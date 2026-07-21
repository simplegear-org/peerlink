import 'dart:convert';

import 'qr_payload_encoder.dart';
import 'settings_account_membership_service.dart';
import 'settings_controller_models.dart';
import 'settings_deep_link_codec.dart';
import 'settings_invite_codec.dart';
import 'settings_pairing_flow_service.dart';
import 'settings_pairing_state_repository.dart';
import 'settings_pairing_state_service.dart';
import 'settings_read_model_service.dart';
import 'settings_server_config_service.dart';
import 'settings_storage_maintenance_service.dart';
export 'settings_controller_models.dart';

import '../../core/runtime/account_device_event.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/app_data_cleaner_service.dart';
import '../../core/runtime/app_storage_stats.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/server_config_payload.dart';
import '../../core/runtime/server_availability.dart';
import '../../core/runtime/server_health_coordinator.dart';
import '../../core/runtime/push_token_service.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/account_identity.dart';
import '../../core/signaling/signaling_service.dart';
import '../../core/turn/turn_server_config.dart';
import '../localization/app_strings.dart';

/// Контроллер экрана настроек: peerId и bootstrap-серверы.
class SettingsController {
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
  static const Duration _outgoingAccountPairingTimeout = Duration(minutes: 5);
  static const Duration _accountPairingSessionTtl = Duration(minutes: 5);

  final NodeFacade facade;
  final StorageService storage;
  late final ServerHealthCoordinator _health;
  late final AppDataCleanerService _dataCleaner;
  late final PushTokenService _pushTokens;
  late final SettingsPairingStateRepository _pairingStateRepository;
  late final SettingsPairingStateService _pairingStateService;
  late final SettingsPairingFlowService _pairingFlow;
  late final SettingsReadModelService _readModelService;
  late final SettingsServerConfigService _serverConfigService;
  late final SettingsStorageMaintenanceService _storageMaintenanceService;
  late final SettingsAccountMembershipService _accountMembershipService;

  SettingsController({required this.facade, required this.storage}) {
    _health = ServerHealthCoordinator(facade: facade, storage: storage);
    _dataCleaner = AppDataCleanerService(facade: facade, storage: storage);
    _pushTokens = PushTokenService(storage: storage);
    _readModelService = SettingsReadModelService(
      health: _health,
      connectedBootstrapServers: () => connectedBootstrapServers,
    );
    _serverConfigService = SettingsServerConfigService(health: _health);
    _storageMaintenanceService = SettingsStorageMaintenanceService(
      dataCleaner: _dataCleaner,
      serverConfigService: _serverConfigService,
      loadStorageBreakdownImpl: storage.computeAppStorageBreakdown,
    );
    _pairingStateRepository = SettingsPairingStateRepository(
      read: readSettingValue,
      write: writeSettingValue,
      delete: deleteSettingValue,
    );
    _pairingStateService = SettingsPairingStateService(
      repository: _pairingStateRepository,
      writeSettingValue: writeSettingValue,
      deleteSettingValue: deleteSettingValue,
      currentConfiguredServerConfigPayload:
          currentConfiguredServerConfigPayload,
      importServerConfigPayload: importServerConfigPayload,
      accountId: () => accountId,
      deviceId: () => deviceId,
    );
    _pairingFlow = SettingsPairingFlowService(
      peerId: () => peerId,
      accountId: () => accountId,
      deviceId: () => deviceId,
      endpointId: () => endpointId,
      fcmTokenHash: () => fcmTokenHash,
      accountIdentity: () => accountIdentity,
      loadOutgoingRequest: () =>
          _pairingStateService.outgoingAccountPairingRequest,
      loadApprovedPayload: () =>
          _pairingStateService.approvedAccountPairingPayload,
      loadRejectedPayload: () =>
          _pairingStateService.rejectedAccountPairingPayload,
      loadPendingRequest: () =>
          _pairingStateService.pendingAccountPairingRequest,
      stageTemporaryPairingServers:
          _pairingStateService.stageTemporaryPairingServers,
      rollbackTemporaryPairingServers:
          _pairingStateService.rollbackTemporaryPairingServers,
      saveOutgoingRequest: _pairingStateService.saveOutgoingRequest,
      deleteOutgoingRequest: _pairingStateService.deleteOutgoingRequest,
      deleteApprovedPayload: _pairingStateService.deleteApprovedPayload,
      deleteRejectedPayload: _pairingStateService.deleteRejectedPayload,
      deleteStagedServerConfig: _pairingStateService.deleteStagedServerConfig,
      issueApprovedPairingAccountIdentity: issueApprovedPairingAccountIdentity,
      applyApprovedPairingAccountIdentity: applyApprovedPairingAccountIdentity,
      sendAccountPairingControlMessage: sendAccountPairingControlMessage,
      appendAccountDeviceEvent: _pairingStateService.appendAccountDeviceEvent,
      signAccountMembershipUpdate: signAccountMembershipUpdate,
      findActiveSession: _pairingStateService.activeAccountPairingSession,
      removeActiveSession:
          _pairingStateService.removeActiveAccountPairingSession,
      removeIncomingRequest:
          _pairingStateService.removeIncomingAccountPairingRequest,
      savePendingRequest: _pairingStateService.savePendingRequest,
      clearPendingRequest: _pairingStateService.clearPendingRequest,
      onMembershipUpdateSendFailed: (peerId, error, stackTrace) {
        AppFileLogger.log(
          'account membership update send failed peerId=$peerId error=$error',
          name: 'account_membership',
          stackTrace: stackTrace,
        );
      },
      pairingTimeout: _outgoingAccountPairingTimeout,
    );
    _accountMembershipService = SettingsAccountMembershipService(
      facade: facade,
      deviceId: () => deviceId,
      accountId: () => accountId,
      accountIdentity: () => accountIdentity,
      ensurePrimaryAccountDeviceForManagement:
          _ensurePrimaryAccountDeviceForManagement,
      issueRevokedAccountIdentity: issueRevokedAccountIdentity,
      signAccountMembershipUpdate: signAccountMembershipUpdate,
      applyAccountMembershipUpdate: applyAccountMembershipUpdate,
      sendAccountPairingControlMessage: sendAccountPairingControlMessage,
      appendAccountDeviceEvent: _pairingStateService.appendAccountDeviceEvent,
      loadIncomingAccountMembershipUpdates: () =>
          _pairingStateService.incomingAccountMembershipUpdates,
      removeIncomingAccountMembershipUpdate:
          _pairingStateService.removeIncomingAccountMembershipUpdate,
    );
  }

