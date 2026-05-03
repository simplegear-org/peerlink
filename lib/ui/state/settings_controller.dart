import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/app_storage_stats.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/server_config_payload.dart';
import '../../core/runtime/server_availability.dart';
import '../../core/runtime/server_health_coordinator.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/relay/http_relay_client.dart';
import '../../core/signaling/signaling_service.dart';
import '../../core/turn/turn_server_config.dart';
import '../localization/app_strings.dart';

enum ServerConfigImportMode { replace, merge }

enum SettingsServerState { connected, connecting, unavailable }

class ServerConfigImportPreview {
  final int bootstrapTotal;
  final int relayTotal;
  final int turnTotal;
  final int bootstrapNew;
  final int relayNew;
  final int turnNew;

  const ServerConfigImportPreview({
    required this.bootstrapTotal,
    required this.relayTotal,
    required this.turnTotal,
    required this.bootstrapNew,
    required this.relayNew,
    required this.turnNew,
  });
}

class PeerLinkInviteImport {
  final String peerId;
  final String? displayName;
  final ServerConfigPayload serverConfig;

  const PeerLinkInviteImport({
    required this.peerId,
    required this.serverConfig,
    this.displayName,
  });
}

/// Контроллер экрана настроек: peerId и bootstrap-серверы.
class SettingsController {
  static const String _invitePayloadType = 'peerlink_invite';
  static const int _invitePayloadVersion = 1;
  static const String _inviteWebBaseUrl = String.fromEnvironment(
    'PEERLINK_INVITE_WEB_BASE_URL',
    defaultValue: 'https://simplegear.org/invite',
  );

  final NodeFacade facade;
  final StorageService storage;
  late final ServerHealthCoordinator _health;
  String _appVersionLabel = '—';

  SettingsController({required this.facade, required this.storage}) {
    _health = ServerHealthCoordinator(facade: facade, storage: storage);
  }

  SecureStorageBox get _settings => storage.getSettings();

  /// Текущий peerId локального узла.
  String get peerId => facade.peerId;
  String get legacyPeerId => facade.legacyPeerId;
  String? get endpointId => facade.endpointId;
  String? get fcmTokenHash => facade.fcmTokenHash;
  String? get fcmToken => _settings.get('fcm_token') as String?;

  String exportUserQrPayload() {
    return jsonEncode(<String, dynamic>{
      'type': 'peerlink_user_qr_v2',
      'schemaVersion': 2,
      'stableUserId': peerId,
      'peerId': peerId,
      'legacyUserId': legacyPeerId,
      'endpointId': endpointId,
      'fcmTokenHash': fcmTokenHash,
    });
  }

