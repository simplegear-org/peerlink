import 'dart:async';
import 'dart:io';

import '../node/node_facade.dart';
import 'server_availability.dart';
import 'server_availability_provider.dart';
import 'storage_service.dart';

class BootstrapServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'bootstrap_servers';
  static const _probeInterval = Duration(seconds: 8);

  final NodeFacade facade;
  final StorageService storage;

  final List<String> endpoints = <String>[];
  final Map<String, ServerAvailability> _availabilityByEndpoint =
      <String, ServerAvailability>{};
  final StreamController<Map<String, ServerAvailability>>
      _availabilityController =
      StreamController<Map<String, ServerAvailability>>.broadcast();
  Timer? _probeTimer;
  bool _disposed = false;

  BootstrapServersService({
    required this.facade,
    required this.storage,
  });

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
    if (_disposed) {
      return;
    }
    final snapshot = List<String>.from(endpoints);
    if (snapshot.isEmpty) {
      _availabilityByEndpoint.clear();
      _emitAvailability();
      return;
    }

    final next = <String, ServerAvailability>{};
    for (final endpoint in snapshot) {
      next[endpoint] = await _probeEndpoint(endpoint);
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
    await _settings.put(
      _storageKey,
      List<String>.from(endpoints),
    );
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

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    if (uri.scheme == 'wss' && InternetAddress.tryParse(uri.host) != null) {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }

    try {
      final socket = await WebSocket.connect(
        trimmed,
        customClient: client,
      ).timeout(const Duration(seconds: 4));
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

  String _shortError(Object error) {
    final text = error.toString().trim();
    if (text.length <= 80) {
      return text;
    }
    return '${text.substring(0, 77)}...';
  }
}
