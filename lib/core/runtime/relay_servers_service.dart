import 'dart:async';
import 'dart:io';

import '../node/node_facade.dart';
import 'server_availability.dart';
import 'server_availability_provider.dart';
import 'storage_service.dart';

class RelayServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'relay_servers';
  static const _probeInterval = Duration(seconds: 8);
  static const _defaultProbeTimeout = Duration(seconds: 4);

  final NodeFacade facade;
  final StorageService storage;
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

  RelayServersService({
    required this.facade,
    required this.storage,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _probeTimeout = probeTimeout;

  SecureStorageBox get _settings => storage.getSettings();

  @override
  String get providerKey => 'relay';

  @override
  List<String> get serverKeys => List<String>.unmodifiable(endpoints);

  @override
  Future<void> initialize() async {
    endpoints
      ..clear()
      ..addAll(_load());
    _seedAvailabilityForEndpoints(endpoints);
    _emitAvailability();
    await _persist();
    await facade.configureRelayServers(endpoints);
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
    await facade.addRelayServer(normalized);
    unawaited(refreshAvailability());
  }

  Future<void> remove(String endpoint) async {
    endpoints.remove(endpoint);
    _availabilityByEndpoint.remove(endpoint);
    _emitAvailability();
    await _persist();
    await facade.removeRelayServer(endpoint);
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
    await facade.configureRelayServers(endpoints);
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
    await facade.configureRelayServers(endpoints);
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
    await facade.configureRelayServers(endpoints);
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

  Future<void> refreshAvailabilityFor(List<String> selectedEndpoints) async {
    if (_disposed || _refreshInFlight) {
      return;
    }
    _refreshInFlight = true;
    try {
      final snapshot = selectedEndpoints
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty && endpoints.contains(item))
          .toList(growable: false);
      if (snapshot.isEmpty) {
        return;
      }
      final next = Map<String, ServerAvailability>.from(
        _availabilityByEndpoint,
      );
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
    return List<String>.from(facade.relayServers)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
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
    if (uri == null || uri.host.isEmpty) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }

    final client = HttpClient();
    if (uri.scheme == 'https' && _isSafeIpAddressHost(uri.host)) {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }

    try {
      final statusCode = await _healthStatusWithTimeout(
        client,
        uri.resolve('/health'),
      );
      if (statusCode == null) {
        return ServerAvailability.unavailable(
          error: 'таймаут проверки ${_probeTimeout.inSeconds}с',
          checkedAt: DateTime.now(),
        );
      }
      if (statusCode == 200) {
        return ServerAvailability.available(checkedAt: DateTime.now());
      }
      return ServerAvailability.unavailable(
        error: 'status $statusCode',
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      return ServerAvailability.unavailable(
        error: _shortError(error),
        checkedAt: DateTime.now(),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<int?> _healthStatusWithTimeout(HttpClient client, Uri uri) {
    final completer = Completer<int?>();
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

    void completeError(Object error, StackTrace stackTrace) {
      timeoutTimer?.cancel();
      if (timedOut || completer.isCompleted) {
        return;
      }
      completer.completeError(error, stackTrace);
    }

    try {
      client.getUrl(uri).then((request) => request.close()).then((
        response,
      ) async {
        final statusCode = response.statusCode;
        try {
          await response.drain<void>();
        } catch (_) {}
        timeoutTimer?.cancel();
        if (timedOut || completer.isCompleted) {
          return;
        }
        completer.complete(statusCode);
      }, onError: completeError);
    } catch (error, stackTrace) {
      completeError(error, stackTrace);
    }

    return completer.future.whenComplete(() => timeoutTimer?.cancel());
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
    if (trimmed.isEmpty) {
      return const ServerAvailability.unknown();
    }
    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.trim().isEmpty) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') ||
        !_isSafeRelayHost(uri.host.trim())) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }
    return const ServerAvailability.unknown();
  }

  bool _isSafeRelayHost(String host) {
    final value = host.trim();
    if (value.isEmpty || value.contains('%')) {
      return false;
    }
    if (_isSafeIpAddressHost(value)) {
      return true;
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
}
