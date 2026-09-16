// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';

import 'qr_payload_encoder.dart';
import 'package:peerlink/features/settings/application/settings_account_membership_service.dart';
import 'package:peerlink/features/settings/application/settings_controller_dependencies.dart';
import 'package:peerlink/features/settings/application/settings_controller_models.dart';
import 'package:peerlink/features/settings/application/settings_pairing_flow_service.dart';
import 'package:peerlink/features/settings/application/settings_pairing_state_service.dart';
import 'package:peerlink/features/settings/application/settings_read_model_service.dart';
import 'package:peerlink/features/settings/application/settings_server_config_service.dart';
import 'package:peerlink/features/settings/application/settings_storage_maintenance_service.dart';

import 'settings_deep_link_codec.dart';
import 'settings_invite_codec.dart';
export 'package:peerlink/features/settings/application/settings_controller_models.dart';

import '../../core/runtime/account_device_event.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/app_data_cleaner_service.dart';
import '../../core/runtime/app_storage_stats.dart';
import '../../core/node/node_capability_apis.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/peer_access_control_service.dart';
import '../../core/runtime/server_config_payload.dart';
import '../../core/runtime/server_availability.dart';
import '../../core/runtime/server_health_coordinator.dart';
import '../../core/runtime/push_token_service.dart';
import '../../core/runtime/push_server_sharing_preferences.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/runtime/terms_acceptance_service.dart';
import '../../core/security/account_identity.dart';
import '../../core/signaling/signaling_service.dart';
import '../../core/turn/turn_server_config.dart';
import '../localization/app_strings.dart';

/// Контроллер экрана настроек: peerId и bootstrap-серверы.
class SettingsController {
  static const String _inviteUsernameKey =
      'peerlink.profile.invite_username.v1';
  static const String _inviteWebBaseUrl = String.fromEnvironment(
    'PEERLINK_INVITE_WEB_BASE_URL',
    defaultValue: 'https://simplegear.org/invite',
  );
  static const String _serverConfigWebBaseUrl = String.fromEnvironment(
    'PEERLINK_SERVER_CONFIG_WEB_BASE_URL',
    defaultValue: 'https://simplegear.org/config',
  );
  static const String _accountPairingWebBaseUrl = String.fromEnvironment(
    'PEERLINK_PAIR_WEB_BASE_URL',
    defaultValue: 'https://simplegear.org/pair',
  );
  static const Duration _accountPairingSessionTtl = Duration(minutes: 5);

  final IdentityApi identity;
  final NetworkApi network;
  final MessagingApi messaging;
  final StorageService storage;
  final Future<void> Function(String username)? onInviteUsernameUpdated;
  final Future<void> Function(String peerId, String username)?
  onInviteUsernamePeerRequested;
  late final ServerHealthCoordinator _health;
  late final AppDataCleanerService _dataCleaner;
  late final PushTokenService _pushTokens;
  late final SettingsPairingStateService _pairingStateService;
  late final SettingsPairingFlowService _pairingFlow;
  late final SettingsReadModelService _readModelService;
  late final SettingsServerConfigService _serverConfigService;
  late final SettingsStorageMaintenanceService _storageMaintenanceService;
  late final SettingsAccountMembershipService _accountMembershipService;
  late final PeerAccessControlService _accessControl;
  late final TermsAcceptanceService _termsAcceptance;
  late final String Function(String peerId, {String? fallback})
  _contactDisplayName;