  SecureStorageBox get _settings => storage.getSettings();

  /// Текущий peerId локального узла.
  String get peerId => facade.peerId;
  String get accountId => facade.accountId;
  String get activeAccountId => facade.activeAccountId;
  String get homeAccountId => facade.homeAccountId;
  String get deviceId => facade.deviceId;
  AccountIdentity get accountIdentity => facade.accountIdentity;
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
  String? get endpointId => facade.endpointId;
  String? get fcmTokenHash => facade.fcmTokenHash;
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
    });
  }

  String exportInvitePayload() {
    return SettingsInviteCodec.exportInvitePayload(
      peerId: peerId,
      endpointId: endpointId,
      fcmTokenHash: fcmTokenHash,
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

  String exportServerConfigShareText() {
    return 'Конфигурация серверов PeerLink: ${exportServerConfigShareLink()}';
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
      throw const FormatException('Это не привязка устройства PeerLink');
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
      throw const FormatException('Это не ссылка конфигурации PeerLink');
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

  List<String> get bootstrapPeers => _readModelService.bootstrapPeers;
  List<String> get relayServers => _readModelService.relayServers;
  List<TurnServerConfig> get turnServers => _readModelService.turnServers;
  List<String> get pushServers => _readModelService.pushServers;
  String get appVersionLabel => _readModelService.appVersionLabel;
  AppLogLevel get appLogLevel => AppFileLogger.parseStoredLevel(
    _settings.get(AppFileLogger.logLevelSettingsKey),
  );

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

  Future<void> addPushServer(String endpoint) {
    return _serverConfigService.addPushServer(endpoint);
  }

  Future<void> removePushServer(String endpoint) {
    return _serverConfigService.removePushServer(endpoint);
  }

  Future<void> updatePushServer(
    String currentEndpoint, {
    required String host,
    int? port,
  }) {
    return _serverConfigService.updatePushServer(
      currentEndpoint,
      host: host,
      port: port,
    );
  }

  Future<void> pausePushServer(String endpoint) {
    return _serverConfigService.pausePushServer(endpoint);
  }

  Future<void> resumePushServer(String endpoint) {
    return _serverConfigService.resumePushServer(endpoint);
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

  void dispose() {}

  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity identity) {
    return facade.mergeAccountIdentity(identity);
  }

  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) {
    return facade.issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice,
      sessionId: sessionId,
    );
  }

  Future<AccountIdentity> applyApprovedPairingAccountIdentity(
    AccountIdentity identity, {
    required String expectedSessionId,
    required String expectedAccountId,
  }) {
    return facade.applyApprovedPairingAccountIdentity(
      incoming: identity,
      expectedSessionId: expectedSessionId,
      expectedAccountId: expectedAccountId,
    );
  }

  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  }) {
    return facade.issueRevokedAccountIdentity(
      revokedDeviceIds: revokedDeviceIds,
    );
  }

  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) {
    return facade.signAccountMembershipUpdate(
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
    return facade.applyAccountMembershipUpdate(
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
    return facade.sendControlMessage(peerId, kind: kind, text: text);
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
      facade.bootstrapConnectionStatus;

  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      facade.bootstrapConnectionStatusStream;
  String? get lastError => facade.bootstrapLastError;
  Stream<String?> get lastErrorStream => facade.bootstrapLastErrorStream;

  String? get activeBootstrapServer => facade.activeBootstrapServer;
  List<String> get connectedBootstrapServers =>
      facade.connectedBootstrapServers;

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
  }) {
    return _serverConfigService.importPayload(payload, mode: mode);
  }
}
