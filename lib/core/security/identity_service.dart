import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';

import '../runtime/account_membership_update_payload.dart';
import 'account_identity.dart';
import 'identity_key_store.dart';
import 'identity_membership_crypto.dart';
import 'identity_storage_support.dart';

export 'identity_key_store.dart';

class _IdentityState {
  final AccountIdentity home;
  final AccountIdentity active;

  const _IdentityState({required this.home, required this.active});
}

class IdentityService {
  static const signingKeyStorageKey = "peerlink.identity.signing.ed25519";
  static const agreementKeyStorageKey = "peerlink.identity.agreement.x25519";
  static const installIdStorageKey = "peerlink.identity.installation.id.v1";
  static const accountIdentityStorageKey = "peerlink.account.identity.v1";
  static const homeAccountIdentityStorageKey =
      "peerlink.account.identity.home.v1";

  late final SimpleKeyPair _signingKeyPair;
  late final SimplePublicKey _signingPublicKey;
  late final SimpleKeyPair _agreementKeyPair;
  late final SimplePublicKey _agreementPublicKey;
  late final String nodeId;
  late final String installationId;
  late AccountIdentity accountIdentity;
  late AccountIdentity _homeAccountIdentity;

  final IdentityKeyStore _keyStore;
  final _ed25519 = Ed25519();
  final _x25519 = X25519();
  final _sha256 = Sha256();
  late final IdentityStorageSupport _storageSupport;
  late final IdentityMembershipCrypto _membershipCrypto;
  String? _fcmTokenHash;
  String? _endpointId;
  bool _initialized = false;

  /// Создает сервис identity с возможностью подменить key-store (например, в тестах).
  IdentityService({IdentityKeyStore? keyStore})
    : _keyStore = keyStore ?? const SecureIdentityKeyStore() {
    _storageSupport = IdentityStorageSupport(
      keyStore: _keyStore,
      ed25519: _ed25519,
      x25519: _x25519,
      signingKeyStorageKey: signingKeyStorageKey,
      agreementKeyStorageKey: agreementKeyStorageKey,
      installIdStorageKey: installIdStorageKey,
    );
    _membershipCrypto = IdentityMembershipCrypto(algorithm: _ed25519);
  }

  /// Инициализирует identity и загружает/генерирует ключевые пары.
  Future<void> initialize({String? fcmToken}) async {
    if (_initialized) {
      if (fcmToken != null) {
        await updateMessagingEndpoint(fcmToken);
      }
      return;
    }

    _signingKeyPair = await _storageSupport.loadOrCreateSigningKeyPair();
    _signingPublicKey = await _signingKeyPair.extractPublicKey();
    _agreementKeyPair = await _storageSupport.loadOrCreateAgreementKeyPair();
    _agreementPublicKey = await _agreementKeyPair.extractPublicKey();
    installationId = await _storageSupport.loadOrCreateInstallationId();
    nodeId = await _deriveStablePeerId(_signingPublicKey, installationId);
    if (fcmToken != null) {
      await updateMessagingEndpoint(fcmToken);
    }
    final state = await _loadOrCreateIdentityState();
    _homeAccountIdentity = state.home;
    accountIdentity = state.active;
    _initialized = true;
  }

  SimpleKeyPair get signingKeyPair => _signingKeyPair;

  SimplePublicKey get publicKey => _signingPublicKey;
  SimplePublicKey get signingPublicKey => _signingPublicKey;
  SimpleKeyPair get agreementKeyPair => _agreementKeyPair;
  SimplePublicKey get agreementPublicKey => _agreementPublicKey;
  String? get endpointId => _endpointId;
  String? get fcmTokenHash => _fcmTokenHash;
  String get accountId => accountIdentity.accountId;
  String get activeAccountId => accountIdentity.accountId;
  String get homeAccountId => _homeAccountIdentity.accountId;
  String get deviceId => nodeId;

