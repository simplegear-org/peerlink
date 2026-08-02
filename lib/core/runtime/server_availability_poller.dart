import 'dart:async';
import 'dart:math';

import 'server_availability.dart';

typedef ServerAvailabilityProbe =
    Future<ServerAvailability> Function(String serverKey);

typedef ServerAvailabilitySeed = ServerAvailability Function(String serverKey);
typedef ServerAvailabilityLogger = void Function(String message);

class ServerAvailabilityPoller {
  final String providerKey;
  final List<String> Function() _serverKeysProvider;
  final ServerAvailabilityProbe _probe;
  final ServerAvailabilitySeed _seedAvailability;
  final Duration _healthyProbeInterval;
  final Duration _initialRetryDelay;
  final Duration _maxRetryDelay;
  final ServerAvailabilityLogger? _logger;

  final Map<String, ServerAvailability> _availabilityByKey =
      <String, ServerAvailability>{};
  final Map<String, int> _failureCountByKey = <String, int>{};
  final Map<String, DateTime> _nextProbeAtByKey = <String, DateTime>{};
  final StreamController<Map<String, ServerAvailability>> _controller =
      StreamController<Map<String, ServerAvailability>>.broadcast();

  Timer? _probeTimer;
  Future<void>? _refreshFuture;
  bool _disposed = false;

  ServerAvailabilityPoller({
    required this.providerKey,
    required List<String> Function() serverKeysProvider,
    required ServerAvailabilityProbe probe,
    required ServerAvailabilitySeed seedAvailability,
    required Duration healthyProbeInterval,
    Duration? initialRetryDelay,
    Duration? maxRetryDelay,
    ServerAvailabilityLogger? logger,
  }) : _serverKeysProvider = serverKeysProvider,
       _probe = probe,
       _seedAvailability = seedAvailability,
       _healthyProbeInterval = healthyProbeInterval,
       _initialRetryDelay = initialRetryDelay ?? healthyProbeInterval,
       _maxRetryDelay =
           maxRetryDelay ??
           Duration(seconds: max(healthyProbeInterval.inSeconds * 8, 30)),
       _logger = logger;

  Stream<Map<String, ServerAvailability>> get availabilityStream =>
      _controller.stream;

  Map<String, ServerAvailability> get availabilitySnapshot =>
      Map<String, ServerAvailability>.unmodifiable(_availabilityByKey);

  ServerAvailability availabilityFor(String serverKey) =>
      _availabilityByKey[serverKey] ?? const ServerAvailability.unknown();

  void overrideAvailability(String serverKey, ServerAvailability availability) {
    if (_disposed) {
      return;
    }
    _availabilityByKey[serverKey] = availability;
    _markNextProbe(serverKey, availability, DateTime.now());
    _emit();
    _scheduleNextProbe();
  }

  void syncKeys() {
    final activeKeys = _serverKeysProvider()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    _availabilityByKey.removeWhere((key, _) => !activeKeys.contains(key));
    _failureCountByKey.removeWhere((key, _) => !activeKeys.contains(key));
    _nextProbeAtByKey.removeWhere((key, _) => !activeKeys.contains(key));
    for (final key in activeKeys) {
      _availabilityByKey.putIfAbsent(key, () => _seedAvailability(key));
      _nextProbeAtByKey.putIfAbsent(key, DateTime.now);
    }
    _emit();
    _scheduleNextProbe();
  }

  void start() {
    syncKeys();
    _scheduleNextProbe();
  }

  Future<void> refreshAvailability() {
    return _refresh(force: true);
  }

  Future<void> refreshAvailabilityFor(List<String> selectedKeys) {
    return _refresh(force: false, onlyKeys: selectedKeys);
  }

  Future<void> runScheduledRefresh() {
    return _refresh(force: false);
  }

  void dispose() {
    _disposed = true;
    _probeTimer?.cancel();
    _controller.close();
  }

  Future<void> _refresh({required bool force, List<String>? onlyKeys}) {
    final inFlight = _refreshFuture;
    if (inFlight != null) {
      return inFlight;
    }
    final future = _refreshImpl(force: force, onlyKeys: onlyKeys);
    _refreshFuture = future;
    return future.whenComplete(() {
      if (identical(_refreshFuture, future)) {
        _refreshFuture = null;
      }
    });
  }

