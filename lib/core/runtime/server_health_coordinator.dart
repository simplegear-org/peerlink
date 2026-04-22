import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../node/node_facade.dart';
import '../turn/turn_server_config.dart';
import 'app_file_logger.dart';
import 'bootstrap_servers_service.dart';
import 'relay_servers_service.dart';
import 'server_availability.dart';
import 'storage_service.dart';
import 'turn_servers_service.dart';

/// Shared runtime coordinator for server-health providers.
///
/// It owns a single set of bootstrap/relay/turn availability services and
/// exposes them to both runtime bootstrap and UI, so the app does not create
/// duplicate probe loops for the same configured server lists.
class ServerHealthCoordinator with WidgetsBindingObserver {
  static ServerHealthCoordinator? _instance;

  final NodeFacade facade;
  final StorageService storage;

  late final BootstrapServersService bootstrap;
  late final RelayServersService relay;
  late final TurnServersService turn;

  Future<void>? _initializeFuture;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<ConnectivityResult> _lastConnectivity = const <ConnectivityResult>[];
  Future<void>? _refreshFuture;
  bool _disposed = false;

  factory ServerHealthCoordinator({
    required NodeFacade facade,
    required StorageService storage,
  }) {
    final existing = _instance;
    if (existing != null) {
      return existing;
    }
    final created = ServerHealthCoordinator._(
      facade: facade,
      storage: storage,
    );
    _instance = created;
    return created;
  }

  ServerHealthCoordinator._({
    required this.facade,
    required this.storage,
  }) {
    bootstrap = BootstrapServersService(
      facade: facade,
      storage: storage,
    );
    relay = RelayServersService(
      facade: facade,
      storage: storage,
    );
    turn = TurnServersService(
      facade: facade,
      storage: storage,
    );
  }

  Future<void> initialize() {
    final inFlight = _initializeFuture;
    if (inFlight != null) {
      return inFlight;
    }
    _initializeFuture = _initializeImpl();
    return _initializeFuture!;
  }

  Future<void> _initializeImpl() async {
    await bootstrap.initialize();
    await relay.initialize();
    await turn.initialize();
    WidgetsBinding.instance.addObserver(this);
    await _startConnectivityWatch();
  }

  Future<void> refreshAll() async {
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      return inFlight;
    }
    _refreshFuture = _refreshAllImpl();
    try {
      await _refreshFuture;
    } finally {
      _refreshFuture = null;
    }
  }

  Future<void> refreshRelayEndpoints(List<String> endpoints) async {
    if (_disposed) {
      return;
    }
    await relay.refreshAvailabilityFor(endpoints);
  }

  Future<void> refreshTurnUrls(List<String> urls) async {
    if (_disposed) {
      return;
    }
    await turn.refreshAvailabilityFor(urls);
  }

  List<String> get bootstrapEndpoints => bootstrap.endpoints;
  List<String> get relayEndpoints => relay.endpoints;
  List<TurnServerConfig> get turnServers => turn.servers;

  Stream<Map<String, ServerAvailability>> get bootstrapAvailabilityStream =>
      bootstrap.availabilityStream;
  Stream<Map<String, ServerAvailability>> get relayAvailabilityStream =>
      relay.availabilityStream;
  Stream<Map<String, ServerAvailability>> get turnAvailabilityStream =>
      turn.availabilityStream;
  Map<String, ServerAvailability> get bootstrapAvailabilitySnapshot =>
      bootstrap.availabilitySnapshot;
  Map<String, ServerAvailability> get relayAvailabilitySnapshot =>
      relay.availabilitySnapshot;
  Map<String, ServerAvailability> get turnAvailabilitySnapshot =>
      turn.availabilitySnapshot;

  ServerAvailability bootstrapAvailabilityFor(String endpoint) =>
      bootstrap.availabilityFor(endpoint);
  ServerAvailability relayAvailabilityFor(String endpoint) =>
      relay.availabilityFor(endpoint);
  ServerAvailability turnAvailabilityFor(String url) =>
      turn.availabilityFor(url);

  Future<void> _refreshAllImpl() async {
    if (_disposed) {
      return;
    }
    await bootstrap.refreshAvailability();
    await relay.refreshAvailability();
    await turn.refreshAvailability();
  }

  Future<void> _startConnectivityWatch() async {
    try {
      _lastConnectivity = await _connectivity.checkConnectivity();
    } catch (_) {
      _lastConnectivity = const <ConnectivityResult>[];
    }
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (_sameConnectivity(_lastConnectivity, results)) {
        return;
      }
      final previous = List<ConnectivityResult>.from(_lastConnectivity);
      _lastConnectivity = List<ConnectivityResult>.from(results);
      _log(
        'connectivity changed from=$previous to=$results refresh=true',
      );
      unawaited(refreshAll());
    });
  }

  bool _sameConnectivity(
    List<ConnectivityResult> a,
    List<ConnectivityResult> b,
  ) {
    if (a.length != b.length) {
      return false;
    }
    final aSorted = List<ConnectivityResult>.from(a)
      ..sort((left, right) => left.index.compareTo(right.index));
    final bSorted = List<ConnectivityResult>.from(b)
      ..sort((left, right) => left.index.compareTo(right.index));
    for (var i = 0; i < aSorted.length; i++) {
      if (aSorted[i] != bSorted[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _log('app resumed refresh=true');
      unawaited(refreshAll());
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    await _connectivitySubscription?.cancel();
    bootstrap.dispose();
    relay.dispose();
    turn.dispose();
  }

  void _log(String message) {
    AppFileLogger.log('[server_health] $message');
  }
}