  String exportInvitePayload() {
    final serverConfig = jsonDecode(exportServerConfigQrPayload());
    return jsonEncode(<String, dynamic>{
      'type': _invitePayloadType,
      'version': _invitePayloadVersion,
      'peer': <String, dynamic>{
        'peerId': peerId,
        'stableUserId': peerId,
        'legacyUserId': legacyPeerId,
        'endpointId': endpointId,
        'fcmTokenHash': fcmTokenHash,
      },
      'servers': serverConfig,
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  String exportInviteDeepLink() {
    final encodedPayload = _encodedInvitePayload();
    return Uri(
      scheme: 'peerlink',
      host: 'invite',
      queryParameters: <String, String>{'payload': encodedPayload},
    ).toString();
  }

  String exportInviteShareLink() {
    final encodedPayload = _encodedInvitePayload();
    final baseUri = Uri.parse(_inviteWebBaseUrl);
    return baseUri
        .replace(
          queryParameters: <String, String>{
            ...baseUri.queryParameters,
            'payload': encodedPayload,
          },
        )
        .toString();
  }

  String _encodedInvitePayload() {
    final payloadBytes = utf8.encode(exportInvitePayload());
    return base64UrlEncode(payloadBytes).replaceAll('=', '');
  }

  PeerLinkInviteImport parseInviteDeepLink(String raw) {
    final trimmed = raw.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !_isInviteUri(uri)) {
      throw const FormatException('Это не приглашение PeerLink');
    }
    final encodedPayload = _invitePayloadFromUri(uri);
    if (encodedPayload == null || encodedPayload.trim().isEmpty) {
      throw const FormatException('В приглашении нет payload');
    }
    final normalizedPayload = base64Url.normalize(encodedPayload.trim());
    final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
    return parseInvitePayload(payloadJson);
  }

  bool _isInviteUri(Uri uri) {
    if (uri.scheme == 'peerlink' && uri.host == 'invite') {
      return true;
    }
    final isWeb = uri.scheme == 'https' || uri.scheme == 'http';
    if (!isWeb) {
      return false;
    }
    if (uri.pathSegments.contains('invite')) {
      return true;
    }
    final fragmentUri = _inviteFragmentUri(uri);
    return fragmentUri?.pathSegments.contains('invite') == true;
  }

  String? _invitePayloadFromUri(Uri uri) {
    final directPayload = uri.queryParameters['payload'];
    if (directPayload?.trim().isNotEmpty == true) {
      return directPayload;
    }
    return _inviteFragmentUri(uri)?.queryParameters['payload'];
  }

  Uri? _inviteFragmentUri(Uri uri) {
    final fragment = uri.fragment.trim();
    if (fragment.isEmpty) {
      return null;
    }
    final normalized = fragment.startsWith('/')
        ? 'https://peerlink.local$fragment'
        : fragment;
    return Uri.tryParse(normalized);
  }

  PeerLinkInviteImport parseInvitePayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат приглашения PeerLink');
    }
    if (decoded['type'] != _invitePayloadType ||
        decoded['version'] != _invitePayloadVersion) {
      throw const FormatException('Неподдерживаемое приглашение PeerLink');
    }

    final peer = decoded['peer'];
    if (peer is! Map) {
      throw const FormatException('В приглашении нет peer');
    }
    final peerMap = Map<String, dynamic>.from(peer);
    final invitePeerId =
        peerMap['stableUserId']?.toString().trim().isNotEmpty == true
        ? peerMap['stableUserId'].toString().trim()
        : peerMap['peerId']?.toString().trim();
    if (invitePeerId == null || invitePeerId.isEmpty) {
      throw const FormatException('В приглашении нет Peer ID');
    }

    final servers = decoded['servers'];
    final serverMap = servers is Map
        ? Map<String, dynamic>.from(servers)
        : <String, dynamic>{
            'type': ServerConfigPayload.type,
            'version': ServerConfigPayload.version,
            'bootstrap': const <String>[],
            'relay': const <String>[],
            'turn': const <Map<String, dynamic>>[],
          };
    final serverConfig = ServerConfigPayload.fromJson(serverMap);
    final displayName = peerMap['displayName']?.toString().trim();

    return PeerLinkInviteImport(
      peerId: invitePeerId,
      displayName: displayName?.isNotEmpty == true ? displayName : null,
      serverConfig: serverConfig,
    );
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

  List<String> get bootstrapPeers => _health.bootstrapEndpoints;
  List<String> get relayServers => _health.relayEndpoints;
  List<TurnServerConfig> get turnServers => _health.turnServers;
  String get appVersionLabel => _appVersionLabel;

  /// Загружает bootstrap-серверы из storage и применяет их в runtime.
  Future<void> initialize() async {
    await _health.initialize();
    await _loadAppVersion();
  }

  void dispose() {}

  /// Добавляет bootstrap endpoint и синхронизирует storage/runtime.
  Future<void> addBootstrap(String peer) async {
    await _health.bootstrap.add(peer);
  }

  /// Удаляет bootstrap endpoint и синхронизирует storage/runtime.
  Future<void> removeBootstrap(String peer) async {
    await _health.bootstrap.remove(peer);
  }

  /// Добавляет relay endpoint и синхронизирует storage/runtime.
  Future<void> addRelay(String endpoint) async {
    await _health.relay.add(endpoint);
  }

  /// Удаляет relay endpoint и синхронизирует storage/runtime.
  Future<void> removeRelay(String endpoint) async {
    await _health.relay.remove(endpoint);
  }

  Future<void> addTurnServer(TurnServerConfig server) async {
    await _health.turn.add(server);
  }

  Future<void> removeTurnServer(String url) async {
    await _health.turn.remove(url);
  }

  ServerConfigImportPreview previewImport(ServerConfigPayload payload) {
    final bootstrapNew = payload.bootstrap
        .where((endpoint) => !bootstrapPeers.contains(endpoint))
        .length;
    final relayNew = payload.relay
        .where((endpoint) => !relayServers.contains(endpoint))
        .length;
    final turnNew = payload.turn
        .where((server) => !turnServers.any((entry) => entry.url == server.url))
        .length;

    return ServerConfigImportPreview(
      bootstrapTotal: payload.bootstrap.length,
      relayTotal: payload.relay.length,
      turnTotal: payload.turn.length,
      bootstrapNew: bootstrapNew,
      relayNew: relayNew,
      turnNew: turnNew,
    );
  }

  Future<void> importServerConfigPayload(
    ServerConfigPayload payload, {
    required ServerConfigImportMode mode,
  }) async {
    if (mode == ServerConfigImportMode.replace) {
      await _health.bootstrap.replace(payload.bootstrap);
      await _health.relay.replace(payload.relay);
      await _health.turn.replace(payload.turn);
      return;
    }
    await _health.bootstrap.merge(payload.bootstrap);
    await _health.relay.merge(payload.relay);
    await _health.turn.merge(payload.turn);
  }

  Future<void> addSelfHostedServersFirst({
    required String bootstrapEndpoint,
    required String relayEndpoint,
    required List<TurnServerConfig> turnServers,
  }) async {
    final bootstrap = bootstrapEndpoint.trim();
    final relay = relayEndpoint.trim();
    final turns = turnServers
        .map((server) => server.copyWith(url: server.url.trim()))
        .where((server) => server.url.isNotEmpty)
        .toList(growable: false);
    if (bootstrap.isEmpty || relay.isEmpty || turns.isEmpty) {
      throw const FormatException('Некорректная конфигурация серверов');
    }

    await _health.bootstrap.putFirst(bootstrap);
    await _health.relay.putFirst(relay);
    await _health.turn.putFirstMany(turns);
  }

  SignalingConnectionStatus get connectionStatus =>
      facade.bootstrapConnectionStatus;

  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      facade.bootstrapConnectionStatusStream;
  String? get lastError => facade.bootstrapLastError;
  Stream<String?> get lastErrorStream => facade.bootstrapLastErrorStream;

  String? get activeBootstrapServer => facade.activeBootstrapServer;

  Stream<Map<String, ServerAvailability>> get bootstrapAvailabilityStream =>
      _health.bootstrapAvailabilityStream;
  Stream<Map<String, ServerAvailability>> get relayAvailabilityStream =>
      _health.relayAvailabilityStream;
  Stream<Map<String, ServerAvailability>> get turnAvailabilityStream =>
      _health.turnAvailabilityStream;

  List<String> get sortedBootstrapPeers {
    final items = List<String>.from(bootstrapPeers);
    items.sort((a, b) {
      final rank = _serverStateRank(
        bootstrapState(a),
      ).compareTo(_serverStateRank(bootstrapState(b)));
      if (rank != 0) {
        return rank;
      }
      final aActive = activeBootstrapServer == a ? 0 : 1;
      final bActive = activeBootstrapServer == b ? 0 : 1;
      if (aActive != bActive) {
        return aActive.compareTo(bActive);
      }
      return a.compareTo(b);
    });
    return items;
  }

  int get bootstrapAvailableCount {
    var count = 0;
    for (final endpoint in bootstrapPeers) {
      if (bootstrapState(endpoint) == SettingsServerState.connected) {
        count += 1;
      }
    }
    return count;
  }

  int get bootstrapUnavailableCount {
    var count = 0;
    for (final endpoint in bootstrapPeers) {
      if (bootstrapState(endpoint) == SettingsServerState.unavailable) {
        count += 1;
      }
    }
    return count;
  }

  int get relayAvailableCount {
    var count = 0;
    for (final endpoint in relayServers) {
      if (relayState(endpoint) == SettingsServerState.connected) {
        count += 1;
      }
    }
    return count;
  }

  int get relayUnavailableCount {
    var count = 0;
    for (final endpoint in relayServers) {
      if (relayState(endpoint) == SettingsServerState.unavailable) {
        count += 1;
      }
    }
    return count;
  }

  int get turnAvailableCount {
    var count = 0;
    for (final server in turnServers) {
      if (turnState(server.url) == SettingsServerState.connected) {
        count += 1;
      }
    }
    return count;
  }

  int get turnUnavailableCount {
    var count = 0;
    for (final server in turnServers) {
      if (turnState(server.url) == SettingsServerState.unavailable) {
        count += 1;
      }
    }
    return count;
  }

  List<String> get sortedRelayServers {
    final items = List<String>.from(relayServers);
    items.sort((a, b) {
      final rank = _serverStateRank(
        relayState(a),
      ).compareTo(_serverStateRank(relayState(b)));
      if (rank != 0) {
        return rank;
      }
      return a.compareTo(b);
    });
    return items;
  }

  List<TurnServerConfig> get sortedTurnServers {
    final items = List<TurnServerConfig>.from(turnServers);
    items.sort((a, b) {
      final rank = _serverStateRank(
        turnState(a.url),
      ).compareTo(_serverStateRank(turnState(b.url)));
      if (rank != 0) {
        return rank;
      }
      return a.url.compareTo(b.url);
    });
    return items;
  }

  SettingsServerState bootstrapState(String endpoint) {
    final availability = _health.bootstrapAvailabilityFor(endpoint);
    final active = activeBootstrapServer == endpoint;
    if (active && connectionStatus == SignalingConnectionStatus.connecting) {
      return SettingsServerState.connecting;
    }
    if (availability.isAvailable == true) {
      return SettingsServerState.connected;
    }
    if (availability.isAvailable == false ||
        (active && connectionStatus == SignalingConnectionStatus.error)) {
      return SettingsServerState.unavailable;
    }
    return SettingsServerState.connecting;
  }

  SettingsServerState relayState(String endpoint) {
    final availability = _health.relayAvailabilityFor(endpoint);
    final status = _relayStatus(endpoint);
    if (status?.healthy == true || availability.isAvailable == true) {
      return SettingsServerState.connected;
    }
    if (availability.isAvailable == false || status?.healthy == false) {
      return SettingsServerState.unavailable;
    }
    return SettingsServerState.connecting;
  }

  SettingsServerState turnState(String url) {
    final availability = _health.turnAvailabilityFor(url);
    if (availability.isAvailable == true) {
      return SettingsServerState.connected;
    }
    if (availability.isAvailable == false) {
      return SettingsServerState.unavailable;
    }
    return SettingsServerState.connecting;
  }

  String connectionStatusLabel(String endpoint, {AppStrings? strings}) {
    final availability = _health.bootstrapAvailabilityFor(endpoint);
    final active = activeBootstrapServer == endpoint;
    final invalidLabel = _invalidAddressLabel(availability, strings: strings);
    if (invalidLabel != null) {
      return invalidLabel;
    }
    final baseLabel = availability.label(
      availableLabel:
          strings?.serverAvailable(active: active) ??
          (active ? 'доступен, активен' : 'доступен'),
      unavailableLabel:
          strings?.serverUnavailable(active: active) ??
          (active ? 'недоступен, активен' : 'недоступен'),
      unknownLabel: strings?.serverCheckPending ?? 'ожидание проверки',
    );
    if (!active) {
      return baseLabel;
    }

    switch (connectionStatus) {
      case SignalingConnectionStatus.connected:
        return strings?.serverConnected(baseLabel) ?? '$baseLabel, подключен';
      case SignalingConnectionStatus.connecting:
        return strings?.serverConnecting(baseLabel) ??
            '$baseLabel, подключение...';
      case SignalingConnectionStatus.disconnected:
        return strings?.serverDisconnected(baseLabel) ?? '$baseLabel, отключен';
      case SignalingConnectionStatus.error:
        return strings?.serverError(baseLabel, lastError) ??
            (lastError == null
                ? '$baseLabel, ошибка'
                : '$baseLabel, ошибка: $lastError');
    }
  }

  String relayStatusLabel(String endpoint, {AppStrings? strings}) {
    final availability = _health.relayAvailabilityFor(endpoint);
    final status = _relayStatus(endpoint);
    final invalidLabel = _invalidAddressLabel(availability, strings: strings);
    if (invalidLabel != null) {
      return invalidLabel;
    }
    final label = availability.label(
      availableLabel: strings?.serverAvailable(active: false) ?? 'доступен',
      unavailableLabel:
          strings?.serverUnavailable(active: false) ?? 'ошибка подключения',
      unknownLabel: strings?.serverCheckPending ?? 'ожидание проверки',
    );
    if (status == null) {
      return label;
    }
    if (status.healthy) {
      return strings?.serverRuntimeUsed(label) ??
          '$label, используется runtime';
    }
    if (status.lastError == null || status.lastError!.isEmpty) {
      return label;
    }
    return strings?.serverRuntimeError(label, status.lastError!) ??
        '$label, runtime: ${status.lastError}';
  }

  String turnStatusLabel(String url, {AppStrings? strings}) {
    final availability = _health.turnAvailabilityFor(url);
    final invalidLabel = _invalidAddressLabel(availability, strings: strings);
    if (invalidLabel != null) {
      return invalidLabel;
    }
    return availability.label(
      availableLabel: strings?.serverAvailable(active: false) ?? 'доступен',
      unavailableLabel:
          strings?.serverUnavailable(active: false) ?? 'ошибка подключения',
      unknownLabel: strings?.serverCheckPending ?? 'ожидание проверки',
    );
  }

  String? _invalidAddressLabel(
    ServerAvailability availability, {
    AppStrings? strings,
  }) {
    if (availability.isAvailable == false &&
        availability.error?.trim() == 'некорректный адрес') {
      return strings?.invalidAddress ?? 'некорректный адрес';
    }
    return null;
  }

  int _serverStateRank(SettingsServerState state) {
    switch (state) {
      case SettingsServerState.connected:
        return 0;
      case SettingsServerState.connecting:
        return 1;
      case SettingsServerState.unavailable:
        return 2;
    }
  }

  RelayServerStatus? _relayStatus(String endpoint) {
    for (final status in facade.relayServerStatuses) {
      if (status.url == endpoint) {
        return status;
      }
    }
    return null;
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

    return jsonEncode(
      ServerConfigPayload(
        bootstrap: availableBootstrap,
        relay: availableRelay,
        turn: availableTurn,
      ).toJson(),
    );
  }

  ServerConfigPayload parseServerConfigQrPayload(String raw) {
    final decoded = jsonDecode(raw);
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
    return AppFileLogger.instance.clear();
  }

  Future<void> clearAllLogs() {
    return AppFileLogger.instance.clearAll();
  }

  Future<AppStorageBreakdown> loadStorageBreakdown() {
    return storage.computeAppStorageBreakdown();
  }

  Future<void> clearMessagesDatabase() {
    return storage.clearMessagesDatabase();
  }

  Future<void> clearSettingsAndServiceData() async {
    await storage.clearSettingsAndServiceData();
    await _health.bootstrap.replace(const <String>[]);
    await _health.relay.replace(const <String>[]);
    await _health.turn.replace(const <TurnServerConfig>[]);
  }

  Future<void> _loadAppVersion() async {
    try {
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(
        r'^version:\s*([^\s]+)',
        multiLine: true,
      ).firstMatch(pubspec);
      if (match != null) {
        _appVersionLabel = match.group(1) ?? _appVersionLabel;
      }
    } catch (_) {
      _appVersionLabel = '—';
    }
  }
}
