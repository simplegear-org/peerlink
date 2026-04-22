import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../node/node_facade.dart';
import '../turn/turn_server_config.dart';
import 'app_file_logger.dart';
import 'server_availability.dart';
import 'server_availability_provider.dart';
import 'storage_service.dart';

class TurnServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'turn_servers';
  static const _probeInterval = Duration(seconds: 10);

  final NodeFacade facade;
  final StorageService storage;

  final List<TurnServerConfig> servers = <TurnServerConfig>[];
  final Map<String, int> _failureCounts = <String, int>{};
  final Map<String, DateTime> _lastFailureTime = <String, DateTime>{};
  final Map<String, int> _basePriorityByUrl = <String, int>{};
  final Map<String, ServerAvailability> _availabilityByUrl =
      <String, ServerAvailability>{};
  final StreamController<Map<String, ServerAvailability>>
      _availabilityController =
      StreamController<Map<String, ServerAvailability>>.broadcast();
  Timer? _probeTimer;
  bool _disposed = false;

  TurnServersService({
    required this.facade,
    required this.storage,
  });

  SecureStorageBox get _settings => storage.getSettings();

  @override
  String get providerKey => 'turn';

  @override
  List<String> get serverKeys => List<String>.unmodifiable(
        servers.map((entry) => entry.url),
      );

  @override
  Future<void> initialize() async {
    servers
      ..clear()
      ..addAll(_load());
    _logServers('initialize:loaded', servers);
    _rememberBasePriorities(servers);
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    facade.turnAllocator.setCallbacks(
      onSuccess: reportConnectionSuccess,
      onFailure: reportConnectionFailure,
    );
    _startProbeLoop();
    unawaited(refreshAvailability());
  }

  /// Отмечает неудачу подключения к TURN серверу и автоматически понижает приоритет
  void reportConnectionFailure(String url) {
    _failureCounts[url] = (_failureCounts[url] ?? 0) + 1;
    _lastFailureTime[url] = DateTime.now();
    unawaited(facade.configureTurnServers(getServersWithAdjustedPriorities()));
    _availabilityByUrl[url] = ServerAvailability.unavailable(
      error: 'ошибка подключения',
      checkedAt: DateTime.now(),
    );
    _emitAvailability();
  }

  /// Сбрасывает счетчик неудач для успешного сервера
  void reportConnectionSuccess(String url) {
    if (_failureCounts.containsKey(url)) {
      _failureCounts[url] = 0;
      _lastFailureTime.remove(url);

      // Восстанавливаем оригинальный приоритет для TURNS серверов
      final serverIndex = servers.indexWhere((s) => s.url == url);
      if (serverIndex != -1) {
        final server = servers[serverIndex];
        final originalPriority = _getOriginalPriority(server.url);

        if (server.priority != originalPriority) {
          servers[serverIndex] = server.copyWith(priority: originalPriority);
          _basePriorityByUrl[url] = originalPriority;
        }
      }
    }
    unawaited(facade.configureTurnServers(getServersWithAdjustedPriorities()));
    _availabilityByUrl[url] = ServerAvailability.available(
      checkedAt: DateTime.now(),
    );
    _emitAvailability();
  }

  /// Возвращает список серверов с актуальными приоритетами
  List<TurnServerConfig> getServersWithAdjustedPriorities() {
    return servers.map((server) {
      final failureCount = _failureCounts[server.url] ?? 0;
      final adjustedPriority = _calculatePriorityWithFailures(
        _getOriginalPriority(server.url),
        failureCount,
      );
      return server.copyWith(priority: adjustedPriority);
    }).toList();
  }

  /// Очистить статистику неудач для всех серверов (для тестирования)
  void resetFailureStats() {
    _failureCounts.clear();
    _lastFailureTime.clear();
    facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  /// Получить статистику по серверам для отладки
  Map<String, Map<String, dynamic>> getServerStats() {
    return {
      for (final server in servers)
        server.url: {
          'priority': server.priority,
          'adjustedPriority': _calculatePriorityWithFailures(
            _getOriginalPriority(server.url),
            _failureCounts[server.url] ?? 0,
          ),
          'failureCount': _failureCounts[server.url] ?? 0,
          'lastFailure': _lastFailureTime[server.url]?.toIso8601String(),
        }
    };
  }

  int _calculatePriorityWithFailures(int originalPriority, int failureCount) {
    if (failureCount == 0) return originalPriority;
    final penalty = failureCount * 100;
    return (originalPriority - penalty).clamp(0, originalPriority);
  }

  int _getOriginalPriority(String url) => _basePriorityByUrl[url] ?? 100;

  Future<void> add(TurnServerConfig server) async {
    final normalizedUrl = _normalizeStrictTurnsUrl(
      server.url,
      throwOnInvalid: true,
    );
    final normalized = server.copyWith(url: normalizedUrl);
    if (normalized.url.isEmpty ||
        servers.any((entry) => entry.url == normalized.url)) {
      return;
    }
    servers.add(normalized);
    _basePriorityByUrl[normalized.url] = normalized.priority;
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> remove(String url) async {
    servers.removeWhere((entry) => entry.url == url);
    _failureCounts.remove(url);
    _lastFailureTime.remove(url);
    _basePriorityByUrl.remove(url);
    _availabilityByUrl.remove(url);
    _emitAvailability();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
  }

  Future<void> replace(List<TurnServerConfig> next) async {
    servers
      ..clear()
      ..addAll(
        next
            .map((entry) {
              final normalized = _normalizeStrictTurnsUrl(entry.url);
              if (normalized == null || normalized.isEmpty) {
                return null;
              }
              return entry.copyWith(url: normalized);
            })
            .whereType<TurnServerConfig>(),
      );
    _logServers('replace:normalized', servers);
    _failureCounts.clear();
    _lastFailureTime.clear();
    _rememberBasePriorities(servers);
    _retainAvailability();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> merge(List<TurnServerConfig> incoming) async {
    for (final server in incoming) {
      final normalizedUrl = _normalizeStrictTurnsUrl(server.url);
      if (normalizedUrl == null || normalizedUrl.isEmpty) {
        continue;
      }
      final normalized = server.copyWith(url: normalizedUrl);
      if (normalized.url.isEmpty ||
          servers.any((entry) => entry.url == normalized.url)) {
        continue;
      }
      servers.add(normalized);
      _basePriorityByUrl[normalized.url] = normalized.priority;
    }
    _logServers('merge:result', servers);
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> putFirst(TurnServerConfig server) async {
    final normalizedUrl = _normalizeStrictTurnsUrl(
      server.url,
      throwOnInvalid: true,
    );
    final normalized = server.copyWith(url: normalizedUrl);
    if (normalized.url.isEmpty) {
      return;
    }
    servers.removeWhere((entry) => entry.url == normalized.url);
    servers.insert(0, normalized);
    _basePriorityByUrl[normalized.url] = normalized.priority;
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> putFirstMany(List<TurnServerConfig> incoming) async {
    final normalized = incoming
        .map((server) => server.copyWith(
              url: _normalizeStrictTurnsUrl(
                server.url,
                throwOnInvalid: true,
              ),
            ))
        .where((server) => server.url.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return;
    }
    for (final server in normalized.reversed) {
      servers.removeWhere((entry) => entry.url == server.url);
      servers.insert(0, server);
      _basePriorityByUrl[server.url] = server.priority;
    }
    _logServers('putFirstMany:result', servers);
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  @override
  Stream<Map<String, ServerAvailability>> get availabilityStream =>
      _availabilityController.stream;

  @override
  Map<String, ServerAvailability> get availabilitySnapshot =>
      Map<String, ServerAvailability>.unmodifiable(_availabilityByUrl);

  @override
  ServerAvailability availabilityFor(String url) =>
      _availabilityByUrl[url] ?? const ServerAvailability.unknown();

  @override
  Future<void> refreshAvailability() async {
    if (_disposed) {
      return;
    }
    final snapshot = List<TurnServerConfig>.from(servers);
    if (snapshot.isEmpty) {
      _availabilityByUrl.clear();
      _emitAvailability();
      return;
    }
    final next = <String, ServerAvailability>{};
    for (final server in snapshot) {
      next[server.url] = await _probeServer(server.url);
      if (_disposed) {
        return;
      }
    }
    if (_disposed) {
      return;
    }
    _availabilityByUrl
      ..clear()
      ..addAll(next);
    _emitAvailability();
  }

  Future<void> refreshAvailabilityFor(List<String> selectedUrls) async {
    if (_disposed) {
      return;
    }
    final snapshot = selectedUrls
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && servers.any((server) => server.url == item))
        .toList(growable: false);
    if (snapshot.isEmpty) {
      return;
    }
    final next = Map<String, ServerAvailability>.from(_availabilityByUrl);
    for (final url in snapshot) {
      next[url] = await _probeServer(url);
      if (_disposed) {
        return;
      }
    }
    if (_disposed) {
      return;
    }
    _availabilityByUrl
      ..clear()
      ..addAll(next);
    _emitAvailability();
  }

  @override
  void dispose() {
    _disposed = true;
    _probeTimer?.cancel();
    _availabilityController.close();
  }

  List<TurnServerConfig> _load() {
    final raw = _settings.get(_storageKey);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((entry) {
            final config = TurnServerConfig.fromJson(
              Map<String, dynamic>.from(entry),
            );
            final normalized = _normalizeStrictTurnsUrl(config.url);
            if (normalized == null || normalized.isEmpty) {
              return null;
            }
            return config.copyWith(url: normalized);
          })
          .whereType<TurnServerConfig>()
          .toList(growable: false);
    }
    return facade.turnServers
        .map((entry) {
          final normalized = _normalizeStrictTurnsUrl(entry.url);
          if (normalized == null || normalized.isEmpty) {
            return null;
          }
          return entry.copyWith(url: normalized);
        })
        .whereType<TurnServerConfig>()
        .toList(growable: false);
  }

  Future<void> _persist() async {
    await _settings.put(
      _storageKey,
      servers.map((entry) => entry.toJson()).toList(growable: false),
    );
  }

  void _startProbeLoop() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(_probeInterval, (_) {
      unawaited(refreshAvailability());
    });
  }

  void _retainAvailability() {
    final activeUrls = servers.map((entry) => entry.url).toSet();
    _availabilityByUrl.removeWhere((key, _) => !activeUrls.contains(key));
    _basePriorityByUrl.removeWhere((key, _) => !activeUrls.contains(key));
    _emitAvailability();
  }

  void _rememberBasePriorities(List<TurnServerConfig> items) {
    _basePriorityByUrl
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.url, item.priority)));
  }

  void _emitAvailability() {
    if (_disposed || _availabilityController.isClosed) {
      return;
    }
    _availabilityController.add(
      Map<String, ServerAvailability>.from(_availabilityByUrl),
    );
  }

  String? _normalizeStrictTurnsUrl(
    String raw, {
    bool throwOnInvalid = false,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return throwOnInvalid
          ? (throw const FormatException('TURN URL не должен быть пустым'))
          : null;
    }
    final segments = trimmed
        .split(';')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return throwOnInvalid
          ? (throw const FormatException('TURN URL не должен быть пустым'))
          : null;
    }
    final normalizedSegments = <String>[];
    for (final segment in segments) {
      final isValid = _isValidTurnSegment(segment);
      if (!isValid) {
        if (throwOnInvalid) {
          throw FormatException(
            'Неверный TURN URL. Разрешены только turn: и turns:. Неверный URL: $segment',
          );
        }
        return null;
      }
      normalizedSegments.add(segment);
    }
    return normalizedSegments.join(';');
  }

  bool _isValidTurnSegment(String segment) {
    final value = segment.trim();
    if (value.isEmpty) {
      return false;
    }
    final uri = Uri.tryParse(value);
    if (uri == null) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'turn' && scheme != 'turns') {
      return false;
    }
    final lower = value.toLowerCase();
    if (lower.startsWith('turn://')) {
      if (uri.host.isEmpty) {
        return false;
      }
    } else {
      // turns:host:port... form stores host in path for Dart Uri.
      if (uri.host.isEmpty && uri.path.trim().isEmpty) {
        return false;
      }
    }
    final transport = uri.queryParameters['transport']?.toLowerCase();
    if (transport != null &&
        transport.isNotEmpty &&
        transport != 'tcp' &&
        transport != 'udp') {
      return false;
    }
    return true;
  }

  Future<ServerAvailability> _probeServer(String rawUrl) async {
    final segments = rawUrl
        .split(';')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return ServerAvailability.unavailable(
        error: 'пустой адрес',
        checkedAt: DateTime.now(),
      );
    }

    Object? lastError;
    for (final segment in segments) {
      try {
        await _probeTurnSegment(segment);
        return ServerAvailability.available(checkedAt: DateTime.now());
      } catch (error) {
        lastError = error;
      }
    }
    return ServerAvailability.unavailable(
      error: _shortError(lastError ?? 'no response'),
      checkedAt: DateTime.now(),
    );
  }

  Future<void> _probeTurnSegment(String segment) async {
    final uri = Uri.parse(segment);
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.isNotEmpty ? uri.host : uri.path.split(':').first;
    final port = uri.hasPort
        ? uri.port
        : (scheme == 'turns' ? 5349 : 3478);
    final transport = (uri.queryParameters['transport'] ?? '').toLowerCase();

    if (scheme == 'turns') {
      final socket = await SecureSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
        onBadCertificate: (_) => InternetAddress.tryParse(host) != null,
      );
      socket.destroy();
      return;
    }

    if (transport == 'tcp' || transport.isEmpty) {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      return;
    }

    if (transport == 'udp') {
      await _probeUdp(host, port);
      return;
    }

    throw StateError('unsupported transport=$transport');
  }

  Future<void> _probeUdp(String host, int port) async {
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw const SocketException('host lookup failed');
    }
    final target = addresses.first;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );
    socket.readEventsEnabled = true;

    final completer = Completer<void>();
    late final StreamSubscription<RawSocketEvent> subscription;
    subscription = socket.listen((event) {
      if (event != RawSocketEvent.read || completer.isCompleted) {
        return;
      }
      final datagram = socket.receive();
      if (datagram == null) {
        return;
      }
      if (datagram.address == target && datagram.port == port) {
        completer.complete();
      }
    });

    try {
      socket.send(_buildStunBindingRequest(), target, port);
      await completer.future.timeout(const Duration(seconds: 4));
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  List<int> _buildStunBindingRequest() {
    final bytes = BytesBuilder();
    bytes.add(const <int>[0x00, 0x01]);
    bytes.add(const <int>[0x00, 0x00]);
    bytes.add(const <int>[0x21, 0x12, 0xA4, 0x42]);
    final random = Random.secure();
    bytes.add(
      List<int>.generate(12, (_) => random.nextInt(256)),
    );
    return bytes.toBytes();
  }

  String _shortError(Object error) {
    final text = error.toString().trim();
    if (text.length <= 80) {
      return text;
    }
    return '${text.substring(0, 77)}...';
  }

  void _logServers(String phase, List<TurnServerConfig> items) {
    AppFileLogger.log(
      '[turn_service] $phase count=${items.length} urls=${items.map((e) => e.url).join(',')}',
    );
  }
}
