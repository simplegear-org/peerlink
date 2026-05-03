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
  static const _defaultProbeTimeout = Duration(seconds: 4);

  final NodeFacade facade;
  final StorageService storage;
  final Duration _probeTimeout;

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
  bool _refreshInFlight = false;

  TurnServersService({
    required this.facade,
    required this.storage,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _probeTimeout = probeTimeout;

  SecureStorageBox get _settings => storage.getSettings();

  @override
  String get providerKey => 'turn';

  @override
  List<String> get serverKeys =>
      List<String>.unmodifiable(servers.map((entry) => entry.url));

  @override
  Future<void> initialize() async {
    servers
      ..clear()
      ..addAll(_load());
    _logServers('initialize:loaded', servers);
    _seedAvailabilityForServers(servers);
    _emitAvailability();
    await _persist();
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
        },
    };
  }

  int _calculatePriorityWithFailures(int originalPriority, int failureCount) {
    if (failureCount == 0) return originalPriority;
    final penalty = failureCount * 100;
    return (originalPriority - penalty).clamp(0, originalPriority);
  }

  int _getOriginalPriority(String url) => _basePriorityByUrl[url] ?? 100;

  Future<void> add(TurnServerConfig server) async {
    final normalized = server.copyWith(url: server.url.trim());
    if (normalized.url.isEmpty ||
        servers.any((entry) => entry.url == normalized.url)) {
      return;
    }
    servers.add(normalized);
    _basePriorityByUrl[normalized.url] = normalized.priority;
    _availabilityByUrl[normalized.url] = _initialAvailabilityForUrl(
      normalized.url,
    );
    _emitAvailability();
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
        next.map((entry) {
          final normalized = entry.url.trim();
          if (normalized.isEmpty) {
            return null;
          }
          return entry.copyWith(url: normalized);
        }).whereType<TurnServerConfig>(),
      );
    _logServers('replace:normalized', servers);
    _failureCounts.clear();
    _lastFailureTime.clear();
    _rememberBasePriorities(servers);
    _retainAvailability();
    _seedAvailabilityForServers(servers);
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> merge(List<TurnServerConfig> incoming) async {
    for (final server in incoming) {
      final normalizedUrl = server.url.trim();
      if (normalizedUrl.isEmpty) {
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
    _seedAvailabilityForServers(servers);
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> putFirst(TurnServerConfig server) async {
    final normalized = server.copyWith(url: server.url.trim());
    if (normalized.url.isEmpty) {
      return;
    }
    servers.removeWhere((entry) => entry.url == normalized.url);
    servers.insert(0, normalized);
    _basePriorityByUrl[normalized.url] = normalized.priority;
    _availabilityByUrl[normalized.url] = _initialAvailabilityForUrl(
      normalized.url,
    );
    _emitAvailability();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> putFirstMany(List<TurnServerConfig> incoming) async {
    final normalized = incoming
        .map((server) {
          final normalizedUrl = server.url.trim();
          if (normalizedUrl.isEmpty) {
            return null;
          }
          return server.copyWith(url: normalizedUrl);
        })
        .whereType<TurnServerConfig>()
        .where((server) => server.url.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      return;
    }
    for (final server in normalized.reversed) {
      servers.removeWhere((entry) => entry.url == server.url);
      servers.insert(0, server);
      _basePriorityByUrl[server.url] = server.priority;
      _availabilityByUrl[server.url] = _initialAvailabilityForUrl(server.url);
    }
    _logServers('putFirstMany:result', servers);
    _emitAvailability();
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
    if (_disposed || _refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    try {
      final snapshot = List<TurnServerConfig>.from(servers);
      if (snapshot.isEmpty) {
        _availabilityByUrl.clear();
        _emitAvailability();
        return;
      }
      final next = <String, ServerAvailability>{};
      for (final server in snapshot) {
        try {
          next[server.url] = await _probeServer(server.url);
        } catch (error) {
          next[server.url] = ServerAvailability.unavailable(
            error: _shortError(error),
            checkedAt: DateTime.now(),
          );
        }
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
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> refreshAvailabilityFor(List<String> selectedUrls) async {
    if (_disposed || _refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    try {
      final snapshot = selectedUrls
          .map((item) => item.trim())
          .where(
            (item) =>
                item.isNotEmpty && servers.any((server) => server.url == item),
          )
          .toList(growable: false);
      if (snapshot.isEmpty) {
        return;
      }
      final next = Map<String, ServerAvailability>.from(_availabilityByUrl);
      for (final url in snapshot) {
        try {
          next[url] = await _probeServer(url);
        } catch (error) {
          next[url] = ServerAvailability.unavailable(
            error: _shortError(error),
            checkedAt: DateTime.now(),
          );
        }
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
    } finally {
      _refreshInFlight = false;
    }
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
            final normalized = config.url.trim();
            if (normalized.isEmpty) {
              return null;
            }
            return config.copyWith(url: normalized);
          })
          .whereType<TurnServerConfig>()
          .toList(growable: false);
    }
    return facade.turnServers
        .map((entry) {
          final normalized = entry.url.trim();
          if (normalized.isEmpty) {
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

  void _seedAvailabilityForServers(List<TurnServerConfig> items) {
    for (final item in items) {
      _availabilityByUrl.putIfAbsent(
        item.url,
        () => _initialAvailabilityForUrl(item.url),
      );
    }
  }

  void _emitAvailability() {
    if (_disposed || _availabilityController.isClosed) {
      return;
    }
    _availabilityController.add(
      Map<String, ServerAvailability>.from(_availabilityByUrl),
    );
  }

  ServerAvailability _initialAvailabilityForUrl(String raw) {
    final normalized = _normalizeStrictTurnsUrl(raw);
    if (normalized == null || normalized.isEmpty) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }
    return const ServerAvailability.unknown();
  }

  String? _normalizeStrictTurnsUrl(String raw, {bool throwOnInvalid = false}) {
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
      if (!_isSafeTurnHost(uri.host.trim())) {
        return false;
      }
    } else {
      // turns:host:port... form stores host in path for Dart Uri.
      final fallbackHost = uri.host.isNotEmpty
          ? uri.host.trim()
          : uri.path.split(':').first.trim();
      if (fallbackHost.isEmpty) {
        return false;
      }
      if (!_isSafeTurnHost(fallbackHost)) {
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
    try {
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

      String? lastError;
      for (final segment in segments) {
        final error = await _probeTurnSegment(segment);
        if (error == null) {
          return ServerAvailability.available(checkedAt: DateTime.now());
        }
        lastError = error;
      }
      return ServerAvailability.unavailable(
        error: _shortError(lastError ?? 'no response'),
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      return ServerAvailability.unavailable(
        error: _shortError(error),
        checkedAt: DateTime.now(),
      );
    }
  }

  Future<String?> _probeTurnSegment(String segment) async {
    Uri uri;
    String scheme;
    String host;
    int port;
    String transport;

    try {
      uri = Uri.parse(segment);
      scheme = uri.scheme.toLowerCase();
      host = uri.host.isNotEmpty ? uri.host : uri.path.split(':').first.trim();
      port = uri.hasPort ? uri.port : (scheme == 'turns' ? 5349 : 3478);
      transport = (uri.queryParameters['transport'] ?? '').toLowerCase();
    } on FormatException catch (error) {
      return 'invalid TURN URL: ${error.message}';
    }

    if ((scheme != 'turn' && scheme != 'turns') || host.isEmpty) {
      return 'invalid TURN URL';
    }
    if (!_isSafeTurnHost(host)) {
      return 'invalid TURN host';
    }

    if (scheme == 'turns') {
      try {
        final socket = await _secureSocketWithTimeout(
          host,
          port,
          allowBadCertificate: _isSafeIpAddressHost(host),
        );
        if (socket == null) {
          return 'turns probe timeout';
        }
        socket.destroy();
        return null;
      } catch (error) {
        return _shortError(error);
      }
    }

    if (transport == 'tcp' || transport.isEmpty) {
      try {
        final socket = await _socketWithTimeout(host, port);
        if (socket == null) {
          return 'tcp probe timeout';
        }
        socket.destroy();
        return null;
      } catch (error) {
        return _shortError(error);
      }
    }

    if (transport == 'udp') {
      final ok = await _probeUdp(host, port);
      return ok ? null : 'udp probe timeout';
    }

    return 'unsupported transport=$transport';
  }

  Future<Socket?> _socketWithTimeout(String host, int port) {
    return _connectionTaskWithTimeout(Socket.startConnect(host, port));
  }

  Future<SecureSocket?> _secureSocketWithTimeout(
    String host,
    int port, {
    required bool allowBadCertificate,
  }) {
    return _connectionTaskWithTimeout(
      SecureSocket.startConnect(
        host,
        port,
        onBadCertificate: (_) => allowBadCertificate,
      ),
    );
  }

  Future<T?> _connectionTaskWithTimeout<T extends Socket>(
    Future<ConnectionTask<T>> taskFuture,
  ) {
    final completer = Completer<T?>();
    Timer? timeoutTimer;
    ConnectionTask<T>? task;
    var timedOut = false;

    void completeAsTimeout() {
      timedOut = true;
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      try {
        task?.cancel();
      } catch (_) {}
    }

    void completeError(Object error, StackTrace stackTrace) {
      timeoutTimer?.cancel();
      if (timedOut || completer.isCompleted) {
        return;
      }
      completer.completeError(error, stackTrace);
    }

    timeoutTimer = Timer(_probeTimeout, completeAsTimeout);

    try {
      taskFuture.then((nextTask) {
        task = nextTask;
        if (timedOut) {
          try {
            nextTask.cancel();
          } catch (_) {}
        }
        nextTask.socket.then((socket) {
          timeoutTimer?.cancel();
          if (timedOut || completer.isCompleted) {
            socket.destroy();
            return;
          }
          completer.complete(socket);
        }, onError: completeError);
      }, onError: completeError);
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
    }

    return completer.future.whenComplete(() => timeoutTimer?.cancel());
  }

  bool _isSafeTurnHost(String host) {
    final value = host.trim();
    if (value.isEmpty) {
      return false;
    }
    if (value.contains('%')) {
      return false;
    }
    try {
      if (InternetAddress.tryParse(value) != null) {
        return true;
      }
    } on FormatException {
      return false;
    }
    final domainPattern = RegExp(r'^[A-Za-z0-9.-]+$');
    return domainPattern.hasMatch(value);
  }

  bool _isSafeIpAddressHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    try {
      return InternetAddress.tryParse(host) != null;
    } on FormatException {
      return false;
    }
  }

  Future<bool> _probeUdp(String host, int port) async {
    RawDatagramSocket? socket;
    StreamSubscription<RawSocketEvent>? subscription;
    final completer = Completer<bool>();
    Timer? timeoutTimer;
    var timedOut = false;

    void cleanup() {
      unawaited(subscription?.cancel() ?? Future<void>.value());
      try {
        socket?.close();
      } catch (_) {}
    }

    void complete(bool value) {
      if (completer.isCompleted) {
        return;
      }
      timeoutTimer?.cancel();
      cleanup();
      completer.complete(value);
    }

    timeoutTimer = Timer(_probeTimeout, () {
      timedOut = true;
      complete(false);
    });

    try {
      final addresses = await InternetAddress.lookup(host);
      if (timedOut) {
        return completer.future;
      }
      if (addresses.isEmpty) {
        complete(false);
        return completer.future;
      }
      final target = addresses.first;
      socket = await RawDatagramSocket.bind(
        target.type == InternetAddressType.IPv6
            ? InternetAddress.anyIPv6
            : InternetAddress.anyIPv4,
        0,
      );
      if (timedOut) {
        cleanup();
        return completer.future;
      }
      socket.readEventsEnabled = true;

      subscription = socket.listen((event) {
        if (event != RawSocketEvent.read || completer.isCompleted) {
          return;
        }
        final datagram = socket?.receive();
        if (datagram == null) {
          return;
        }
        if (datagram.address == target && datagram.port == port) {
          complete(true);
        }
      });

      socket.send(_buildStunBindingRequest(), target, port);
    } catch (_) {
      if (!timedOut && !completer.isCompleted) {
        complete(false);
      }
    }

    return completer.future;
  }

  List<int> _buildStunBindingRequest() {
    final bytes = BytesBuilder();
    bytes.add(const <int>[0x00, 0x01]);
    bytes.add(const <int>[0x00, 0x00]);
    bytes.add(const <int>[0x21, 0x12, 0xA4, 0x42]);
    final random = Random.secure();
    bytes.add(List<int>.generate(12, (_) => random.nextInt(256)));
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