  SettingsController({
    required this.identity,
    required this.network,
    required this.messaging,
    required this.storage,
    required SettingsControllerDependenciesFactory dependenciesFactory,
    this.onInviteUsernameUpdated,
    this.onInviteUsernamePeerRequested,
  }) {
    final dependencies = dependenciesFactory(
      identity: identity,
      network: network,
      storage: storage,
      connectedBootstrapServers: () => connectedBootstrapServers,
      readSettingValue: readSettingValue,
      writeSettingValue: writeSettingValue,
      deleteSettingValue: deleteSettingValue,
      currentConfiguredServerConfigPayload:
          currentConfiguredServerConfigPayload,
      importServerConfigPayload: importServerConfigPayload,
      peerId: () => peerId,
      accountId: () => accountId,
      deviceId: () => deviceId,
      endpointId: () => endpointId,
      fcmTokenHash: () => fcmTokenHash,
      accountIdentity: () => accountIdentity,
      ensurePrimaryAccountDeviceForManagement:
          _ensurePrimaryAccountDeviceForManagement,
      issueApprovedPairingAccountIdentity: issueApprovedPairingAccountIdentity,
      applyApprovedPairingAccountIdentity: applyApprovedPairingAccountIdentity,
      sendAccountPairingControlMessage: sendAccountPairingControlMessage,
      issueRevokedAccountIdentity: issueRevokedAccountIdentity,
      signAccountMembershipUpdate: signAccountMembershipUpdate,
      applyAccountMembershipUpdate: applyAccountMembershipUpdate,
    );
    _health = dependencies.health;
    _dataCleaner = dependencies.dataCleaner;
    _pushTokens = dependencies.pushTokens;
    _accessControl = dependencies.accessControl;
    _termsAcceptance = dependencies.termsAcceptance;
    _readModelService = dependencies.readModelService;
    _serverConfigService = dependencies.serverConfigService;
    _storageMaintenanceService = dependencies.storageMaintenanceService;
    _pairingStateService = dependencies.pairingStateService;
    _pairingFlow = dependencies.pairingFlow;
    _accountMembershipService = dependencies.accountMembershipService;
    _contactDisplayName = dependencies.contactDisplayName;
  }

  SecureStorageBox get _settings => storage.getSettings();

  bool get allowMessagesOnlyFromContacts =>
      _accessControl.allowMessagesOnlyFromContacts;
  List<BlockedPeer> get blockedPeers => _accessControl.blockedPeers();
  int get blockedPeersCount => blockedPeers.length;
  String get termsVersion => TermsAcceptanceService.currentTermsVersion;
  String get inviteUsername {
    final value = readSettingValue(_inviteUsernameKey);
    return value is String ? value.trim() : '';
  }

  Future<void> updateInviteUsername(String value) async {
    final normalized = value.trim();
    if (normalized.length > 64 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const FormatException('Недопустимое имя в PeerLink');
    }
    await writeSettingValue(_inviteUsernameKey, normalized);
    final notifyUsernameUpdated = onInviteUsernameUpdated;
    if (notifyUsernameUpdated != null) {
      unawaited(
        _notifyInviteUsernameUpdated(notifyUsernameUpdated, normalized),
      );
    }
  }

  Future<void> _notifyInviteUsernameUpdated(
    Future<void> Function(String username) notify,
    String username,
  ) async {
    try {
      await notify(username);
    } catch (_) {
      // Рассылка профиля best-effort и не должна влиять на сохранение имени.
    }
  }

