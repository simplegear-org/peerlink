import 'dart:async';

import 'bootstrap_signaling_runtime_state.dart';

class BootstrapSignalingReconnectController {
  final BootstrapSignalingRuntimeState state;
  final Duration minReconnectDelay;
  final Duration maxReconnectDelay;
  final int connectFailureCircuitBreakerThreshold;
  final Duration connectFailureCooldown;
  final Future<void> Function(String endpoint) reconnect;
  final void Function(String message) log;

  Timer? _reconnectTimer;
  Stopwatch? _reconnectStopwatch;
  int _consecutiveConnectFailures = 0;
  DateTime? _cooldownUntil;

  BootstrapSignalingReconnectController({
    required this.state,
    required this.minReconnectDelay,
    required this.maxReconnectDelay,
    required this.connectFailureCircuitBreakerThreshold,
    required this.connectFailureCooldown,
    required this.reconnect,
    required this.log,
  });

  void scheduleReconnect(String reason) {
    if (state.manualCloseRequested) {
      log('reconnect:skip manual close reason=$reason');
      return;
    }
    final endpoint = state.serverEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      log('reconnect:skip no endpoint reason=$reason');
      return;
    }
    if (state.channel != null) {
      log('reconnect:skip channel active reason=$reason');
      return;
    }
    if (_reconnectTimer != null) {
      log('reconnect:already scheduled reason=$reason');
      return;
    }

    final now = DateTime.now();
    final cooldownUntil = _cooldownUntil;
    if (cooldownUntil != null && cooldownUntil.isAfter(now)) {
      final delay = cooldownUntil.difference(now);
      log(
        'reconnect:circuit-open until=${cooldownUntil.toIso8601String()} '
        'delayMs=${delay.inMilliseconds} reason=$reason',
      );
      _reconnectTimer = Timer(delay, () {
        _reconnectTimer = null;
        log('reconnect:circuit-half-open endpoint=$endpoint');
        scheduleReconnect(reason);
      });
      return;
    }

    final delay = _nextReconnectDelay(reason);
    state.reconnectAttempt += 1;
    final scheduledAttempt = state.reconnectAttempt;
    final scheduledEndpoint = endpoint;
    log(
      'reconnect:scheduled attempt=$scheduledAttempt delayMs=${delay.inMilliseconds} reason=$reason',
    );
    markReconnectPhase(
      'reconnect:scheduled attempt=$scheduledAttempt delayMs=${delay.inMilliseconds} reason=$reason',
    );
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (state.manualCloseRequested) {
        return;
      }
      final currentEndpoint = state.serverEndpoint;
      if (currentEndpoint == null || currentEndpoint.isEmpty) {
        return;
      }
      if (currentEndpoint != scheduledEndpoint) {
        log(
          'reconnect:skip stale timer attempt=$scheduledAttempt '
          'scheduledEndpoint=$scheduledEndpoint currentEndpoint=$currentEndpoint',
        );
        return;
      }
      log(
        'reconnect:start attempt=$scheduledAttempt endpoint=$currentEndpoint',
      );
      markReconnectPhase(
        'reconnect:start attempt=$scheduledAttempt endpoint=$currentEndpoint',
      );
      await reconnect(currentEndpoint);
    });
  }

  void recordConnectFailure() {
    _consecutiveConnectFailures += 1;
    if (_consecutiveConnectFailures < connectFailureCircuitBreakerThreshold) {
      log(
        'reconnect:circuit failureCount=$_consecutiveConnectFailures '
        'threshold=$connectFailureCircuitBreakerThreshold',
      );
      return;
    }
    final until = DateTime.now().add(connectFailureCooldown);
    _cooldownUntil = until;
    log(
      'reconnect:circuit-open failureCount=$_consecutiveConnectFailures '
      'cooldownUntil=${until.toIso8601String()}',
    );
  }

  void resetConnectFailureCircuit() {
    final hadFailures =
        _consecutiveConnectFailures > 0 || _cooldownUntil != null;
    _consecutiveConnectFailures = 0;
    _cooldownUntil = null;
    if (hadFailures) {
      log('reconnect:circuit-reset');
    }
  }

  void stopReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void startReconnectStopwatch(String reason) {
    _reconnectStopwatch
      ?..stop()
      ..reset();
    _reconnectStopwatch = Stopwatch()..start();
    log('reconnect:trace start reason=$reason');
  }

  void stopReconnectStopwatch(String reason) {
    final stopwatch = _reconnectStopwatch;
    if (stopwatch == null) {
      return;
    }
    log(
      'reconnect:trace stop reason=$reason elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    stopwatch.stop();
    _reconnectStopwatch = null;
  }

  void markReconnectPhase(String message) {
    final stopwatch = _reconnectStopwatch;
    if (stopwatch == null) {
      return;
    }
    log(
      'reconnect:trace phase=$message elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
  }

  Duration _nextReconnectDelay(String reason) {
    if (reason == 'register_ack timeout' ||
        reason == 'already registered' ||
        reason == 'network changed') {
      return const Duration(milliseconds: 250);
    }
    final seconds = 1 << state.reconnectAttempt.clamp(0, 4);
    final clampedSeconds = seconds.clamp(
      minReconnectDelay.inSeconds,
      maxReconnectDelay.inSeconds,
    );
    return Duration(seconds: clampedSeconds);
  }
}
