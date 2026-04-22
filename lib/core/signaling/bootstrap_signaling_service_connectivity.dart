part of 'bootstrap_signaling_service.dart';

extension _BootstrapSignalingServiceConnectivity on BootstrapSignalingService {
  Future<void> _initializeConnectivityWatch() async {
    try {
      _lastConnectivity = await _connectivity.checkConnectivity();
    } catch (_) {
      _lastConnectivity = const <ConnectivityResult>[];
    }

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      if (_sameConnectivity(_lastConnectivity, results)) {
        return;
      }
      final previous = List<ConnectivityResult>.from(_lastConnectivity);
      _lastConnectivity = List<ConnectivityResult>.from(results);
      _log('network:changed from=$previous to=$results');
      _scheduleFastReconnectForNetworkChange(results);
    });
  }

  bool _sameConnectivity(
    List<ConnectivityResult> a,
    List<ConnectivityResult> b,
  ) {
    final normalizedA = a.toSet().toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    final normalizedB = b.toSet().toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    if (normalizedA.length != normalizedB.length) {
      return false;
    }
    for (var i = 0; i < normalizedA.length; i++) {
      if (normalizedA[i] != normalizedB[i]) {
        return false;
      }
    }
    return true;
  }

  void _scheduleFastReconnectForNetworkChange(
    List<ConnectivityResult> results,
  ) {
    if (_manualCloseRequested) {
      return;
    }
    if (_serverEndpoint == null || _serverEndpoint!.isEmpty) {
      return;
    }
    if (results.isEmpty ||
        (results.length == 1 && results.first == ConnectivityResult.none)) {
      _log('network:changed no network, tearing down active channel');
      unawaited(_handleNetworkBecameUnavailable());
      return;
    }

    _networkChangeTimer?.cancel();
    _networkChangeTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_fastReconnectAfterNetworkChange());
    });
  }

  Future<void> _handleNetworkBecameUnavailable() async {
    _startReconnectStopwatch('network unavailable');
    _networkChangeTimer?.cancel();
    _networkChangeTimer = null;
    _registrationTimeout?.cancel();
    _registrationTimeout = null;
    _stopHeartbeat();
    _stopReconnectTimer();
    _reconnectAttempt = 0;
    _markReconnectPhase('teardown:start no-network');
    await _teardownActiveChannel();
    _markReconnectPhase('teardown:done no-network');
    _setError('network unavailable');
    _setStatus(SignalingConnectionStatus.disconnected);
  }

  Future<void> _fastReconnectAfterNetworkChange() async {
    if (_manualCloseRequested) {
      return;
    }
    final endpoint = _serverEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      return;
    }
    _startReconnectStopwatch('network changed');
    _log('network:fast reconnect endpoint=$endpoint');
    _reconnectAttempt = 0;
    _registrationTimeout?.cancel();
    _registrationTimeout = null;
    _stopHeartbeat();
    _stopReconnectTimer();
    _markReconnectPhase('teardown:start fast-reconnect');
    await _teardownActiveChannel();
    _markReconnectPhase('teardown:done fast-reconnect');
    _setError('network changed');
    _setStatus(SignalingConnectionStatus.connecting);
    _markReconnectPhase('setServer:start fast-reconnect');
    await setServer(endpoint);
  }

  Uri _parseEndpointUri(String endpoint) {
    final withScheme = endpoint.contains('://') ? endpoint : 'ws://$endpoint';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      throw FormatException('Invalid bootstrap endpoint: $endpoint');
    }

    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw FormatException(
        'Bootstrap endpoint must use ws:// or wss://: $endpoint',
      );
    }

    return uri;
  }

  void _scheduleReconnect(String reason) {
    if (_manualCloseRequested) {
      _log('reconnect:skip manual close reason=$reason');
      return;
    }
    final endpoint = _serverEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      _log('reconnect:skip no endpoint reason=$reason');
      return;
    }
    if (_channel != null) {
      _log('reconnect:skip channel active reason=$reason');
      return;
    }
    if (_reconnectTimer != null) {
      _log('reconnect:already scheduled reason=$reason');
      return;
    }

    final now = DateTime.now();
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      final delay = cooldownUntil.difference(now);
      _log(
        'reconnect:circuit-open until=${cooldownUntil.toIso8601String()} '
        'delayMs=${delay.inMilliseconds} reason=$reason',
      );
      _reconnectTimer = Timer(delay, () {
        _reconnectTimer = null;
        _log('reconnect:circuit-half-open endpoint=$endpoint');
        _scheduleReconnect(reason);
      });
      return;
    }

    final delay = _nextReconnectDelay(reason);
    _reconnectAttempt += 1;
    final scheduledAttempt = _reconnectAttempt;
    final scheduledEndpoint = endpoint;
    _log(
      'reconnect:scheduled attempt=$scheduledAttempt delayMs=${delay.inMilliseconds} reason=$reason',
    );
    _markReconnectPhase(
      'reconnect:scheduled attempt=$scheduledAttempt delayMs=${delay.inMilliseconds} reason=$reason',
    );
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_manualCloseRequested) {
        return;
      }
      final currentEndpoint = _serverEndpoint;
      if (currentEndpoint == null || currentEndpoint.isEmpty) {
        return;
      }
      if (currentEndpoint != scheduledEndpoint) {
        _log(
          'reconnect:skip stale timer attempt=$scheduledAttempt '
          'scheduledEndpoint=$scheduledEndpoint currentEndpoint=$currentEndpoint',
        );
        return;
      }
      _log('reconnect:start attempt=$scheduledAttempt endpoint=$currentEndpoint');
      _markReconnectPhase(
        'reconnect:start attempt=$scheduledAttempt endpoint=$currentEndpoint',
      );
      await setServer(currentEndpoint);
    });
  }

  void _recordConnectFailure() {
    _consecutiveConnectFailures += 1;
    if (_consecutiveConnectFailures <
        BootstrapSignalingService._connectFailureCircuitBreakerThreshold) {
      _log(
        'reconnect:circuit failureCount=$_consecutiveConnectFailures '
        'threshold=${BootstrapSignalingService._connectFailureCircuitBreakerThreshold}',
      );
      return;
    }
    final until = DateTime.now().add(
      BootstrapSignalingService._connectFailureCooldown,
    );
    _cooldownUntil = until;
    _log(
      'reconnect:circuit-open failureCount=$_consecutiveConnectFailures '
      'cooldownUntil=${until.toIso8601String()}',
    );
  }

  void _resetConnectFailureCircuit() {
    final hadFailures = _consecutiveConnectFailures > 0 || _cooldownUntil != null;
    _consecutiveConnectFailures = 0;
    _cooldownUntil = null;
    if (hadFailures) {
      _log('reconnect:circuit-reset');
    }
  }

  Duration _nextReconnectDelay(String reason) {
    if (reason == 'register_ack timeout' ||
        reason == 'already registered' ||
        reason == 'network changed') {
      return const Duration(milliseconds: 250);
    }
    final seconds = 1 << _reconnectAttempt.clamp(0, 4);
    final clampedSeconds = seconds.clamp(
      BootstrapSignalingService._minReconnectDelay.inSeconds,
      BootstrapSignalingService._maxReconnectDelay.inSeconds,
    );
    return Duration(seconds: clampedSeconds);
  }

  void _stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _startReconnectStopwatch(String reason) {
    _reconnectStopwatch
      ?..stop()
      ..reset();
    _reconnectStopwatch = Stopwatch()..start();
    _log('reconnect:trace start reason=$reason');
  }

  void _stopReconnectStopwatch(String reason) {
    final stopwatch = _reconnectStopwatch;
    if (stopwatch == null) {
      return;
    }
    _log(
      'reconnect:trace stop reason=$reason elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    stopwatch.stop();
    _reconnectStopwatch = null;
  }

  void _markReconnectPhase(String phase) {
    final elapsedMs = _reconnectStopwatch?.elapsedMilliseconds;
    if (elapsedMs == null) {
      return;
    }
    _log('reconnect:trace phase=$phase elapsedMs=$elapsedMs');
  }
}