  Future<void> sendInviteUsernameToPeer(String peerId) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) return;
    await onInviteUsernamePeerRequested?.call(normalizedPeerId, inviteUsername);
  }

  bool get isCurrentTermsAccepted => _termsAcceptance.isCurrentVersionAccepted;
  TermsAcceptanceState get termsAcceptanceState => _termsAcceptance.state;

  Future<void> setAllowMessagesOnlyFromContacts(bool enabled) async {
    await _accessControl.setAllowMessagesOnlyFromContacts(enabled);
    await network.syncPushDeviceState(
      reason: 'allow_contacts_toggle',
      forcePolicy: true,
    );
  }

  Future<void> unblockPeer(String peerId) async {
    await _accessControl.unblockPeer(peerId);
    await network.syncPushDeviceState(
      reason: 'unblock_peer',
      forcePolicy: true,
    );
  }

  Future<void> acceptCurrentTerms() {
    return _termsAcceptance.acceptCurrentVersion();
  }

  String blockedPeerDisplayName(String peerId) {
    return _contactDisplayName(peerId, fallback: peerId);
  }

  /// Текущий peerId локального узла.
  String get peerId => identity.peerId;
  String get accountId => identity.accountId;
  String get activeAccountId => identity.activeAccountId;
  String get homeAccountId => identity.homeAccountId;
  String get deviceId => identity.deviceId;
  AccountIdentity get accountIdentity => identity.accountIdentity;
  bool get isPrimaryAccountDevice => activeAccountId == homeAccountId;
  bool get hasChildAccountDevices =>
      accountIdentity.devices.any((device) => device.deviceId != deviceId);
  bool get canUsePairingQrControls => isPrimaryAccountDevice;
  bool get canJoinAnotherAccount => canUsePairingQrControls;
  bool get hasWorkingPairingTransport =>
      bootstrapAvailableCount > 0 && relayAvailableCount > 0;
  int get accountDeviceCount => accountIdentity.devices.length;
  PendingAccountPairingRequest? get pendingAccountPairingRequest =>
      _pairingStateService.pendingAccountPairingRequest;
  List<IncomingAccountPairingRequest> get incomingAccountPairingRequests =>
      _pairingStateService.incomingAccountPairingRequests;
  AccountPairingRequestPayload? get outgoingAccountPairingRequest =>
      _pairingStateService.outgoingAccountPairingRequest;
  AccountPairingApprovalPayload? get approvedAccountPairingPayload =>
      _pairingStateService.approvedAccountPairingPayload;
  AccountPairingRejectedPayload? get rejectedAccountPairingPayload =>
      _pairingStateService.rejectedAccountPairingPayload;
  List<AccountDeviceEvent> get accountDeviceEvents =>
      _pairingStateService.accountDeviceEvents;
  String? get endpointId => identity.endpointId;
  String? get fcmTokenHash => identity.fcmTokenHash;
  String? get fcmToken => _pushTokens.fcmToken;
  String? get apnsToken => _pushTokens.apnsToken;
  String? get voipToken => _pushTokens.voipToken;

  String exportUserQrPayload() {
    return jsonEncode(<String, dynamic>{
      'type': 'peerlink_user_qr_v2',
      'schemaVersion': 2,
      'stableUserId': peerId,
      'peerId': peerId,
      'endpointId': endpointId,
      'fcmTokenHash': fcmTokenHash,
      if (inviteUsername.isNotEmpty) 'displayName': inviteUsername,
      'identityBundleV3': identity.identityBundleV3Json,
    });
  }

  String exportInvitePayload() {
    return SettingsInviteCodec.exportInvitePayload(
      peerId: peerId,
      endpointId: endpointId,
      fcmTokenHash: fcmTokenHash,
      identityBundleV3: identity.identityBundleV3Json,
      serverConfig: ServerConfigPayload.fromJson(
        jsonDecode(exportServerConfigQrPayload()) as Map<String, dynamic>,
      ),
    );
  }

  String exportInviteDeepLink() {
    return SettingsInviteCodec.exportInviteDeepLink(exportInvitePayload());
  }

  String exportInviteShareLink() {
    return SettingsInviteCodec.exportInviteShareLink(
      exportInvitePayload(),
      _inviteWebBaseUrl,
    );
  }

  String exportServerConfigShareLink() {
    final encodedPayload = QrPayloadEncoder.encodeToBase64Url(
      exportServerConfigQrPayload(),
    );
    final baseUri = Uri.parse(_serverConfigWebBaseUrl);
    return baseUri
        .replace(
          queryParameters: <String, String>{
            ...baseUri.queryParameters,
            'payload': encodedPayload,
          },
        )
        .toString();
  }

  String exportServerConfigDeepLink() {
    return QrPayloadEncoder.buildDeepLink(
      scheme: 'peerlink',
      host: 'config',
      payload: QrPayloadEncoder.encodeToBase64Url(
        exportServerConfigQrPayload(),
      ),
    );
  }

  String exportServerConfigShareText(AppStrings strings) {
    return strings.serverConfigShareText(
      exportServerConfigDeepLink(),
      exportServerConfigShareLink(),
    );
  }

  String exportAccountPairingPayload() {
    _ensurePrimaryAccountDeviceForManagement();
    _ensureCanUsePairingQrControls();
    if (!hasWorkingPairingTransport) {
      throw StateError(
        'Showing a pairing QR requires at least one working bootstrap server and one working relay server',
      );
    }
    final currentDevice = accountIdentity.deviceById(deviceId);
    if (currentDevice == null) {
      throw StateError('Current device identity is missing');
    }
    final now = DateTime.now();
    final payload = AccountPairingPayload(
      sessionId: 'pairing-session:${now.microsecondsSinceEpoch}',
      accountId: accountIdentity.accountId,
      displayName: accountIdentity.displayName,
      targetDeviceId: currentDevice.deviceId,
      targetPeerId: currentDevice.peerId,
      targetSigningPublicKey: currentDevice.signingPublicKey,
      serverConfig: currentConfiguredServerConfigPayload(),
      createdAtMs: now.millisecondsSinceEpoch,
      expiresAtMs: now.add(_accountPairingSessionTtl).millisecondsSinceEpoch,
    );
    _pairingStateService.storeActiveAccountPairingSession(payload);
    return jsonEncode(payload.toJson());
  }

  String exportAccountPairingDeepLink() {
    final encodedPayload = _encodedAccountPairingPayload();
    return QrPayloadEncoder.buildDeepLink(
      scheme: 'peerlink',
      host: 'pair',
      payload: encodedPayload,
    );
  }

  String exportAccountPairingShareLink() {
    final encodedPayload = _encodedAccountPairingPayload();
    final baseUri = Uri.parse(_accountPairingWebBaseUrl);
    return baseUri
        .replace(
          queryParameters: <String, String>{
            ...baseUri.queryParameters,
            'payload': encodedPayload,
          },
        )
        .toString();
  }

  String _encodedAccountPairingPayload() {
    return QrPayloadEncoder.encodeToBase64Url(exportAccountPairingPayload());
  }

  bool isAccountPairingDeepLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null && SettingsDeepLinkCodec.isAccountPairingUri(uri);
  }

  AccountPairingPayload parseAccountPairingDeepLink(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('{')) {
      return parseAccountPairingPayload(trimmed);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !SettingsDeepLinkCodec.isAccountPairingUri(uri)) {
      throw const FormatException('Это не привязка устройства PeerLink X');
    }
    final encodedPayload = SettingsDeepLinkCodec.payloadFromUri(uri);
    if (encodedPayload == null || encodedPayload.trim().isEmpty) {
      throw const FormatException('В привязке нет payload');
    }
    final normalizedPayload = base64Url.normalize(encodedPayload.trim());
    final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
    return parseAccountPairingPayload(payloadJson);
  }

  AccountPairingPayload parseAccountPairingPayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат привязки устройства');
    }
    final payload = AccountPairingPayload.fromJson(decoded);
    if (payload.accountId.isEmpty || payload.sessionId.isEmpty) {
      throw const FormatException('В привязке нет accountId или sessionId');
    }
    if (payload.targetDeviceId.isEmpty || payload.targetPeerId.isEmpty) {
      throw const FormatException('В привязке нет доверенного устройства');
    }
    if (payload.isExpired) {
      throw const FormatException('QR привязки устройства уже истек');
    }
    return payload;
  }

  Future<AccountPairingRequestPayload> requestAccountPairingPayload(
    AccountPairingPayload payload,
  ) async {
    _ensureCanJoinAnotherAccount();
    return _pairingFlow.requestAccountPairingPayload(payload);
  }

  Future<AccountPairingRequestPayload> requestAccountPairingDeepLink(
    String raw,
  ) async {
    final payload = parseAccountPairingDeepLink(raw);
    return requestAccountPairingPayload(payload);
  }

  Future<void> approveIncomingAccountPairingRequest(
    IncomingAccountPairingRequest request,
  ) async {
    _ensurePrimaryAccountDeviceForManagement();
    await _pairingFlow.approveIncomingAccountPairingRequest(request);
  }

  Future<void> rejectIncomingAccountPairingRequest(String requestId) async {
    _ensurePrimaryAccountDeviceForManagement();
    await _pairingFlow.rejectIncomingAccountPairingRequest(
      requestId,
      incomingAccountPairingRequests,
    );
  }

  Future<AccountIdentity?> applyApprovedAccountPairingIfAvailable() async {
    final approval = _pairingStateService.approvedAccountPairingPayload;
    if (approval == null) {
      return null;
    }
    await importServerConfigPayload(
      approval.serverConfig,
      mode: ServerConfigImportMode.merge,
    );
    return _pairingFlow.applyApprovedAccountPairingIfAvailable();
  }

  Future<bool> consumeRejectedAccountPairingIfAvailable() async {
    return _pairingFlow.consumeRejectedAccountPairingIfAvailable();
  }

  Future<bool> expireStaleOutgoingAccountPairingIfNeeded() async {
    return _pairingFlow.expireStaleOutgoingAccountPairingIfNeeded();
  }

  Future<PendingAccountPairingRequest> stageAccountPairingPayload(
    AccountPairingPayload payload, {
    int? scannedAtMs,
  }) async {
    return _pairingFlow.stageAccountPairingPayload(
      payload,
      scannedAtMs: scannedAtMs,
    );
  }

  Future<PendingAccountPairingRequest> stageAccountPairingDeepLink(String raw) {
    return stageAccountPairingPayload(parseAccountPairingDeepLink(raw));
  }

  Future<AccountPairingRequestPayload> approvePendingAccountPairing() async {
    _ensureCanJoinAnotherAccount();
    return _pairingFlow.approvePendingAccountPairing();
  }

  Future<void> clearPendingAccountPairingRequest() async {
    await _pairingFlow.clearPendingRequest();
  }

  Future<void> restorePendingAccountPairingRequest() async {
    await _pairingStateService.restorePendingAccountPairingRequest();
  }

  PeerLinkInviteImport parseInviteDeepLink(String raw) {
    return SettingsInviteCodec.parseInviteDeepLink(raw);
  }

  bool isServerConfigDeepLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    return uri != null && SettingsDeepLinkCodec.isServerConfigUri(uri);
  }

  ServerConfigPayload parseServerConfigDeepLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !SettingsDeepLinkCodec.isServerConfigUri(uri)) {
      throw const FormatException('Это не ссылка конфигурации PeerLink X');
    }
    final encodedPayload = SettingsDeepLinkCodec.payloadFromUri(uri);
    if (encodedPayload == null || encodedPayload.trim().isEmpty) {
      throw const FormatException('В ссылке конфигурации нет payload');
    }
    final normalizedPayload = base64Url.normalize(encodedPayload.trim());
    final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
    final decoded = jsonDecode(payloadJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат конфигурации');
    }
    return ServerConfigPayload.fromJson(decoded);
  }

  ServerConfigPayload? tryParseServerConfigFromAnyDeepLinkPayload(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      return null;
    }
    final encodedPayload = SettingsDeepLinkCodec.payloadFromUri(uri);
    if (encodedPayload == null || encodedPayload.trim().isEmpty) {
      return null;
    }
    try {
      final normalizedPayload = base64Url.normalize(encodedPayload.trim());
      final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
      final decoded = jsonDecode(payloadJson);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      if (decoded['type'] != ServerConfigPayload.type ||
          decoded['version'] != ServerConfigPayload.version) {
        return null;
      }
      return ServerConfigPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  PeerLinkInviteImport parseInvitePayload(String raw) {
    return SettingsInviteCodec.parseInvitePayload(raw);
  }

  String? extractPeerIdFromUserQr(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, dynamic>) {
        return trimmed;
      }
      final stableUserId = decoded['stableUserId']?.toString();
      if (stableUserId != null && stableUserId.isNotEmpty) {
        return stableUserId;
      }
      final peerId = decoded['peerId']?.toString();
      if (peerId != null && peerId.isNotEmpty) {
        return peerId;
      }
      return null;
    } catch (_) {
      return trimmed;
    }
  }

  Map<String, dynamic>? extractIdentityBundleV3FromUserQr(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final bundle = decoded['identityBundleV3'];
      return bundle is Map ? Map<String, dynamic>.from(bundle) : null;
    } catch (_) {
      return null;
    }
  }

  String? extractDisplayNameFromUserQr(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is! Map<String, dynamic>) return null;
      final displayName = decoded['displayName']?.toString().trim();
      if (displayName == null ||
          displayName.isEmpty ||
          displayName.length > 64 ||
          RegExp(r'[\x00-\x1F\x7F]').hasMatch(displayName)) {
        return null;
      }
      return displayName;
    } catch (_) {
      return null;
    }
  }

  List<String> get bootstrapPeers => _readModelService.bootstrapPeers;
  List<String> get relayServers => _readModelService.relayServers;
  List<TurnServerConfig> get turnServers => _readModelService.turnServers;
  List<String> get pushServers => _readModelService.pushServers;
  String get appVersionLabel => _readModelService.appVersionLabel;
  AppLogLevel get appLogLevel => AppFileLogger.parseStoredLevel(
    _settings.get(AppFileLogger.logLevelSettingsKey),
  );
  bool get shareServersInPush =>
      PushServerSharingPreferences.shareOutgoingServers(_settings);
  bool get receiveServersFromPush =>
      PushServerSharingPreferences.receiveIncomingServers(_settings);

  Future<void> setShareServersInPush(bool value) {
    return PushServerSharingPreferences.setShareOutgoingServers(
      _settings,
      value,
    );
  }

  Future<void> setReceiveServersFromPush(bool value) {
    return PushServerSharingPreferences.setReceiveIncomingServers(
      _settings,
      value,
    );
  }

  Future<void> addBootstrap(String peer) {
    return _serverConfigService.addBootstrap(peer);
  }

  Future<void> removeBootstrap(String peer) {
    return _serverConfigService.removeBootstrap(peer);
  }

  Future<void> addRelay(String endpoint) {
    return _serverConfigService.addRelay(endpoint);
  }

  Future<void> removeRelay(String endpoint) {
    return _serverConfigService.removeRelay(endpoint);
  }

  Future<void> addTurnServer(TurnServerConfig server) {
    return _serverConfigService.addTurnServer(server);
  }

  Future<void> removeTurnServer(String url) {
    return _serverConfigService.removeTurnServer(url);
  }

  Future<void> addPushServer(String endpoint) async {
    await _serverConfigService.addPushServer(endpoint);
    await network.syncPushDeviceState(
      reason: 'push_server_add',
      forceRegister: true,
      forcePolicy: true,
    );
  }

  Future<void> removePushServer(String endpoint) async {
    await _serverConfigService.removePushServer(endpoint);
    await network.syncPushDeviceState(
      reason: 'push_server_remove',
      forcePolicy: true,
    );
  }

  Future<void> updatePushServer(
    String currentEndpoint, {
    required String host,
    int? port,
  }) async {
    await _serverConfigService.updatePushServer(
      currentEndpoint,
      host: host,
      port: port,
    );
    await network.syncPushDeviceState(
      reason: 'push_server_update',
      forceRegister: true,
      forcePolicy: true,
    );
  }

  Future<void> pausePushServer(String endpoint) async {
    await _serverConfigService.pausePushServer(endpoint);
    await network.syncPushDeviceState(
      reason: 'push_server_pause',
      forcePolicy: true,
    );
  }

  Future<void> resumePushServer(String endpoint) async {
    await _serverConfigService.resumePushServer(endpoint);
    await network.syncPushDeviceState(
      reason: 'push_server_resume',
      forceRegister: true,
      forcePolicy: true,
    );
  }

  ServerConfigImportPreview previewImport(ServerConfigPayload payload) {
    return _serverConfigService.previewImport(payload);
  }

  Future<void> addSelfHostedServersFirst({
    required String bootstrapEndpoint,
    required String relayEndpoint,
    required List<TurnServerConfig> turnServers,
  }) {
    return _serverConfigService.addSelfHostedServersFirst(
      bootstrapEndpoint: bootstrapEndpoint,
      relayEndpoint: relayEndpoint,
      turnServers: turnServers,
    );
  }

  Future<AppStorageBreakdown> loadStorageBreakdown() {
    return _storageMaintenanceService.loadStorageBreakdown();
  }

  Future<void> clearManagedMediaStorage() {
    return _storageMaintenanceService.clearManagedMediaStorage();
  }

  Future<void> clearMessagesDatabase() {
    return _storageMaintenanceService.clearMessagesDatabase();
  }

  Future<void> clearSettingsAndServiceData() {
    return _storageMaintenanceService.clearSettingsAndServiceData();
  }

  Future<void> setAppLogLevel(AppLogLevel level) {
    return AppFileLogger.setLogLevel(level, storage: storage);
  }

  Future<void> revokeAccountDevice(String targetDeviceId) {
    return _accountMembershipService.revokeAccountDevice(targetDeviceId);
  }

  Future<void> revokeAllOtherAccountDevices() {
    return _accountMembershipService.revokeAllOtherAccountDevices();
  }

  Future<void> revokeAccountDevices(Iterable<String> targetDeviceIds) {
    return _accountMembershipService.revokeAccountDevices(targetDeviceIds);
  }

  Future<int> applyIncomingAccountMembershipUpdatesIfAvailable() {
    return _accountMembershipService
        .applyIncomingAccountMembershipUpdatesIfAvailable();
  }

  /// Загружает bootstrap-серверы из storage и применяет их в runtime.
  Future<void> initialize() async {
    await _health.initialize();
    await _pairingStateService.restorePendingAccountPairingRequest();
    await _pairingStateService.cleanupExpiredIncomingAccountPairingRequests();
    await applyIncomingAccountMembershipUpdatesIfAvailable();
    await _readModelService.loadAppVersion();
  }

  /// Invite flow needs an explicit retryable failure when defaults are absent.
  Future<void> ensureInitialServerConfigForInvite() {
    return _health.ensureInitialServerConfigForInvite();
  }

  void dispose() {}

  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity identity) {
    return this.identity.mergeAccountIdentity(identity);
  }

  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) {
    return identity.issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice,
      sessionId: sessionId,
    );
  }

  Future<AccountIdentity> applyApprovedPairingAccountIdentity(
    AccountIdentity identity, {
    required String expectedSessionId,
    required String expectedAccountId,
  }) {
    return this.identity.applyApprovedPairingAccountIdentity(
      incoming: identity,
      expectedSessionId: expectedSessionId,
      expectedAccountId: expectedAccountId,
    );
  }

  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  }) {
    return identity.issueRevokedAccountIdentity(
      revokedDeviceIds: revokedDeviceIds,
    );
  }

  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) {
    return this.identity.signAccountMembershipUpdate(
      identity: identity,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
    );
  }

  Future<AccountIdentity> applyAccountMembershipUpdate({
    required AccountIdentity identity,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  }) {
    return this.identity.applyAccountMembershipUpdate(
      incoming: identity,
      actorDeviceId: actorDeviceId,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
      signature: signature,
    );
  }

  Future<void> sendAccountPairingControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return messaging.sendControlMessage(peerId, kind: kind, text: text);
  }

  void _ensurePrimaryAccountDeviceForManagement() {
    if (!isPrimaryAccountDevice) {
      throw StateError(
        'Account device management is available only on the primary device',
      );
    }
  }

  void _ensureCanJoinAnotherAccount() {
    if (!canJoinAnotherAccount) {
      throw StateError(
        'This device already manages other devices and cannot join another account',
      );
    }
  }

  void _ensureCanUsePairingQrControls() {
    if (!canUsePairingQrControls) {
      throw StateError(
        'Pairing QR controls are available only on a standalone primary device',
      );
    }
  }

  SignalingConnectionStatus get connectionStatus =>
      network.bootstrapConnectionStatus;

  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      network.bootstrapConnectionStatusStream;
  String? get lastError => network.bootstrapLastError;
  Stream<String?> get lastErrorStream => network.bootstrapLastErrorStream;

  String? get activeBootstrapServer => network.activeBootstrapServer;
  List<String> get connectedBootstrapServers =>
      network.connectedBootstrapServers;

  Stream<Map<String, ServerAvailability>> get bootstrapAvailabilityStream =>
      _health.bootstrapAvailabilityStream;
  Stream<Map<String, ServerAvailability>> get relayAvailabilityStream =>
      _health.relayAvailabilityStream;
  Stream<Map<String, ServerAvailability>> get turnAvailabilityStream =>
      _health.turnAvailabilityStream;
  Stream<Map<String, ServerAvailability>> get pushAvailabilityStream =>
      _health.pushAvailabilityStream;

  List<String> get sortedBootstrapPeers {
    return _readModelService.sortedBootstrapPeers;
  }

  int get bootstrapAvailableCount => bootstrapPeers
      .where(
        (endpoint) => bootstrapState(endpoint) == SettingsServerState.connected,
      )
      .length;

  int get bootstrapUnavailableCount =>
      _readModelService.bootstrapUnavailableCount;

  int get relayAvailableCount => relayServers
      .where(
        (endpoint) => relayState(endpoint) == SettingsServerState.connected,
      )
      .length;

  int get relayUnavailableCount => _readModelService.relayUnavailableCount;

  int get turnAvailableCount => _readModelService.turnAvailableCount;

  int get turnUnavailableCount => _readModelService.turnUnavailableCount;

  List<String> get sortedRelayServers => _readModelService.sortedRelayServers;

  List<TurnServerConfig> get sortedTurnServers =>
      _readModelService.sortedTurnServers;

  List<String> get sortedPushServers => _readModelService.sortedPushServers;

  bool isPushServerPaused(String endpoint) =>
      _readModelService.isPushServerPaused(endpoint);

  SettingsServerState bootstrapState(String endpoint) {
    return _readModelService.bootstrapState(endpoint);
  }

  SettingsServerState relayState(String endpoint) {
    return _readModelService.relayState(endpoint);
  }

  SettingsServerState turnState(String url) {
    return _readModelService.turnState(url);
  }

  SettingsServerState pushState(String endpoint) {
    return _readModelService.pushState(endpoint);
  }

  String connectionStatusLabel(String endpoint, {AppStrings? strings}) {
    return _readModelService.connectionStatusLabel(endpoint, strings: strings);
  }

  String relayStatusLabel(String endpoint, {AppStrings? strings}) {
    return _readModelService.relayStatusLabel(endpoint, strings: strings);
  }

  String turnStatusLabel(String url, {AppStrings? strings}) {
    return _readModelService.turnStatusLabel(url, strings: strings);
  }

  String pushStatusLabel(String endpoint, {AppStrings? strings}) {
    return _readModelService.pushStatusLabel(endpoint, strings: strings);
  }

  String exportServerConfigQrPayload() {
    final availableBootstrap = bootstrapPeers
        .where(
          (endpoint) =>
              bootstrapState(endpoint) == SettingsServerState.connected,
        )
        .toList(growable: false);
    final availableRelay = relayServers
        .where(
          (endpoint) => relayState(endpoint) == SettingsServerState.connected,
        )
        .toList(growable: false);
    final availableTurn = turnServers
        .where(
          (server) => turnState(server.url) == SettingsServerState.connected,
        )
        .toList(growable: false);
    final availablePush = pushServers
        .where(
          (endpoint) => pushState(endpoint) == SettingsServerState.connected,
        )
        .toList(growable: false);
    return jsonEncode(
      ServerConfigPayload(
        bootstrap: availableBootstrap,
        relay: availableRelay,
        turn: availableTurn,
        push: availablePush,
      ).toJson(),
    );
  }

  ServerConfigPayload currentConfiguredServerConfigPayload() {
    return ServerConfigPayload(
      bootstrap: List<String>.from(bootstrapPeers),
      relay: List<String>.from(relayServers),
      turn: List<TurnServerConfig>.from(turnServers),
      push: List<String>.from(pushServers),
    );
  }

  ServerConfigPayload parseServerConfigQrPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Неверный формат QR');
    }
    final uri = Uri.tryParse(trimmed);
    if (uri != null && SettingsDeepLinkCodec.isServerConfigUri(uri)) {
      return parseServerConfigDeepLink(trimmed);
    }
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат QR');
    }
    return ServerConfigPayload.fromJson(decoded);
  }

  Future<String> readAppLog() {
    return AppFileLogger.instance.readLog();
  }

  Future<String?> appLogFilePath() {
    return AppFileLogger.instance.getLogFilePath();
  }

  Future<void> clearAppLog() {
    return _dataCleaner.clearCurrentLog();
  }

  Future<void> clearAllLogs() {
    return _dataCleaner.clearAllLogs();
  }

  Future<void> resetLocalAccount() {
    return _dataCleaner.resetLocalAccount();
  }

  Future<void> resetDeviceCompletely() {
    return _dataCleaner.resetDeviceCompletely();
  }

  dynamic readSettingValue(String key) => _settings.get(key);

  Future<void> writeSettingValue(String key, dynamic value) async {
    await _settings.put(key, value);
  }

  Future<void> deleteSettingValue(String key) async {
    await _settings.delete(key);
  }

  Future<void> importServerConfigPayload(
    ServerConfigPayload payload, {
    required ServerConfigImportMode mode,
  }) async {
    await _serverConfigService.importPayload(payload, mode: mode);
    await _registerImportedPushServers(payload);
  }

  Future<void> _registerImportedPushServers(ServerConfigPayload payload) async {
    if (payload.push.isEmpty) {
      return;
    }
    try {
      await network.syncPushDeviceState(
        reason: 'server_import',
        forceRegister: true,
        forcePolicy: true,
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[settings] push register after server import failed error=$error',
        stackTrace: stackTrace,
      );
    }
  }
}