  Future<void> _refreshImpl({
    required bool force,
    List<String>? onlyKeys,
  }) async {
    if (_disposed) {
      return;
    }

    syncKeys();
    final allKeys = _serverKeysProvider()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (allKeys.isEmpty) {
      _availabilityByKey.clear();
      _emit();
      _scheduleNextProbe();
      return;
    }

    final selected = onlyKeys == null
        ? allKeys
        : onlyKeys
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty && allKeys.contains(item))
              .toList(growable: false);
    if (selected.isEmpty) {
      _scheduleNextProbe();
      return;
    }

    final now = DateTime.now();
    final dueKeys = <String>[];
    for (final key in selected) {
      if (force || _isProbeDue(key, now)) {
        dueKeys.add(key);
      }
    }
    if (dueKeys.isEmpty) {
      _scheduleNextProbe();
      return;
    }

    final results = await Future.wait(
      dueKeys.map((key) async => MapEntry(key, await _probeSafely(key))),
    );
    if (_disposed) {
      return;
    }

    var changed = false;
    for (final result in results) {
      final key = result.key;
      final availability = result.value;
      final previous = _availabilityByKey[key];
      _availabilityByKey[key] = availability;
      _markNextProbe(key, availability, now);
      if (!_sameAvailability(previous, availability)) {
        changed = true;
      }
    }

    if (changed) {
      _emit();
    }
    _scheduleNextProbe();
  }

  Future<ServerAvailability> _probeSafely(String key) async {
    try {
      return await _probe(key);
    } catch (error) {
      _log('probe failed provider=$providerKey key=$key error=$error');
      return ServerAvailability.unavailable(
        error: error.toString(),
        checkedAt: DateTime.now(),
      );
    }
  }

  bool _isProbeDue(String key, DateTime now) {
    final nextProbeAt = _nextProbeAtByKey[key];
    if (nextProbeAt == null) {
      return true;
    }
    return !nextProbeAt.isAfter(now);
  }

  void _markNextProbe(
    String key,
    ServerAvailability availability,
    DateTime now,
  ) {
    if (availability.isAvailable == true) {
      _failureCountByKey[key] = 0;
      _nextProbeAtByKey[key] = now.add(_healthyProbeInterval);
      return;
    }
    final nextFailureCount = (_failureCountByKey[key] ?? 0) + 1;
    _failureCountByKey[key] = nextFailureCount;
    final retryDelay = _retryDelayFor(nextFailureCount);
    _nextProbeAtByKey[key] = now.add(retryDelay);
  }

  Duration _retryDelayFor(int failureCount) {
    if (failureCount <= 1) {
      return _initialRetryDelay;
    }
    final multiplier = 1 << (failureCount - 1);
    final computedMs = _initialRetryDelay.inMilliseconds * multiplier;
    final cappedMs = min(computedMs, _maxRetryDelay.inMilliseconds);
    return Duration(milliseconds: cappedMs);
  }

  void _scheduleNextProbe() {
    _probeTimer?.cancel();
    if (_disposed) {
      return;
    }
    final keys = _serverKeysProvider()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (keys.isEmpty) {
      return;
    }

    final now = DateTime.now();
    DateTime? earliest;
    for (final key in keys) {
      final next = _nextProbeAtByKey[key] ?? now;
      if (earliest == null || next.isBefore(earliest)) {
        earliest = next;
      }
    }
    if (earliest == null) {
      return;
    }
    final delay = earliest.isAfter(now)
        ? earliest.difference(now)
        : Duration.zero;
    _probeTimer = Timer(delay, () {
      unawaited(runScheduledRefresh());
    });
  }

  bool _sameAvailability(ServerAvailability? left, ServerAvailability? right) {
    if (identical(left, right)) {
      return true;
    }
    return left?.isAvailable == right?.isAvailable &&
        left?.error == right?.error &&
        left?.checkedAt == right?.checkedAt;
  }

  void _emit() {
    if (_disposed || _controller.isClosed) {
      return;
    }
    _controller.add(Map<String, ServerAvailability>.from(_availabilityByKey));
  }

  void _log(String message) {
    _logger?.call(message);
  }
}
