import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/security/account_identity.dart';
import 'package:peerlink/core/security/identity_service.dart';
import 'package:peerlink/core/security/session_crypto.dart';
import 'package:peerlink/core/security/session_manager.dart';
import 'package:peerlink/core/security/signature_service.dart';

void main() {
  test('initialize creates account identity with current device', () async {
    final store = _MemoryIdentityKeyStore();
    final identity = IdentityService(keyStore: store);

    await identity.initialize(fcmToken: 'token-1');

    expect(identity.accountId, isNotEmpty);
    expect(identity.deviceId, identity.nodeId);
    expect(identity.accountIdentity.devices, hasLength(1));

    final device = identity.accountIdentity.devices.single;
    expect(device.deviceId, identity.nodeId);
    expect(device.peerId, identity.nodeId);
    expect(device.endpointId, identity.endpointId);
    expect(device.fcmTokenHash, identity.fcmTokenHash);
    expect(device.isCurrentDevice, isTrue);

    final raw = store.values[IdentityService.accountIdentityStorageKey];
    expect(raw, isNotNull);
    final persisted = AccountIdentity.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw!) as Map),
    );
    expect(persisted.accountId, identity.accountId);
    expect(persisted.devices.single.deviceId, identity.nodeId);

    final rawHome = store.values[IdentityService.homeAccountIdentityStorageKey];
    expect(rawHome, isNotNull);
    final persistedHome = AccountIdentity.fromJson(
      Map<String, dynamic>.from(jsonDecode(rawHome!) as Map),
    );
    expect(persistedHome.accountId, identity.homeAccountId);
    expect(identity.homeAccountId, identity.activeAccountId);
  });

  test('updateMessagingEndpoint refreshes persisted current device', () async {
    final store = _MemoryIdentityKeyStore();
    final identity = IdentityService(keyStore: store);
    await identity.initialize();

    await identity.updateMessagingEndpoint('token-2');

    final raw = store.values[IdentityService.accountIdentityStorageKey];
    final persisted = AccountIdentity.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw!) as Map),
    );

    expect(persisted.devices.single.endpointId, identity.endpointId);
    expect(persisted.devices.single.fcmTokenHash, identity.fcmTokenHash);
  });

  test(
    'identity bundle v3 keeps v2 peer id and enables offline session',
    () async {
      final alice = IdentityService(keyStore: _MemoryIdentityKeyStore());
      final bob = IdentityService(keyStore: _MemoryIdentityKeyStore());
      await alice.initialize();
      await bob.initialize();

      final aliceBundle = alice.identityBundleV3Json;
      final bobBundle = bob.identityBundleV3Json;

      expect(aliceBundle['peerId'], alice.nodeId);
      expect(aliceBundle['signingPublicKey'], isNotEmpty);
      expect(aliceBundle['agreementPublicKey'], isNotEmpty);
      expect(aliceBundle['signature'], isNotEmpty);

      final aliceSessions = SessionManager(
        identity: alice,
        crypto: SessionCrypto(),
        signatures: SignatureService(),
        peerIdentityStore: _MemoryPeerIdentityStore(),
      );
      final bobSessions = SessionManager(
        identity: bob,
        crypto: SessionCrypto(),
        signatures: SignatureService(),
        peerIdentityStore: _MemoryPeerIdentityStore(),
      );

      expect(
        await aliceSessions.trustPeerIdentityBundleV3(
          bobBundle,
          expectedPeerId: bob.nodeId,
        ),
        isTrue,
      );
      expect(
        await bobSessions.trustPeerIdentityBundleV3(
          aliceBundle,
          expectedPeerId: alice.nodeId,
        ),
        isTrue,
      );
      expect(await aliceSessions.ensureSession(bob.nodeId), isTrue);
      expect(await bobSessions.ensureSession(alice.nodeId), isTrue);

      final encrypted = await aliceSessions.encrypt(
        bob.nodeId,
        Uint8List.fromList(utf8.encode('hello')),
      );
      final decrypted = await bobSessions.decrypt(alice.nodeId, encrypted);
      expect(utf8.decode(decrypted), 'hello');
    },
  );

  test(
    'mergeAccountIdentity adopts account id and keeps current device',
    () async {
      final store = _MemoryIdentityKeyStore();
      final identity = IdentityService(keyStore: store);
      await identity.initialize(fcmToken: 'local-token');
      final localDeviceId = identity.deviceId;

      final merged = await identity.mergeAccountIdentity(
        AccountIdentity(
          accountId: 'shared-account',
          displayName: 'Shared user',
          devices: <AccountDeviceIdentity>[
            AccountDeviceIdentity(
              deviceId: 'phone-device',
              peerId: 'phone-device',
              createdAtMs: 10,
              updatedAtMs: 20,
              isCurrentDevice: true,
            ),
          ],
        ),
      );

      expect(identity.accountId, 'shared-account');
      expect(merged.displayName, 'Shared user');
      expect(merged.devices, hasLength(2));
      expect(merged.deviceById('phone-device')!.isCurrentDevice, isFalse);
      expect(merged.deviceById(localDeviceId)!.isCurrentDevice, isTrue);
      expect(merged.deviceById(localDeviceId)!.endpointId, identity.endpointId);

      final raw = store.values[IdentityService.accountIdentityStorageKey];
      final persisted = AccountIdentity.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw!) as Map),
      );
      expect(persisted.accountId, 'shared-account');
      expect(persisted.deviceById(localDeviceId)!.isCurrentDevice, isTrue);
      expect(persisted.deviceById('phone-device')!.isCurrentDevice, isFalse);
    },
  );

  test(
    'applyApprovedPairingAccountIdentity validates enrollment proof',
    () async {
      final trustedStore = _MemoryIdentityKeyStore();
      final newStore = _MemoryIdentityKeyStore();
      final trusted = IdentityService(keyStore: trustedStore);
      final newcomer = IdentityService(keyStore: newStore);

      await trusted.initialize(fcmToken: 'trusted-token');
      await newcomer.initialize(fcmToken: 'new-token');

      final requestedDevice = newcomer.accountIdentity.deviceById(
        newcomer.deviceId,
      )!;
      final approvedIdentity = await trusted
          .issueApprovedPairingAccountIdentity(
            requestedDevice: requestedDevice.copyWith(isCurrentDevice: false),
            sessionId: 'session-1',
          );

      final adopted = await newcomer.applyApprovedPairingAccountIdentity(
        incoming: approvedIdentity,
        expectedSessionId: 'session-1',
        expectedAccountId: trusted.accountId,
      );

      final currentDevice = adopted.deviceById(newcomer.deviceId)!;
      expect(adopted.accountId, trusted.accountId);
      expect(currentDevice.isCurrentDevice, isTrue);
      expect(currentDevice.approvedByDeviceId, trusted.deviceId);
      expect(currentDevice.membershipSignature, isNotEmpty);
    },
  );

  test('revoke restores original first-launch home account', () async {
    final trustedStore = _MemoryIdentityKeyStore();
    final newcomerStore = _MemoryIdentityKeyStore();
    final trusted = IdentityService(keyStore: trustedStore);
    final newcomer = IdentityService(keyStore: newcomerStore);

    await trusted.initialize(fcmToken: 'trusted-token');
    await newcomer.initialize(fcmToken: 'new-token');

    final newcomerOriginalHomeAccountId = newcomer.homeAccountId;
    final requestedDevice = newcomer.accountIdentity.deviceById(
      newcomer.deviceId,
    )!;
    final approvedIdentity = await trusted.issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice.copyWith(isCurrentDevice: false),
      sessionId: 'session-restore-home',
    );

    await newcomer.applyApprovedPairingAccountIdentity(
      incoming: approvedIdentity,
      expectedSessionId: 'session-restore-home',
      expectedAccountId: trusted.accountId,
    );

    expect(newcomer.activeAccountId, trusted.accountId);
    expect(newcomer.homeAccountId, newcomerOriginalHomeAccountId);

    final trustedUpdatedIdentity = await trusted.issueRevokedAccountIdentity(
      revokedDeviceIds: <String>[newcomer.deviceId],
    );
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final signature = await trusted.signAccountMembershipUpdate(
      identity: trustedUpdatedIdentity,
      action: 'revokeDevices',
      affectedDeviceIds: <String>[newcomer.deviceId],
      updatedAtMs: updatedAtMs,
    );

    await newcomer.applyAccountMembershipUpdate(
      incoming: trustedUpdatedIdentity,
      actorDeviceId: trusted.deviceId,
      action: 'revokeDevices',
      affectedDeviceIds: <String>[newcomer.deviceId],
      updatedAtMs: updatedAtMs,
      signature: signature,
    );

    expect(newcomer.activeAccountId, newcomerOriginalHomeAccountId);
    expect(newcomer.homeAccountId, newcomerOriginalHomeAccountId);
    expect(
      newcomer.accountIdentity.deviceById(newcomer.deviceId)!.isCurrentDevice,
      isTrue,
    );
  });
}

class _MemoryPeerIdentityStore implements PeerIdentityStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String peerId) async => values[peerId];

  @override
  Future<void> write(String peerId, String value) async {
    values[peerId] = value;
  }
}

class _MemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