  Future<AccountIdentity> resetToNewLocalAccount() async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before resetting account identity',
      );
    }
    final freshIdentity = AccountIdentity(
      accountId: _storageSupport.generateAccountId(),
      devices: const <AccountDeviceIdentity>[],
    );
    _homeAccountIdentity = await _persistCurrentDevice(
      freshIdentity,
      storageKey: homeAccountIdentityStorageKey,
      syncHomeSnapshot: false,
    );
    accountIdentity = await _persistCurrentDevice(_homeAccountIdentity);
    return accountIdentity;
  }

  Future<void> clearPersistedIdentity({
    required bool preserveDeviceKeys,
  }) async {
    await _keyStore.delete(accountIdentityStorageKey);
    await _keyStore.delete(homeAccountIdentityStorageKey);
    if (!preserveDeviceKeys) {
      await _keyStore.delete(installIdStorageKey);
      await _keyStore.delete(signingKeyStorageKey);
      await _keyStore.delete(agreementKeyStorageKey);
    }
  }

  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before issuing pairing approval',
      );
    }
    final normalizedSessionId = sessionId.trim();
    if (normalizedSessionId.isEmpty) {
      throw const FormatException('Pairing approval has no sessionId');
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final enrolledDevice = requestedDevice.copyWith(
      createdAtMs: requestedDevice.createdAtMs == 0
          ? nowMs
          : requestedDevice.createdAtMs,
      updatedAtMs: nowMs,
      approvedByDeviceId: nodeId,
      approvedAtMs: nowMs,
      enrollmentSessionId: normalizedSessionId,
      membershipSignature: await _membershipCrypto.createMembershipSignature(
        accountId: accountIdentity.accountId,
        device: requestedDevice,
        approvedByDeviceId: nodeId,
        approvedAtMs: nowMs,
        sessionId: normalizedSessionId,
        signerKeyPair: _signingKeyPair,
      ),
      isCurrentDevice: false,
    );
    final nextIdentity = accountIdentity
        .upsertDevice(enrolledDevice)
        .bumpMembershipVersion()
        .withCurrentDevice(nodeId);
    accountIdentity = await _persistCurrentDevice(nextIdentity);
    return accountIdentity;
  }

  Future<AccountIdentity> applyApprovedPairingAccountIdentity({
    required AccountIdentity incoming,
    required String expectedSessionId,
    required String expectedAccountId,
  }) async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before applying pairing approval',
      );
    }
    final normalizedAccountId = expectedAccountId.trim();
    final normalizedSessionId = expectedSessionId.trim();
    if (normalizedAccountId.isEmpty || normalizedSessionId.isEmpty) {
      throw const FormatException(
        'Pairing approval is missing account/session binding',
      );
    }
    if (incoming.accountId.trim() != normalizedAccountId) {
      throw const FormatException('Pairing approval accountId mismatch');
    }

    final localCurrent = accountIdentity.deviceById(nodeId);
    final approvedCurrent = incoming.deviceById(nodeId);
    if (localCurrent == null || approvedCurrent == null) {
      throw const FormatException(
        'Pairing approval does not contain the current device',
      );
    }
    if (approvedCurrent.deviceId != nodeId ||
        approvedCurrent.peerId != nodeId ||
        approvedCurrent.signingPublicKey != localCurrent.signingPublicKey ||
        approvedCurrent.agreementPublicKey != localCurrent.agreementPublicKey) {
      throw const FormatException(
        'Pairing approval does not match the current device keys',
      );
    }

    final approvedByDeviceId = approvedCurrent.approvedByDeviceId?.trim();
    final approvedAtMs = approvedCurrent.approvedAtMs;
    final membershipSignature = approvedCurrent.membershipSignature?.trim();
    final enrollmentSessionId = approvedCurrent.enrollmentSessionId?.trim();
    if (approvedByDeviceId == null ||
        approvedByDeviceId.isEmpty ||
        approvedAtMs == null ||
        membershipSignature == null ||
        membershipSignature.isEmpty ||
        enrollmentSessionId == null ||
        enrollmentSessionId.isEmpty) {
      throw const FormatException(
        'Pairing approval has no signed membership proof',
      );
    }
    if (enrollmentSessionId != normalizedSessionId) {
      throw const FormatException('Pairing approval sessionId mismatch');
    }

    final approver = incoming.deviceById(approvedByDeviceId);
    final approverSigningKey = approver?.signingPublicKey?.trim();
    if (approver == null ||
        approverSigningKey == null ||
        approverSigningKey.isEmpty) {
      throw const FormatException(
        'Pairing approval approver device is missing or unsigned',
      );
    }

    final verified = await _membershipCrypto.verifyMembershipSignature(
      accountId: incoming.accountId,
      device: approvedCurrent,
      approvedByDeviceId: approvedByDeviceId,
      approvedAtMs: approvedAtMs,
      sessionId: enrollmentSessionId,
      membershipSignature: membershipSignature,
      signerPublicKeyBase64: approverSigningKey,
    );
    if (!verified) {
      throw const FormatException('Pairing approval membership proof invalid');
    }

    accountIdentity = await _persistCurrentDevice(
      incoming.withCurrentDevice(nodeId),
    );
    return accountIdentity;
  }

  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  }) async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before issuing account revocation',
      );
    }
    final revoked = revokedDeviceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != nodeId)
        .toSet();
    if (revoked.isEmpty) {
      return accountIdentity;
    }
    final nextIdentity = accountIdentity
        .removeDevices(revoked)
        .bumpMembershipVersion()
        .withCurrentDevice(nodeId);
    accountIdentity = await _persistCurrentDevice(nextIdentity);
    return accountIdentity;
  }

  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before signing account updates',
      );
    }
    return _membershipCrypto.signAccountMembershipUpdate(
      identity: identity,
      actorDeviceId: nodeId,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
      signerKeyPair: _signingKeyPair,
    );
  }

  Future<AccountIdentity> applyAccountMembershipUpdate({
    required AccountIdentity incoming,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  }) async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before applying account updates',
      );
    }
    final normalizedActorDeviceId = actorDeviceId.trim();
    final normalizedAction = action.trim();
    final normalizedSignature = signature.trim();
    final normalizedAffectedDeviceIds = affectedDeviceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (incoming.accountId.trim() != accountIdentity.accountId.trim()) {
      throw const FormatException(
        'Account membership update accountId mismatch',
      );
    }
    if (incoming.membershipVersion < accountIdentity.membershipVersion) {
      throw const FormatException('Account membership update is stale');
    }
    if (incoming.membershipVersion == accountIdentity.membershipVersion) {
      final normalizedIncoming = incoming.withCurrentDevice(nodeId);
      final normalizedCurrent = accountIdentity.withCurrentDevice(nodeId);
      if (jsonEncode(normalizedIncoming.toJson()) ==
          jsonEncode(normalizedCurrent.toJson())) {
        return accountIdentity;
      }
      throw const FormatException(
        'Account membership update conflicts with current membership version',
      );
    }
    if (normalizedActorDeviceId.isEmpty ||
        normalizedAction.isEmpty ||
        normalizedSignature.isEmpty ||
        updatedAtMs <= 0) {
      throw const FormatException('Account membership update is incomplete');
    }
    final actor = accountIdentity.deviceById(normalizedActorDeviceId);
    final actorSigningKey = actor?.signingPublicKey?.trim();
    if (actor == null || actorSigningKey == null || actorSigningKey.isEmpty) {
      throw const FormatException(
        'Account membership update actor device is missing or unsigned',
      );
    }
    if (incoming.deviceById(normalizedActorDeviceId) == null) {
      throw const FormatException(
        'Account membership update removes the actor device',
      );
    }
    final verified = await _membershipCrypto
        .verifyAccountMembershipUpdateSignature(
          identity: incoming,
          actorDeviceId: normalizedActorDeviceId,
          action: normalizedAction,
          affectedDeviceIds: normalizedAffectedDeviceIds,
          updatedAtMs: updatedAtMs,
          signature: normalizedSignature,
          signerPublicKeyBase64: actorSigningKey,
        );
    if (!verified) {
      throw const FormatException(
        'Account membership update signature invalid',
      );
    }
    if (normalizedAction ==
        AccountMembershipUpdatePayload.revokeDevicesAction) {
      for (final revokedDeviceId in normalizedAffectedDeviceIds) {
        if (incoming.deviceById(revokedDeviceId) != null) {
          throw const FormatException(
            'Revoked device still exists in updated account membership',
          );
        }
      }
    }
    if (normalizedAction == AccountMembershipUpdatePayload.addDevicesAction) {
      for (final addedDeviceId in normalizedAffectedDeviceIds) {
        if (incoming.deviceById(addedDeviceId) == null) {
          throw const FormatException(
            'Added device is missing in updated account membership',
          );
        }
      }
    }
    if (incoming.deviceById(nodeId) == null) {
      accountIdentity = await _restoreHomeAccountIdentity();
      return accountIdentity;
    }
    accountIdentity = await _persistCurrentDevice(
      incoming.withCurrentDevice(nodeId),
    );
    return accountIdentity;
  }

  Map<String, dynamic> identityProfileJson() {
    final signingPublicKeyBase64 = base64Encode(_signingPublicKey.bytes);
    final agreementPublicKeyBase64 = base64Encode(_agreementPublicKey.bytes);
    return <String, dynamic>{
      'schemaVersion': 2,
      'accountId': accountIdentity.accountId,
      'activeAccountId': accountIdentity.accountId,
      'homeAccountId': _homeAccountIdentity.accountId,
      'deviceId': nodeId,
      'stableUserId': nodeId,
      'publicKey': signingPublicKeyBase64,
      'agreementPublicKey': agreementPublicKeyBase64,
      'deviceInstallIdHash': _sha256Hex(utf8.encode(installationId)),
      'accountIdentity': accountIdentity.toJson(),
      'endpoint': <String, dynamic>{
        'endpointId': _endpointId,
        'push': <String, dynamic>{
          'provider': 'fcm',
          'tokenHash': _fcmTokenHash,
        },
      },
    };
  }

  Future<void> updateMessagingEndpoint(String? fcmToken) async {
    final normalized = fcmToken?.trim();
    if (normalized == null || normalized.isEmpty) {
      _fcmTokenHash = null;
      _endpointId = null;
      if (_initialized) {
        accountIdentity = await _persistCurrentDevice(accountIdentity);
      }
      return;
    }
    _fcmTokenHash = _sha256Hex(utf8.encode(normalized));
    final endpointSource = utf8.encode('endpoint:v2:$nodeId:$normalized');
    _endpointId = _sha256Base64Url(endpointSource).substring(0, 32);
    if (_initialized) {
      accountIdentity = await _persistCurrentDevice(accountIdentity);
    }
  }

  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity incoming) async {
    if (!_initialized) {
      throw StateError(
        'IdentityService must be initialized before merging account identity',
      );
    }
    final incomingAccountId = incoming.accountId.trim();
    if (incomingAccountId.isEmpty) {
      throw const FormatException('Incoming account identity has no accountId');
    }

    final mergedDevicesById = <String, AccountDeviceIdentity>{};
    void addImportedDevice(AccountDeviceIdentity device) {
      final deviceId = device.deviceId.trim();
      if (deviceId.isEmpty) {
        return;
      }
      mergedDevicesById[deviceId] = device.copyWith(isCurrentDevice: false);
    }

    for (final device in incoming.devices) {
      addImportedDevice(device);
    }
    final localCurrentDevice = accountIdentity.deviceById(nodeId);
    if (localCurrentDevice != null) {
      addImportedDevice(localCurrentDevice);
    }
    if (incomingAccountId == accountIdentity.accountId) {
      for (final device in accountIdentity.devices) {
        addImportedDevice(device);
      }
    }

    final displayName = incoming.displayName.isNotEmpty
        ? incoming.displayName
        : accountIdentity.displayName;
    final base = AccountIdentity(
      membershipVersion:
          incoming.membershipVersion > accountIdentity.membershipVersion
          ? incoming.membershipVersion
          : accountIdentity.membershipVersion,
      accountId: incomingAccountId,
      displayName: displayName,
      devices: mergedDevicesById.values.toList(growable: false),
    );
    accountIdentity = await _persistCurrentDevice(base);
    return accountIdentity;
  }

  /// Новый стабильный userId: SHA-256(publicKey + installationId).
  Future<String> _deriveStablePeerId(
    SimplePublicKey key,
    String installId,
  ) async {
    final signingKey = base64Encode(key.bytes);
    final payload = utf8.encode('uid:v2:$signingKey:$installId');
    final hash = await _sha256.hash(payload);
    return base64UrlEncode(hash.bytes).substring(0, 32);
  }

  Future<_IdentityState> _loadOrCreateIdentityState() async {
    final existingActive = await _readStoredAccountIdentity(
      accountIdentityStorageKey,
    );
    final existingHome = await _readStoredAccountIdentity(
      homeAccountIdentityStorageKey,
    );
    final fallback = existingActive ?? existingHome;
    final base = fallback != null && fallback.accountId.isNotEmpty
        ? fallback
        : AccountIdentity(
            accountId: _storageSupport.generateAccountId(),
            membershipVersion: 1,
            devices: const <AccountDeviceIdentity>[],
          );
    final resolvedHome =
        existingHome != null && existingHome.accountId.isNotEmpty
        ? existingHome
        : base;
    _homeAccountIdentity = await _persistCurrentDevice(
      resolvedHome,
      storageKey: homeAccountIdentityStorageKey,
      syncHomeSnapshot: false,
    );
    final resolvedActive =
        existingActive != null && existingActive.accountId.isNotEmpty
        ? existingActive
        : _homeAccountIdentity;
    final persistedActive = await _persistCurrentDevice(
      resolvedActive,
      syncHomeSnapshot:
          resolvedActive.accountId == _homeAccountIdentity.accountId,
    );
    return _IdentityState(home: _homeAccountIdentity, active: persistedActive);
  }

  Future<AccountIdentity> _persistCurrentDevice(
    AccountIdentity identity, {
    String storageKey = accountIdentityStorageKey,
    bool syncHomeSnapshot = true,
  }) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final existingDevice = identity.deviceById(nodeId);
    final currentDevice = AccountDeviceIdentity(
      deviceId: nodeId,
      peerId: nodeId,
      signingPublicKey: base64Encode(_signingPublicKey.bytes),
      agreementPublicKey: base64Encode(_agreementPublicKey.bytes),
      endpointId: _endpointId,
      fcmTokenHash: _fcmTokenHash,
      approvedByDeviceId: existingDevice?.approvedByDeviceId,
      approvedAtMs: existingDevice?.approvedAtMs,
      enrollmentSessionId: existingDevice?.enrollmentSessionId,
      membershipSignature: existingDevice?.membershipSignature,
      createdAtMs: existingDevice?.createdAtMs ?? nowMs,
      updatedAtMs: nowMs,
      isCurrentDevice: true,
    );
    final updated = identity.upsertDevice(currentDevice);
    await _storageSupport.writeAccountIdentity(storageKey, updated);
    if (storageKey == homeAccountIdentityStorageKey) {
      _homeAccountIdentity = updated;
    } else if (syncHomeSnapshot &&
        updated.accountId.trim().isNotEmpty &&
        updated.accountId == _homeAccountIdentity.accountId) {
      _homeAccountIdentity = await _persistCurrentDevice(
        updated.withCurrentDevice(nodeId),
        storageKey: homeAccountIdentityStorageKey,
        syncHomeSnapshot: false,
      );
    }
    return updated;
  }

  Future<AccountIdentity> _restoreHomeAccountIdentity() async {
    final restoredHome = await _persistCurrentDevice(
      _homeAccountIdentity.withCurrentDevice(nodeId),
    );
    _homeAccountIdentity = restoredHome;
    return restoredHome;
  }

  Future<AccountIdentity?> _readStoredAccountIdentity(String storageKey) async {
    return _storageSupport.readStoredAccountIdentity(storageKey);
  }

  String _sha256Hex(List<int> bytes) {
    final digest = sha256.convert(bytes).bytes;
    return digest
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  String _sha256Base64Url(List<int> bytes) {
    final digest = sha256.convert(bytes).bytes;
    return base64UrlEncode(digest);
  }
}
