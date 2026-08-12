enum CallRecoveryObservationKind {
  heartbeatMissed,
  mediaReadyTimeout,
  postIceRecoveryFlowStalled,
  liveMediaFlowStalled,
  remoteVideoFlowStalled,
  iceDisconnected,
  iceFailed,
  iceConnected,
  mediaAdvanced,
}

enum CallRecoveryDisposition { none, retryLater }

class CallRecoveryObservation {
  const CallRecoveryObservation({
    required this.kind,
    required this.reason,
    this.attempt = 0,
    this.localMediaReady,
    this.remoteMediaReady,
  });

  final CallRecoveryObservationKind kind;
  final String reason;
  final int attempt;
  final bool? localMediaReady;
  final bool? remoteMediaReady;
}

class CallRecoveryCoordinator {
  static const Duration mediaRecentWindow = Duration(seconds: 6);
  static const int mediaReadyFailAttempt = 5;

  CallRecoveryCoordinator({
    required void Function(String message) log,
    required void Function({required bool recovering, required String status})
    onRecoveryStateChanged,
    required void Function(String error) onFatal,
    DateTime Function()? now,
  }) : _log = log,
       _onRecoveryStateChanged = onRecoveryStateChanged,
       _onFatal = onFatal,
       _now = now ?? DateTime.now;

  final void Function(String message) _log;
  final void Function({required bool recovering, required String status})
  _onRecoveryStateChanged;
  final void Function(String error) _onFatal;
  final DateTime Function() _now;

  DateTime? _lastMediaAdvancedAt;
  DateTime? _iceUnhealthySince;

  bool get mediaRecentlyActive {
    final last = _lastMediaAdvancedAt;
    return last != null && _now().difference(last) <= mediaRecentWindow;
  }

  Future<CallRecoveryDisposition> observe(
    CallRecoveryObservation observation,
  ) async {
    switch (observation.kind) {
      case CallRecoveryObservationKind.mediaAdvanced:
        _markMediaAdvanced();
        return CallRecoveryDisposition.none;
      case CallRecoveryObservationKind.iceConnected:
        _clearIceUnhealthy('ice-connected');
        return CallRecoveryDisposition.none;
      case CallRecoveryObservationKind.mediaReadyTimeout:
        return _handleMediaReadyTimeout(observation);
      case CallRecoveryObservationKind.iceDisconnected:
      case CallRecoveryObservationKind.iceFailed:
        _markIceUnhealthy(observation);
        return CallRecoveryDisposition.none;
      case CallRecoveryObservationKind.heartbeatMissed:
      case CallRecoveryObservationKind.remoteVideoFlowStalled:
      case CallRecoveryObservationKind.postIceRecoveryFlowStalled:
      case CallRecoveryObservationKind.liveMediaFlowStalled:
        _logObservation(observation, action: 'diagnostic-only');
        return CallRecoveryDisposition.none;
    }
  }

  void reset() {
    _lastMediaAdvancedAt = null;
    _iceUnhealthySince = null;
  }

  void dispose() {
    reset();
  }

  CallRecoveryDisposition _handleMediaReadyTimeout(
    CallRecoveryObservation observation,
  ) {
    if (observation.attempt >= mediaReadyFailAttempt) {
      _logObservation(observation, action: 'fatal-no-media-ready');
      _onFatal('Не удалось восстановить двусторонний аудиоканал');
      return CallRecoveryDisposition.none;
    }
    _logObservation(observation, action: 'observe-and-retry');
    return CallRecoveryDisposition.retryLater;
  }

  void _markMediaAdvanced() {
    _lastMediaAdvancedAt = _now();
    _clearIceUnhealthy('media-advanced');
  }

  void _markIceUnhealthy(CallRecoveryObservation observation) {
    _iceUnhealthySince ??= _now();
    _onRecoveryStateChanged(
      recovering: true,
      status: observation.kind == CallRecoveryObservationKind.iceFailed
          ? 'Транспорт звонка прерван, ждём восстановления сети'
          : 'Транспорт звонка нестабилен, ждём восстановления сети',
    );
    _logObservation(observation, action: 'passive-watch');
  }

  void _clearIceUnhealthy(String reason) {
    if (_iceUnhealthySince == null) {
      return;
    }
    _iceUnhealthySince = null;
    _onRecoveryStateChanged(recovering: false, status: '');
    _log('recovery:cleared reason="$reason"');
  }

  void _logObservation(
    CallRecoveryObservation observation, {
    required String action,
  }) {
    _log(
      'recovery:observe kind=${observation.kind.name} '
      'reason="${observation.reason}" action=$action '
      'attempt=${observation.attempt} '
      'localReady=${observation.localMediaReady} '
      'remoteReady=${observation.remoteMediaReady}',
    );
  }
}
