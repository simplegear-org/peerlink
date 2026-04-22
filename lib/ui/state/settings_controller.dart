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

enum ServerConfigImportMode {
  replace,
  merge,
}

enum SettingsServerState {
  connected,
  connecting,
  unavailable,
}

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

/// Контроллер экрана настроек: peerId и bootstrap-серверы.
class SettingsController {
  final NodeFacade facade;
  final StorageService storage;
  late final ServerHealthCoordinator _health;
  String _appVersionLabel = '—';

  SettingsController({
    required this.facade,
    required this.storage,
  }) {
    _health = ServerHealthCoordinator(
      facade: facade,
      storage: storage,
    );
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
      final rank = _serverStateRank(bootstrapState(a))
          .compareTo(_serverStateRank(bootstrapState(b)));
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
      final rank = _serverStateRank(relayState(a))
          .compareTo(_serverStateRank(relayState(b)));
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
      final rank = _serverStateRank(turnState(a.url))
          .compareTo(_serverStateRank(turnState(b.url)));
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

  String connectionStatusLabel(String endpoint) {
    final availability = _health.bootstrapAvailabilityFor(endpoint);
    final active = activeBootstrapServer == endpoint;
    final baseLabel = availability.label(
      availableLabel: active ? 'доступен, активен' : 'доступен',
      unavailableLabel: active ? 'недоступен, активен' : 'недоступен',
    );
    if (!active) {
      return baseLabel;
    }

    switch (connectionStatus) {
      case SignalingConnectionStatus.connected:
        return '$baseLabel, подключен';
      case SignalingConnectionStatus.connecting:
        return '$baseLabel, подключение...';
      case SignalingConnectionStatus.disconnected:
        return '$baseLabel, отключен';
      case SignalingConnectionStatus.error:
        return lastError == null ? '$baseLabel, ошибка' : '$baseLabel, ошибка: $lastError';
    }
  }

  String relayStatusLabel(String endpoint) {
    final availability = _health.relayAvailabilityFor(endpoint);
    final status = _relayStatus(endpoint);
    final label = availability.label();
    if (status == null) {
      return label;
    }
    if (status.healthy) {
      return '$label, используется runtime';
    }
    if (status.lastError == null || status.lastError!.isEmpty) {
      return label;
    }
    return '$label, runtime: ${status.lastError}';
  }

  String turnStatusLabel(String url) {
    final availability = _health.turnAvailabilityFor(url);
    return availability.label();
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
    return jsonEncode(
      ServerConfigPayload(
        bootstrap: List<String>.from(bootstrapPeers),
        relay: List<String>.from(relayServers),
        turn: List<TurnServerConfig>.from(turnServers),
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
      final match = RegExp(r'^version:\s*([^\s]+)', multiLine: true).firstMatch(pubspec);
      if (match != null) {
        _appVersionLabel = match.group(1) ?? _appVersionLabel;
      }
    } catch (_) {
      _appVersionLabel = '—';
    }
  }

}
