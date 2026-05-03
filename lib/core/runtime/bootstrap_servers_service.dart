import 'dart:async';
import 'dart:io';

import '../node/node_facade.dart';
import 'server_availability.dart';
import 'server_availability_provider.dart';
import 'storage_service.dart';

typedef BootstrapWebSocketConnector =
    Future<WebSocket> Function(String url, {HttpClient? customClient});

class BootstrapServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'bootstrap_servers';
  static const _probeInterval = Duration(seconds: 8);
  static const _defaultProbeTimeout = Duration(seconds: 4);

  final NodeFacade facade;
  final StorageService storage;
  final BootstrapWebSocketConnector _webSocketConnector;
  final Duration _probeTimeout;

  final List<String> endpoints = <String>[];
  final Map<String, ServerAvailability> _availabilityByEndpoint =
      <String, ServerAvailability>{};
  final StreamController<Map<String, ServerAvailability>>
  _availabilityController =
      StreamController<Map<String, ServerAvailability>>.broadcast();
  Timer? _probeTimer;
  bool _disposed = false;
  bool _refreshInFlight = false;

  BootstrapServersService({
    required this.facade,
    required this.storage,
    BootstrapWebSocketConnector? webSocketConnector,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _webSocketConnector =
           webSocketConnector ??
           ((url, {customClient}) =>
               WebSocket.connect(url, customClient: customClient)),
       _probeTimeout = probeTimeout;

  SecureStorageBox get _settings => storage.getSettings();

  @override
  String get providerKey => 'bootstrap';

  @override
  List<String> get serverKeys => List<String>.unmodifiable(endpoints);

  @override
  Future<void> initialize() async {
    endpoints
      ..clear()
      ..addAll(_load());
    _seedAvailabilityForEndpoints(endpoints);
    _emitAvailability();
    await facade.configureBootstrapServers(endpoints);
    _startProbeLoop();
    unawaited(refreshAvailability());
  }

  Future<void> add(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty || endpoints.contains(normalized)) {
      return;
    }
    endpoints.add(normalized);
    _availabilityByEndpoint[normalized] = _initialAvailabilityForEndpoint(
      normalized,
    );
    _emitAvailability();
    await _persist();
    await facade.addBootstrapServer(normalized);
    unawaited(refreshAvailability());
  }

  Future<void> remove(String endpoint) async {
    endpoints.remove(endpoint);
    _availabilityByEndpoint.remove(endpoint);
    _emitAvailability();
    await _persist();
    await facade.removeBootstrapServer(endpoint);
  }

  Future<void> replace(List<String> next) async {
    endpoints
      ..clear()
      ..addAll(
        next.map((item) => item.trim()).where((item) => item.isNotEmpty),
      );
    _retainAvailability();
    _seedAvailabilityForEndpoints(endpoints);
    await _persist();
    await facade.configureBootstrapServers(endpoints);
    unawaited(refreshAvailability());
  }

  Future<void> merge(List<String> incoming) async {
    for (final item in incoming) {
      final normalized = item.trim();
      if (normalized.isEmpty || endpoints.contains(normalized)) {
        continue;
      }
      endpoints.add(normalized);
    }
    _retainAvailability();
    _seedAvailabilityForEndpoints(endpoints);
    await _persist();
    await facade.configureBootstrapServers(endpoints);
    unawaited(refreshAvailability());
  }

  Future<void> putFirst(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      return;
    }
    endpoints.remove(normalized);
    endpoints.insert(0, normalized);
    _availabilityByEndpoint[normalized] = _initialAvailabilityForEndpoint(
      normalized,
    );
    _emitAvailability();
    await _persist();
    await facade.configureBootstrapServers(endpoints);
    unawaited(refreshAvailability());
  }

  @override
  Stream<Map<String, ServerAvailability>> get availabilityStream =>
      _availabilityController.stream;

  @override
  Map<String, ServerAvailability> get availabilitySnapshot =>
      Map<String, ServerAvailability>.unmodifiable(_availabilityByEndpoint);

  @override
  ServerAvailability availabilityFor(String endpoint) =>
      _availabilityByEndpoint[endpoint] ?? const ServerAvailability.unknown();

  @override
  Future<void> refreshAvailability() async {
    if (_disposed || _refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    try {
      final snapshot = List<String>.from(endpoints);
      if (snapshot.isEmpty) {
        _availabilityByEndpoint.clear();
        _emitAvailability();
        return;
      }

      final next = <String, ServerAvailability>{};
      for (final endpoint in snapshot) {
        try {
          next[endpoint] = await _probeEndpoint(endpoint);
        } catch (error) {
          next[endpoint] = ServerAvailability.unavailable(
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
      _availabilityByEndpoint
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

  List<String> _load() {
    final raw = _settings.get(_storageKey);
    if (raw is List) {
      return raw
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return List<String>.from(facade.bootstrapServers);
  }

  Future<void> _persist() async {
    await _settings.put(_storageKey, List<String>.from(endpoints));
  }

  void _startProbeLoop() {
    _probeTimer?.cancel();
    _probeTimer = Timer.periodic(_probeInterval, (_) {
      unawaited(refreshAvailability());
    });
  }

  void _retainAvailability() {
    _availabilityByEndpoint.removeWhere((key, _) => !endpoints.contains(key));
    _emitAvailability();
  }

  void _seedAvailabilityForEndpoints(List<String> items) {
    for (final endpoint in items) {
      _availabilityByEndpoint.putIfAbsent(
        endpoint,
        () => _initialAvailabilityForEndpoint(endpoint),
      );
    }
  }

  void _emitAvailability() {
    if (_disposed || _availabilityController.isClosed) {
      return;
    }
    _availabilityController.add(
      Map<String, ServerAvailability>.from(_availabilityByEndpoint),
    );
  }

  Future<ServerAvailability> _probeEndpoint(String endpoint) async {
    final trimmed = endpoint.trim();
    if (trimmed.isEmpty) {
      return const ServerAvailability.unknown();
    }

    final uri = Uri.tryParse(trimmed);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        uri.host.isEmpty ||
        (scheme != 'ws' && scheme != 'wss')) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }

    final client = HttpClient();
    if (uri.scheme == 'wss' && _isSafeIpAddressHost(uri.host)) {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }

    try {
      final socket = await _connectWithTimeout(trimmed, client);
      if (socket == null) {
        return ServerAvailability.unavailable(
          error: 'таймаут проверки ${_probeTimeout.inSeconds}с',
          checkedAt: DateTime.now(),
        );
      }
      if (_disposed) {
        try {
          await socket.close();
        } catch (_) {}
        return const ServerAvailability.unknown();
      }
      await socket.close();
      return ServerAvailability.available(checkedAt: DateTime.now());
    } catch (error) {
      return ServerAvailability.unavailable(
        error: _shortError(error),
        checkedAt: DateTime.now(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<WebSocket?> _connectWithTimeout(String endpoint, HttpClient client) {
    final completer = Completer<WebSocket?>();
    Timer? timeoutTimer;
    var timedOut = false;

    void completeAsTimeout() {
      timedOut = true;
      if (!completer.isCompleted) {
        completer.complete(null);
      }
      client.close(force: true);
    }

    timeoutTimer = Timer(_probeTimeout, completeAsTimeout);

    try {
      _webSocketConnector(endpoint, customClient: client).then(
        (socket) {
          timeoutTimer?.cancel();
          if (timedOut || completer.isCompleted) {
            _closeSocketSilently(socket);
            return;
          }
          completer.complete(socket);
        },
        onError: (Object error, StackTrace stackTrace) {
          timeoutTimer?.cancel();
          if (timedOut || completer.isCompleted) {
            return;
          }
          completer.completeError(error, stackTrace);
        },
      );
    } catch (error, stackTrace) {
      timeoutTimer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }

    return completer.future.whenComplete(() => timeoutTimer?.cancel());
  }

  void _closeSocketSilently(WebSocket socket) {
    try {
      unawaited(socket.close().catchError((_) {}));
    } catch (_) {}
  }

  String _shortError(Object error) {
    final text = error.toString().trim();
    if (text.length <= 80) {
      return text;
    }
    return '${text.substring(0, 77)}...';
  }

  ServerAvailability _initialAvailabilityForEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.host.trim().isEmpty ||
        (uri.scheme != 'ws' && uri.scheme != 'wss')) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }
    return const ServerAvailability.unknown();
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
}
