import 'dart:async';
import 'dart:io';

import '../node/node_facade.dart';
import 'server_availability.dart';
import 'server_availability_poller.dart';
import 'server_availability_provider.dart';
import 'server_runtime_utils.dart';
import 'storage_service.dart';

typedef BootstrapWebSocketConnector =
    Future<WebSocket> Function(String url, {HttpClient? customClient});

class BootstrapServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'bootstrap_servers';
  static const _healthyProbeInterval = Duration(seconds: 8);
  static const _defaultProbeTimeout = Duration(seconds: 4);
  final NodeFacade facade;
  final StorageService storage;
  final BootstrapWebSocketConnector _webSocketConnector;
  final Duration _probeTimeout;
  late final ServerAvailabilityPoller _poller;

  final List<String> endpoints = <String>[];
  bool _disposed = false;

  BootstrapServersService({
    required this.facade,
    required this.storage,
    BootstrapWebSocketConnector? webSocketConnector,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _webSocketConnector =
           webSocketConnector ??
           ((url, {customClient}) =>
               WebSocket.connect(url, customClient: customClient)),
       _probeTimeout = probeTimeout {
    _poller = ServerAvailabilityPoller(
      providerKey: providerKey,
      serverKeysProvider: () => endpoints,
      probe: _probeEndpoint,
      seedAvailability: _initialAvailabilityForEndpoint,
      healthyProbeInterval: _healthyProbeInterval,
    );
  }

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
    _poller.syncKeys();
    await facade.configureBootstrapServers(endpoints);
    _poller.start();
    unawaited(refreshAvailability());
  }

  Future<void> add(String endpoint) async {
    final normalized = normalizeEndpoint(endpoint);
    if (normalized.isEmpty || endpoints.contains(normalized)) {
      return;
    }
    endpoints.add(normalized);
    _poller.syncKeys();
    await _persist();
    await facade.addBootstrapServer(normalized);
    unawaited(refreshAvailability());
  }

  Future<void> remove(String endpoint) async {
    final normalized = normalizeEndpoint(endpoint);
    endpoints.remove(normalized);
    _poller.syncKeys();
    await _persist();
    await facade.removeBootstrapServer(normalized);
  }

  Future<void> replace(List<String> next) async {
    endpoints
      ..clear()
      ..addAll(ServerRuntimeUtils.uniqueNormalized(next, normalizeEndpoint));
    _poller.syncKeys();
    await _persist();
    await facade.configureBootstrapServers(endpoints);
    unawaited(refreshAvailability());
  }

  Future<void> merge(List<String> incoming) async {
    ServerRuntimeUtils.mergeUnique(endpoints, incoming, normalizeEndpoint);
    _poller.syncKeys();
    await _persist();
    await facade.configureBootstrapServers(endpoints);
    unawaited(refreshAvailability());
  }

  Future<void> putFirst(String endpoint) async {
    final normalized = normalizeEndpoint(endpoint);
    final changed = ServerRuntimeUtils.putFirst(endpoints, normalized);
    if (!changed) {
      return;
    }
    _poller.syncKeys();
    await _persist();
    await facade.configureBootstrapServers(endpoints);
    unawaited(refreshAvailability());
  }

  @override
  Stream<Map<String, ServerAvailability>> get availabilityStream =>
      _poller.availabilityStream;

  @override
  Map<String, ServerAvailability> get availabilitySnapshot =>
      _poller.availabilitySnapshot;

  @override
  ServerAvailability availabilityFor(String endpoint) =>
      _poller.availabilityFor(endpoint);

  @override
  Future<void> refreshAvailability() async {
    if (_disposed) {
      return;
    }
    await _poller.refreshAvailability();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
  }

  List<String> _load() {
    final raw = _settings.get(_storageKey);
    if (raw is List) {
      final values = raw.whereType<String>();
      return ServerRuntimeUtils.uniqueNormalized(values, normalizeEndpoint);
    }
    return ServerRuntimeUtils.uniqueNormalized(
      facade.bootstrapServers,
      normalizeEndpoint,
    );
  }

  Future<void> _persist() async {
    await _settings.put(_storageKey, List<String>.from(endpoints));
  }

  static String normalizeEndpoint(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return '';
    }

    final candidate = raw.contains('://') ? raw : '//$raw';
    final uri = Uri.tryParse(candidate);
    if (uri == null) {
      return '';
    }

    final host = uri.host.trim();
    if (host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return '';
    }

    final scheme = _shouldUseSecureScheme(host) ? 'wss' : 'ws';
    final buffer = StringBuffer()..write('$scheme://');
    if (host.contains(':') && !host.startsWith('[')) {
      buffer.write('[$host]');
    } else {
      buffer.write(host);
    }
    if (uri.hasPort) {
      buffer.write(':${uri.port}');
    }
    return buffer.toString();
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
    if (uri.scheme == 'wss') {
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
      _closeSocketSilently(socket);
      return ServerAvailability.available(checkedAt: DateTime.now());
    } catch (error) {
      return ServerAvailability.unavailable(
        error: ServerRuntimeUtils.shortError(error),
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

  static bool _shouldUseSecureScheme(String host) {
    if (host.isEmpty) {
      return true;
    }
    if (host.toLowerCase() == 'localhost') {
      return false;
    }

    final address = InternetAddress.tryParse(host);
    if (address == null) {
      return true;
    }

    if (address.type == InternetAddressType.IPv4) {
      final octets = address.rawAddress;
      if (octets.length == 4) {
        final first = octets[0];
        final second = octets[1];
        if (first == 10 ||
            first == 127 ||
            (first == 172 && second >= 16 && second <= 31) ||
            (first == 192 && second == 168) ||
            (first == 169 && second == 254)) {
          return false;
        }
      }
      return true;
    }

    final normalized = address.address.toLowerCase();
    if (normalized == '::1' ||
        normalized.startsWith('fc') ||
        normalized.startsWith('fd') ||
        normalized.startsWith('fe80:')) {
      return false;
    }
    return true;
  }
}
