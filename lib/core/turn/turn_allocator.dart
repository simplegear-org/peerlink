import 'dart:async';

import 'turn_server_config.dart';
import 'turn_node.dart';
import 'turn_credentials.dart';
import '../runtime/server_availability.dart';
import '../runtime/app_file_logger.dart';

class TurnAllocator {
  static const Duration _sharedHealthFreshness = Duration(seconds: 20);
  static const int _refreshShortlistSize = 3;
  final List<TurnNode> _nodes = [];
  ServerAvailability? Function(String url)? _availabilityLookup;
  Future<void> Function(List<String> urls)? _availabilityRefresh;

  TurnNode? _active;
  Timer? _healthTimer;

  bool _initialized = false;

  // Callbacks для обратной связи с TurnServersService
  void Function(String url)? _onSuccess;
  void Function(String url)? _onFailure;

  // ================================
  // PUBLIC API
  // ================================

  void setCallbacks({
    void Function(String url)? onSuccess,
    void Function(String url)? onFailure,
  }) {
    _onSuccess = onSuccess;
    _onFailure = onFailure;
  }

  void setAvailabilityLookup(
    ServerAvailability? Function(String url)? availabilityLookup,
  ) {
    _availabilityLookup = availabilityLookup;
    _recalculateActive();
  }

  void setAvailabilityRefresh(
    Future<void> Function(List<String> urls)? availabilityRefresh,
  ) {
    _availabilityRefresh = availabilityRefresh;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _startHealthMonitoring();

    _initialized = true;
  }

  void dispose() {
    _healthTimer?.cancel();
  }

  void registerServer({
    required String url,
    required String username,
    required String password,
    int priority = 100,
  }) {
    final existing = _findNode(url);
    if (existing != null) {
      _nodes.remove(existing);
    }

    _nodes.add(
      TurnNode(
        credentials: TurnCredentials(
          url: url,
          username: username,
          password: password,
        ),
        priority: priority,
      ),
    );

    _recalculateActive();
  }

  void configureServers(List<TurnServerConfig> servers) {
    _nodes
      ..clear()
      ..addAll(
        servers
            .where((server) => server.url.trim().isNotEmpty)
            .map(
              (server) => TurnNode(
                credentials: TurnCredentials(
                  url: server.url.trim(),
                  username: server.username,
                  password: server.password,
                ),
                priority: server.priority,
              ),
            ),
      );
    _log(
      'configure count=${_nodes.length} urls=${_nodes.map((n) => n.credentials.url).join(',')}',
    );
    _recalculateActive();
  }

  TurnCredentials? allocate() {
    if (_active == null) {
      _recalculateActive();
    }

    if (_active == null || _effectiveHealthy(_active!) != true) {
      _log('allocate active=null-or-unhealthy');
      return null;
    }

    _log('allocate active=${_active!.credentials.url}');
    return _active!.credentials;
  }

  List<TurnCredentials> allocateAll() {
    if (_active == null) {
      _recalculateActive();
    }
    if (_nodes.isEmpty) {
      _log('allocateAll empty');
      return const <TurnCredentials>[];
    }

    final ordered = List<TurnNode>.from(_nodes)
      ..sort(_compareNodes);
    final healthy = ordered
        .where((node) => _effectiveHealthy(node) == true)
        .toList(growable: false);
    final source = healthy.isNotEmpty ? healthy : ordered;
    _log(
      'allocateAll count=${source.length} urls=${source.map((n) => n.credentials.url).join(',')}',
    );
    return source
        .map((node) => node.credentials)
        .toList(growable: false);
  }

  Future<void> refreshSelectionIfNeeded({
    int limit = _refreshShortlistSize,
  }) async {
    final refresh = _availabilityRefresh;
    if (refresh == null || _nodes.isEmpty) {
      return;
    }
    final shortlist = List<TurnNode>.from(_nodes)
      ..sort(_compareNodes);
    final selected = shortlist.take(limit).toList(growable: false);
    if (selected.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final stale = selected.any((node) {
      final availability = _availabilityLookup?.call(node.credentials.url);
      final checkedAt = availability?.checkedAt;
      if (checkedAt == null) {
        return true;
      }
      return now.difference(checkedAt) > _sharedHealthFreshness;
    });
    if (!stale) {
      return;
    }
    try {
      await refresh(
        selected.map((node) => node.credentials.url).toList(growable: false),
      );
      _recalculateActive();
    } catch (error) {
      _log('shortlist refresh failed error=$error');
    }
  }

  void reportSuccess(String url) {
    final node = _findNode(url);
    node?.markHealthy();
    _onSuccess?.call(url);
    _recalculateActive();
  }

  void reportFailure(String url) {
    final node = _findNode(url);
    node?.markUnhealthy();
    _onFailure?.call(url);
    _recalculateActive();
  }

  List<TurnNode> get nodes => List.unmodifiable(_nodes);

  bool? isHealthy(String url) {
    final node = _findNode(url);
    if (node == null) {
      return null;
    }
    return _effectiveHealthy(node);
  }

  List<TurnServerConfig> get serverConfigs => _nodes
      .map(
        (node) => TurnServerConfig(
          url: node.credentials.url,
          username: node.credentials.username,
          password: node.credentials.password,
          priority: node.priority,
        ),
      )
      .toList(growable: false);

  // ================================
  // INTERNAL LOGIC
  // ================================

  void _recalculateActive() {
    if (_nodes.isEmpty) {
      _active = null;
      return;
    }

    _nodes.sort(_compareNodes);

    final healthy = _nodes.where((n) => _effectiveHealthy(n) == true).toList();

    if (healthy.isNotEmpty) {
      _active = healthy.first;
    } else {
      _active = _nodes.first;
    }
  }

  void _startHealthMonitoring() {
    _healthTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _healthCheck(),
    );
  }

  void _healthCheck() {
    // Until a real TURN health probe exists, keep allocator state deterministic.
    // Health is updated via reportSuccess/reportFailure from real connection flow.
    _recalculateActive();
  }

  TurnNode? _findNode(String url) {
    try {
      return _nodes.firstWhere(
        (n) => n.credentials.url == url,
      );
    } catch (_) {
      return null;
    }
  }

  void _log(String message) {
    AppFileLogger.log('[turn_allocator] $message');
  }

  bool? _effectiveHealthy(TurnNode node) {
    final shared = _availabilityLookup?.call(node.credentials.url);
    if (shared?.isAvailable != null) {
      return shared!.isAvailable;
    }
    return node.isHealthy;
  }

  int _compareNodes(TurnNode a, TurnNode b) {
    final aRank = _sortRank(a);
    final bRank = _sortRank(b);
    if (aRank != bRank) {
      return aRank.compareTo(bRank);
    }
    return b.score.compareTo(a.score);
  }

  int _sortRank(TurnNode node) {
    final shared = _availabilityLookup?.call(node.credentials.url);
    final available = shared?.isAvailable;
    if (available == true) {
      return 0;
    }
    if (available == false) {
      return 2;
    }
    return node.isHealthy ? 0 : 1;
  }
}
