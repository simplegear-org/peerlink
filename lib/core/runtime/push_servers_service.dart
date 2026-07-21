import 'dart:async';
import 'dart:io';

import 'app_file_logger.dart';
import 'server_availability.dart';
import 'server_availability_poller.dart';
import 'server_availability_provider.dart';
import 'server_runtime_utils.dart';
import 'storage_service.dart';

class PushServerEntry {
  final String endpoint;
  final bool paused;

  const PushServerEntry({
    required this.endpoint,
    this.paused = false,
  });

  PushServerEntry copyWith({
    String? endpoint,
    bool? paused,
  }) {
    return PushServerEntry(
      endpoint: endpoint ?? this.endpoint,
      paused: paused ?? this.paused,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'endpoint': endpoint,
      'paused': paused,
    };
  }

  static PushServerEntry? fromStorage(Object? raw) {
    if (raw is String) {
      final normalized = PushServersService._normalizeIncomingEndpoint(raw);
      if (normalized.isEmpty) {
        return null;
      }
      return PushServerEntry(endpoint: normalized);
    }
    if (raw is Map) {
      final map = Map<String, dynamic>.from(raw);
      final normalized = PushServersService._normalizeIncomingEndpoint(
        map['endpoint']?.toString() ?? '',
      );
      if (normalized.isEmpty) {
        return null;
      }
      return PushServerEntry(
        endpoint: normalized,
        paused: map['paused'] == true,
      );
    }
    return null;
  }
}

class PushServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'push_servers';
  static const _legacyStorageKey = 'push_server_url';
  static const _healthyProbeInterval = Duration(seconds: 8);
  static const _defaultProbeTimeout = Duration(seconds: 4);

  final StorageService storage;
  final Duration _probeTimeout;
  late final ServerAvailabilityPoller _poller;

  final List<PushServerEntry> entries = <PushServerEntry>[];
  bool _disposed = false;

  PushServersService({
    required this.storage,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _probeTimeout = probeTimeout {
    _poller = ServerAvailabilityPoller(
      providerKey: providerKey,
      serverKeysProvider: () => activeEndpoints,
      probe: _probeEndpoint,
      seedAvailability: _initialAvailabilityForEndpoint,
      healthyProbeInterval: _healthyProbeInterval,
      logger: (message) => AppFileLogger.log('[push_service] $message'),
    );
  }

  SecureStorageBox get _settings => storage.getSettings();

  @override
  String get providerKey => 'push';

  List<String> get endpoints => List<String>.unmodifiable(
    entries.map((item) => item.endpoint),
  );

  List<String> get activeEndpoints => List<String>.unmodifiable(
    entries.where((item) => !item.paused).map((item) => item.endpoint),
  );

  @override
  List<String> get serverKeys => List<String>.unmodifiable(activeEndpoints);

  @override
  Future<void> initialize() async {
    entries
      ..clear()
      ..addAll(_load());
    await _migrateLegacyPushServerUrl();
    _poller.syncKeys();
    await _persist();
    _poller.start();
    _log(
      'initialize endpoints=${entries.length} active=${activeEndpoints.length}',
    );
    unawaited(refreshAvailability());
  }

  Future<void> add(String endpoint) async {
    final normalized = normalizeEndpoint(endpoint);
    if (normalized.isEmpty ||
        entries.any((item) => item.endpoint == normalized)) {
      _log('add skip endpoint=$endpoint reason=duplicate_or_empty');
      return;
    }
    entries.add(PushServerEntry(endpoint: normalized));
    _poller.syncKeys();
    await _persist();
    _log(
      'add endpoint=$normalized total=${entries.length} active=${activeEndpoints.length}',
    );
    unawaited(refreshAvailability());
  }

  Future<void> update(
    String currentEndpoint, {
    required String host,
    int? port,
  }) async {
    final currentNormalized = currentEndpoint.trim();
    if (currentNormalized.isEmpty) {
      _log('update skip reason=empty_current');
      return;
    }
    final nextNormalized = normalizeHostPort(host: host, port: port);
    if (currentNormalized == nextNormalized) {
      _log('update skip endpoint=$currentNormalized reason=no_changes');
      return;
    }
    if (entries.any((item) => item.endpoint == nextNormalized)) {
      throw const FormatException('Такой push сервер уже добавлен');
    }
    final index = entries.indexWhere(
      (item) => item.endpoint == currentNormalized,
    );
    if (index < 0) {
      _log('update skip endpoint=$currentNormalized reason=not_found');
      return;
    }
    entries[index] = entries[index].copyWith(endpoint: nextNormalized);
    _poller.syncKeys();
    await _persist();
    _log('update endpoint=$currentNormalized next=$nextNormalized');
    unawaited(refreshAvailability());
  }

  Future<void> setPaused(String endpoint, {required bool paused}) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      _log('pause skip reason=empty');
      return;
    }
    final index = entries.indexWhere((item) => item.endpoint == normalized);
    if (index < 0) {
      _log('pause skip endpoint=$normalized reason=not_found');
      return;
    }
    final current = entries[index];
    if (current.paused == paused) {
      _log('pause skip endpoint=$normalized reason=no_changes paused=$paused');
      return;
    }
    entries[index] = current.copyWith(paused: paused);
    _poller.syncKeys();
    await _persist();
    _log(
      'pause endpoint=$normalized paused=$paused active=${activeEndpoints.length}',
    );
    if (!paused) {
      unawaited(refreshAvailability());
    }
  }

  bool isPaused(String endpoint) {
    final normalized = endpoint.trim();
    final index = entries.indexWhere((item) => item.endpoint == normalized);
    if (index < 0) {
      return false;
    }
    return entries[index].paused;
  }

  Future<void> remove(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      _log('remove skip reason=empty');
      return;
    }
    final removedIndex = entries.indexWhere((item) => item.endpoint == normalized);
    final removed = removedIndex >= 0;
    if (removed) {
      entries.removeAt(removedIndex);
    }
    _poller.syncKeys();
    await _persist();
    _log(
      removed
          ? 'remove endpoint=$normalized total=${entries.length}'
          : 'remove skip endpoint=$normalized reason=not_found',
    );
  }

  Future<void> merge(List<String> incoming) async {
    if (incoming.isEmpty) {
      _log('merge skip reason=empty');
      return;
    }
    final current = entries.map((item) => item.endpoint).toSet().toList(
      growable: true,
    );
    final changed = ServerRuntimeUtils.mergeUnique(
      current,
      incoming,
      _normalizeIncomingEndpoint,
    );
    if (!changed) {
      _log('merge skip reason=no_changes');
      return;
    }
    final pausedByEndpoint = <String, bool>{
      for (final item in entries) item.endpoint: item.paused,
    };
    entries
      ..clear()
      ..addAll(
        (current..sort()).map(
          (endpoint) => PushServerEntry(
            endpoint: endpoint,
            paused: pausedByEndpoint[endpoint] ?? false,
          ),
        ),
      );
    _poller.syncKeys();
    await _persist();
    _log(
      'merge result total=${entries.length} active=${activeEndpoints.length}',
    );
    unawaited(refreshAvailability());
  }

  Future<void> replace(List<String> incoming) async {
    final normalized = ServerRuntimeUtils.uniqueNormalized(
      incoming,
      _normalizeIncomingEndpoint,
    ).toList(growable: true)
      ..sort();
    entries
      ..clear()
      ..addAll(normalized.map((item) => PushServerEntry(endpoint: item)));
    _poller.syncKeys();
    await _persist();
    _log(
      'replace result total=${entries.length} active=${activeEndpoints.length}',
    );
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
      _log('refresh skip reason=disposed');
      return;
    }
    _log(
      'refresh start total=${entries.length} active=${activeEndpoints.length}',
    );
    await _poller.refreshAvailability();
  }

  @override
  void dispose() {
    _disposed = true;
    _poller.dispose();
    _log('dispose');
  }

  List<PushServerEntry> _load() {
    final raw = _settings.get(_storageKey);
    if (raw is List) {
      final resultByEndpoint = <String, PushServerEntry>{};
      for (final item in raw) {
        final entry = PushServerEntry.fromStorage(item);
        if (entry == null) {
          continue;
        }
        resultByEndpoint[entry.endpoint] = entry;
      }
      final result = resultByEndpoint.values.toList(growable: false)
        ..sort((a, b) => a.endpoint.compareTo(b.endpoint));
      return result;
    }
    return const <PushServerEntry>[];
  }

  Future<void> _persist() async {
    final normalized = entries.toList(growable: false)
      ..sort((a, b) => a.endpoint.compareTo(b.endpoint));
    await _settings.put(
      _storageKey,
      normalized.map((item) => item.toJson()).toList(growable: false),
    );
  }

  static String normalizeEndpoint(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      throw const FormatException('Некорректный адрес push сервера');
    }
    if (raw.contains('://') || raw.contains('/')) {
      throw const FormatException('Введите только домен или IP');
    }
    return normalizeHostPort(host: raw);
  }

  static String normalizeHostPort({required String host, int? port}) {
    final rawHost = host.trim();
    if (rawHost.isEmpty) {
      throw const FormatException('Некорректный адрес push сервера');
    }
    if (rawHost.contains('://') || rawHost.contains('/')) {
      throw const FormatException('Введите только домен или IP');
    }
    if (port != null && (port <= 0 || port > 65535)) {
      throw const FormatException('Некорректный порт push сервера');
    }
    final uri = Uri(scheme: 'https', host: rawHost, port: port);
    if (uri.host.trim().isEmpty) {
      throw const FormatException('Некорректный адрес push сервера');
    }
    return uri.toString();
  }

  static List<String> extractActiveEndpointsFromStorage(Object? raw) {
    if (raw is! List) {
      return const <String>[];
    }
    final result = <String>{};
    for (final item in raw) {
      final entry = PushServerEntry.fromStorage(item);
      if (entry == null || entry.paused) {
        continue;
      }
      result.add(entry.endpoint);
    }
    return result.toList(growable: false)..sort();
  }

  static String _normalizeIncomingEndpoint(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null ||
        parsed.host.isEmpty ||
        !parsed.hasScheme ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      return '';
    }
    return parsed.toString();
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
        (scheme != 'http' && scheme != 'https')) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }

    final client = HttpClient();
    ServerRuntimeUtils.enableHostMatchingBadCertificateForHttps(client, uri);

    try {
      final healthStatusCode = await ServerRuntimeUtils.requestStatusWithTimeout(
        client: client,
        uri: uri.resolve('/health'),
        method: 'GET',
        timeout: _probeTimeout,
      );
      if (healthStatusCode == null) {
        return ServerAvailability.unavailable(
          error: 'таймаут проверки ${_probeTimeout.inSeconds}с',
          checkedAt: DateTime.now(),
        );
      }
      if (healthStatusCode == 200) {
        return ServerAvailability.available(checkedAt: DateTime.now());
      }
      return ServerAvailability.unavailable(
        error: 'health status $healthStatusCode',
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      return ServerAvailability.unavailable(
        error: ServerRuntimeUtils.shortError(error, maxLength: 140),
        checkedAt: DateTime.now(),
      );
    } finally {
      client.close(force: true);
    }
  }

  ServerAvailability _initialAvailabilityForEndpoint(String endpoint) {
    final trimmed = endpoint.trim();
    final uri = Uri.tryParse(trimmed);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      return ServerAvailability.unavailable(
        error: 'некорректный адрес',
        checkedAt: DateTime.now(),
      );
    }
    return const ServerAvailability.unknown();
  }

  Future<void> _migrateLegacyPushServerUrl() async {
    if (entries.isNotEmpty) {
      return;
    }
    final legacy = _settings.get(_legacyStorageKey);
    if (legacy is! String || legacy.trim().isEmpty) {
      return;
    }
    try {
      final normalized = normalizeEndpoint(legacy);
      entries
        ..clear()
        ..add(PushServerEntry(endpoint: normalized));
      _log('legacy migrated endpoint=$normalized');
      await _persist();
    } catch (_) {
      _log('legacy migrate skipped reason=invalid_value');
    }
  }

  void _log(String message) {
    AppFileLogger.log('[push_service] $message');
  }
}
