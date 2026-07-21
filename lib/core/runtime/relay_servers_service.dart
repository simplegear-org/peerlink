import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../node/node_facade.dart';
import 'server_availability.dart';
import 'server_availability_poller.dart';
import 'server_availability_provider.dart';
import 'server_runtime_utils.dart';
import 'storage_service.dart';

class RelayServersService implements ServerAvailabilityProvider {
  static const _storageKey = 'relay_servers';
  static const _healthyProbeInterval = Duration(seconds: 8);
  static const _defaultProbeTimeout = Duration(seconds: 4);
  static const _defaultRelayPort = 444;

  final NodeFacade facade;
  final StorageService storage;
  final Duration _probeTimeout;
  late final ServerAvailabilityPoller _poller;

  final List<String> endpoints = <String>[];
  bool _disposed = false;

  RelayServersService({
    required this.facade,
    required this.storage,
    Duration probeTimeout = _defaultProbeTimeout,
  }) : _probeTimeout = probeTimeout {
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
  String get providerKey => 'relay';

  @override
  List<String> get serverKeys => List<String>.unmodifiable(endpoints);

  @override
  Future<void> initialize() async {
    endpoints
      ..clear()
      ..addAll(_load());
    _poller.syncKeys();
    await _persist();
    await facade.configureRelayServers(endpoints);
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
    await facade.addRelayServer(normalized);
    unawaited(refreshAvailability());
  }

  Future<void> remove(String endpoint) async {
    final normalized = normalizeEndpoint(endpoint);
    endpoints.remove(normalized);
    _poller.syncKeys();
    await _persist();
    await facade.removeRelayServer(normalized);
  }

  Future<void> replace(List<String> next) async {
    endpoints
      ..clear()
      ..addAll(ServerRuntimeUtils.uniqueNormalized(next, normalizeEndpoint));
    _poller.syncKeys();
    await _persist();
    await facade.configureRelayServers(endpoints);
    unawaited(refreshAvailability());
  }

  Future<void> merge(List<String> incoming) async {
    ServerRuntimeUtils.mergeUnique(endpoints, incoming, normalizeEndpoint);
    _poller.syncKeys();
    await _persist();
    await facade.configureRelayServers(endpoints);
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
    await facade.configureRelayServers(endpoints);
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

  Future<void> refreshAvailabilityFor(List<String> selectedEndpoints) async {
    if (_disposed) {
      return;
    }
    await _poller.refreshAvailabilityFor(selectedEndpoints);
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
      List<String>.from(facade.relayServers),
      normalizeEndpoint,
    );
  }

  static String normalizeEndpoint(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return '';
    }

    final withAuthority = _relayUriCandidate(raw);
    final uri = Uri.tryParse(withAuthority);
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

    if (!_isSafeRelayHostStatic(host)) {
      return '';
    }

    final buffer = StringBuffer()..write('https://');
    if (host.contains(':') && !host.startsWith('[')) {
      buffer.write('[$host]');
    } else {
      buffer.write(host);
    }
    buffer.write(':${uri.hasPort ? uri.port : _defaultRelayPort}');
    return buffer.toString();
  }

  Future<void> _persist() async {
    await _settings.put(_storageKey, List<String>.from(endpoints));
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
    // Relay endpoints are user-configured/self-hosted and may commonly use
    // self-signed certificates during local or IP-based deployments.
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
      if (healthStatusCode != 200) {
        return ServerAvailability.unavailable(
          error: 'health status $healthStatusCode',
          checkedAt: DateTime.now(),
        );
      }

      final probeStatusCode = await ServerRuntimeUtils.requestStatusWithTimeout(
        client: client,
        uri: uri.resolve('/relay/probe'),
        method: 'POST',
        timeout: _probeTimeout,
        contentType: ContentType.json,
        bodyBytes: utf8.encode(
          jsonEncode(<String, String>{
            'v': '1',
            'client': 'peerlink-health-check',
          }),
        ),
      );
      if (probeStatusCode == null) {
        return ServerAvailability.unavailable(
          error: 'таймаут проверки ${_probeTimeout.inSeconds}с',
          checkedAt: DateTime.now(),
        );
      }
      if (probeStatusCode == 200) {
        return ServerAvailability.available(checkedAt: DateTime.now());
      }
      return ServerAvailability.unavailable(
        error: 'probe status $probeStatusCode',
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      return ServerAvailability.unavailable(
        error: ServerRuntimeUtils.shortError(error),
        checkedAt: DateTime.now(),
      );
    } finally {
      client.close(force: true);
    }
  }

  ServerAvailability _initialAvailabilityForEndpoint(String endpoint) {
    final normalized = normalizeEndpoint(endpoint);
    if (normalized.isEmpty) {
      return const ServerAvailability.unknown();
    }
    final uri = Uri.tryParse(normalized);
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

  static String _relayUriCandidate(String raw) {
    final lower = raw.toLowerCase();
    if (lower.startsWith('https://') || lower.startsWith('http://')) {
      return raw;
    }
    if (raw.contains('://')) {
      final hostPort = raw.substring(raw.indexOf('://') + 3);
      return '//$hostPort';
    }
    return '//$raw';
  }

  static bool _isSafeRelayHostStatic(String host) {
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
