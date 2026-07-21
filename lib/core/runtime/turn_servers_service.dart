import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../node/node_facade.dart';
import '../turn/turn_server_config.dart';
import 'app_file_logger.dart';
import 'server_availability.dart';
import 'server_availability_poller.dart';
import 'server_availability_provider.dart';
import 'server_runtime_utils.dart';
import 'storage_service.dart';

class TurnServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'turn_servers';
  static const _healthyProbeInterval = Duration(seconds: 10);
  static const _defaultProbeTimeout = Duration(seconds: 4);
  static const _defaultTurnPort = 3478;

  final NodeFacade facade;
  final StorageService storage;
  final Duration _probeTimeout;
  late final ServerAvailabilityPoller _poller;

  final List<TurnServerConfig> servers = <TurnServerConfig>[];
  final Map<String, int> _failureCounts = <String, int>{};
  final Map<String, DateTime> _lastFailureTime = <String, DateTime>{};
  final Map<String, int> _basePriorityByUrl = <String, int>{};
  bool _disposed = false;

  TurnServersService({
    required this.facade,
    required this.storage,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _probeTimeout = probeTimeout {
    _poller = ServerAvailabilityPoller(
      providerKey: providerKey,
      serverKeysProvider: () =>
          servers.map((entry) => entry.url).toList(growable: false),
      probe: _probeServer,
      seedAvailability: _initialAvailabilityForUrl,
      healthyProbeInterval: _healthyProbeInterval,
      logger: (message) => AppFileLogger.log('[turn_service] $message'),
    );
  }

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
    _poller.syncKeys();
    await _persist();
    _rememberBasePriorities(servers);
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    facade.turnAllocator.setCallbacks(
      onSuccess: reportConnectionSuccess,
      onFailure: reportConnectionFailure,
    );
    _poller.start();
    unawaited(refreshAvailability());
  }

  /// Отмечает неудачу подключения к TURN серверу и автоматически понижает приоритет
  void reportConnectionFailure(String url) {
    _failureCounts[url] = (_failureCounts[url] ?? 0) + 1;
    _lastFailureTime[url] = DateTime.now();
    unawaited(facade.configureTurnServers(getServersWithAdjustedPriorities()));
    _poller.overrideAvailability(
      url,
      ServerAvailability.unavailable(
        error: 'ошибка подключения',
        checkedAt: DateTime.now(),
      ),
    );
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
    _poller.overrideAvailability(
      url,
      ServerAvailability.available(checkedAt: DateTime.now()),
    );
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
    final normalized = _normalizeServerConfig(server);
    if (normalized.url.isEmpty ||
        servers.any((entry) => entry.url == normalized.url)) {
      return;
    }
    servers.add(normalized);
    _basePriorityByUrl[normalized.url] = normalized.priority;
    _poller.syncKeys();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> remove(String url) async {
    final normalized = normalizeTurnsEndpoint(url);
    servers.removeWhere((entry) => entry.url == normalized);
    _failureCounts.remove(normalized);
    _lastFailureTime.remove(normalized);
    _basePriorityByUrl.remove(normalized);
    _poller.syncKeys();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
  }

  Future<void> replace(List<TurnServerConfig> next) async {
    servers
      ..clear()
      ..addAll(
        next.map((entry) {
          final normalized = _normalizeServerConfig(entry);
          if (normalized.url.isEmpty) {
            return null;
          }
          return normalized;
        }).whereType<TurnServerConfig>(),
      );
    _logServers('replace:normalized', servers);
    _failureCounts.clear();
    _lastFailureTime.clear();
    _rememberBasePriorities(servers);
    _poller.syncKeys();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> merge(List<TurnServerConfig> incoming) async {
    for (final server in incoming) {
      final normalized = _normalizeServerConfig(server);
      if (normalized.url.isEmpty) {
        continue;
      }
      if (normalized.url.isEmpty ||
          servers.any((entry) => entry.url == normalized.url)) {
        continue;
      }
      servers.add(normalized);
      _basePriorityByUrl[normalized.url] = normalized.priority;
    }
    _logServers('merge:result', servers);
    _poller.syncKeys();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> putFirst(TurnServerConfig server) async {
    final normalized = _normalizeServerConfig(server);
    if (normalized.url.isEmpty) {
      return;
    }
    servers.removeWhere((entry) => entry.url == normalized.url);
    servers.insert(0, normalized);
    _basePriorityByUrl[normalized.url] = normalized.priority;
    _poller.syncKeys();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  Future<void> putFirstMany(List<TurnServerConfig> incoming) async {
    final normalized = incoming
        .map(_normalizeServerConfig)
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
    }
    _logServers('putFirstMany:result', servers);
    _poller.syncKeys();
    await _persist();
    await facade.configureTurnServers(getServersWithAdjustedPriorities());
    unawaited(refreshAvailability());
  }

  @override
  Stream<Map<String, ServerAvailability>> get availabilityStream =>
      _poller.availabilityStream;

  @override
  Map<String, ServerAvailability> get availabilitySnapshot =>
      _poller.availabilitySnapshot;

  @override
  ServerAvailability availabilityFor(String url) =>
      _poller.availabilityFor(url);

  @override
  Future<void> refreshAvailability() async {
    if (_disposed) {
      return;
    }
    await _poller.refreshAvailability();
  }

  Future<void> refreshAvailabilityFor(List<String> selectedUrls) async {
    if (_disposed) {
      return;
    }
    await _poller.refreshAvailabilityFor(selectedUrls);
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
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
            final normalized = _normalizeServerConfig(config);
            if (normalized.url.isEmpty) {
              return null;
            }
            return normalized;
          })
          .whereType<TurnServerConfig>()
          .fold<List<TurnServerConfig>>(<TurnServerConfig>[], (acc, item) {
            if (acc.any((existing) => existing.url == item.url)) {
              return acc;
            }
            acc.add(item);
            return acc;
          })
          .toList(growable: false);
    }
    return facade.turnServers
        .map((entry) {
          final normalized = _normalizeServerConfig(entry);
          if (normalized.url.isEmpty) {
            return null;
          }
          return normalized;
        })
        .whereType<TurnServerConfig>()
        .fold<List<TurnServerConfig>>(<TurnServerConfig>[], (acc, item) {
          if (acc.any((existing) => existing.url == item.url)) {
            return acc;
          }
          acc.add(item);
          return acc;
        })
        .toList(growable: false);
  }

  Future<void> _persist() async {
    await _settings.put(
      _storageKey,
      servers.map((entry) => entry.toJson()).toList(growable: false),
    );
  }

  void _rememberBasePriorities(List<TurnServerConfig> items) {
    _basePriorityByUrl
      ..clear()
      ..addEntries(items.map((item) => MapEntry(item.url, item.priority)));
  }

  ServerAvailability _initialAvailabilityForUrl(String raw) {
    final normalized = normalizeTurnsEndpoint(raw);
    if (normalized == null || normalized.isEmpty) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }
    return const ServerAvailability.unknown();
  }

  TurnServerConfig _normalizeServerConfig(TurnServerConfig server) {
    final normalizedUrl = normalizeTurnsEndpoint(server.url) ?? '';
    final normalizedUsername = server.username.trim().isEmpty
        ? 'peerlink'
        : server.username.trim();
    final normalizedPassword = server.password.isEmpty
        ? 'peerlink'
        : server.password;
    return server.copyWith(
      url: normalizedUrl,
      username: normalizedUsername,
      password: normalizedPassword,
    );
  }

  static String? normalizeTurnsEndpoint(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return null;
    }
    if (raw.contains(';')) {
      return null;
    }

    final candidate = _turnUriCandidate(raw);
    final uri = Uri.tryParse(candidate);
    if (uri == null) {
      return null;
    }

    final host = uri.host.trim();
    if (host.isEmpty || uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      return null;
    }

    if (!_isSafeTurnHostStatic(host)) {
      return null;
    }

    final scheme = raw.toLowerCase().startsWith('turns:') ? 'turns' : 'turn';
    final buffer = StringBuffer()..write('$scheme:');
    if (host.contains(':') && !host.startsWith('[')) {
      buffer.write('[$host]');
    } else {
      buffer.write(host);
    }
    final defaultPort = scheme == 'turns' ? 5349 : _defaultTurnPort;
    final normalizedPort = uri.hasPort ? uri.port : defaultPort;
    final transport = _normalizeTurnTransport(uri.queryParameters['transport']);
    buffer.write(':$normalizedPort');
    buffer.write('?transport=$transport');
    return buffer.toString();
  }

  static String _normalizeTurnTransport(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value == 'udp') {
      return 'udp';
    }
    return 'tcp';
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
        error: ServerRuntimeUtils.shortError(lastError ?? 'no response'),
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      return ServerAvailability.unavailable(
        error: ServerRuntimeUtils.shortError(error),
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
      host = _extractTurnHost(uri);
      port = _extractTurnPort(uri, scheme: scheme);
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
        final ok = await _probeStreamSocket(socket);
        return ok ? null : 'turns probe timeout';
      } catch (error) {
        return ServerRuntimeUtils.shortError(error);
      }
    }

    if (transport == 'tcp' || transport.isEmpty) {
      try {
        final socket = await _socketWithTimeout(host, port);
        if (socket == null) {
          return 'tcp probe timeout';
        }
        final ok = await _probeStreamSocket(socket);
        return ok ? null : 'tcp probe timeout';
      } catch (error) {
        return ServerRuntimeUtils.shortError(error);
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

  static bool _isSafeTurnHostStatic(String host) {
    final value = host.trim();
    if (value.isEmpty || value.contains('%')) {
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

  static String _turnUriCandidate(String raw) {
    final lower = raw.toLowerCase();
    if (lower.startsWith('turns:')) {
      final rest = raw.substring('turns:'.length);
      return '//$rest';
    }
    if (lower.startsWith('turn:')) {
      final rest = raw.substring('turn:'.length);
      return '//$rest';
    }
    if (raw.contains('://')) {
      final hostPort = raw.substring(raw.indexOf('://') + 3);
      return '//$hostPort';
    }
    return '//$raw';
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

  String _extractTurnHost(Uri uri) {
    if (uri.host.isNotEmpty) {
      return uri.host.trim();
    }
    final path = uri.path.trim();
    if (path.isEmpty) {
      return '';
    }
    if (path.startsWith('[')) {
      final closing = path.indexOf(']');
      if (closing <= 1) {
        return '';
      }
      return path.substring(1, closing).trim();
    }
    final lastColon = path.lastIndexOf(':');
    if (lastColon > 0) {
      return path.substring(0, lastColon).trim();
    }
    return path;
  }

  int _extractTurnPort(Uri uri, {required String scheme}) {
    if (uri.hasPort) {
      return uri.port;
    }
    final defaultPort = scheme == 'turns' ? 5349 : 3478;
    final path = uri.path.trim();
    if (path.isEmpty) {
      return defaultPort;
    }
    if (path.startsWith('[')) {
      final closing = path.indexOf(']');
      if (closing == -1 || closing == path.length - 1) {
        return defaultPort;
      }
      final suffix = path.substring(closing + 1);
      if (!suffix.startsWith(':')) {
        return defaultPort;
      }
      return int.tryParse(suffix.substring(1).trim()) ?? defaultPort;
    }
    final lastColon = path.lastIndexOf(':');
    if (lastColon <= 0 || lastColon == path.length - 1) {
      return defaultPort;
    }
    return int.tryParse(path.substring(lastColon + 1).trim()) ?? defaultPort;
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

  Future<bool> _probeStreamSocket(Socket socket) async {
    StreamSubscription<Uint8List>? subscription;
    final completer = Completer<bool>();
    Timer? timeoutTimer;

    void cleanup() {
      timeoutTimer?.cancel();
      unawaited(subscription?.cancel() ?? Future<void>.value());
      try {
        socket.destroy();
      } catch (_) {}
    }

    void complete(bool value) {
      if (completer.isCompleted) {
        return;
      }
      cleanup();
      completer.complete(value);
    }

    timeoutTimer = Timer(_probeTimeout, () => complete(false));

    try {
      subscription = socket.listen(
        (data) {
          if (data.isNotEmpty) {
            complete(true);
          }
        },
        onError: (_) => complete(false),
        onDone: () => complete(false),
        cancelOnError: true,
      );
      socket.add(_buildStunBindingRequest());
      await socket.flush();
    } catch (_) {
      complete(false);
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

  void _logServers(String phase, List<TurnServerConfig> items) {
    AppFileLogger.log(
      '[turn_service] $phase count=${items.length} urls=${items.map((e) => e.url).join(',')}',
    );
  }
}
