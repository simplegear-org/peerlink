import 'dart:async';

typedef CallHeartbeatSignalSender =
    Future<void> Function(
      String peerId,
      String type,
      Map<String, dynamic> data,
    );

class CallHeartbeatController {
  static const Duration heartbeatInterval = Duration(seconds: 1);
  static const int missedWarningThreshold = 3;
  static const int missedRecoveryThreshold = 12;
  static const int missedThreshold = missedWarningThreshold;
  static const Duration missedRecoveryCooldown = Duration(seconds: 18);
  static const Duration logThrottle = Duration(seconds: 12);

  CallHeartbeatController({
    required CallHeartbeatSignalSender sendSignal,
    required bool Function() isSignalingConnected,
    required Future<void> Function(String reason) onHeartbeatMissed,
    required void Function(String message) log,
    bool Function()? isMediaRecentlyActive,
    Duration interval = heartbeatInterval,
    DateTime Function()? now,
  }) : _sendSignal = sendSignal,
       _isSignalingConnected = isSignalingConnected,
       _onHeartbeatMissed = onHeartbeatMissed,
       _log = log,
       _isMediaRecentlyActive = isMediaRecentlyActive,
       _interval = interval,
       _now = now ?? DateTime.now;

  final CallHeartbeatSignalSender _sendSignal;
  final bool Function() _isSignalingConnected;
  final Future<void> Function(String reason) _onHeartbeatMissed;
  final void Function(String message) _log;
  final bool Function()? _isMediaRecentlyActive;
  final Duration _interval;
  final DateTime Function() _now;

  Timer? _timer;
  String? _peerId;
  String? _callId;
  int _seq = 0;
  bool _remoteSupported = false;
  bool _recoveryTriggeredForCurrentMiss = false;
  DateTime? _lastRemoteHeartbeatAt;
  DateTime? _lastMissedRecoveryAt;
  DateTime? _lastMissedLogAt;
  DateTime? _lastMediaActiveRecoverySkipLogAt;
  DateTime? _lastSendSkipLogAt;

  bool get isActive => _timer?.isActive ?? false;
  bool get remoteSupported => _remoteSupported;

  void start({required String peerId, required String callId}) {
    if (isActive && _peerId == peerId && _callId == callId) {
      return;
    }
    stop();
    _peerId = peerId;
    _callId = callId;
    _seq = 0;
    _remoteSupported = false;
    _recoveryTriggeredForCurrentMiss = false;
    _lastRemoteHeartbeatAt = null;
    _lastMissedRecoveryAt = null;
    _lastMissedLogAt = null;
    _lastMediaActiveRecoverySkipLogAt = null;
    _lastSendSkipLogAt = null;
    _log(
      'callHeartbeat:start peerId=$peerId callId=$callId '
      'intervalMs=${_interval.inMilliseconds}',
    );
    unawaited(_sendHeartbeat());
    _timer = Timer.periodic(_interval, (_) {
      unawaited(_sendHeartbeat());
      unawaited(_checkRemoteHeartbeat());
    });
  }

  void stop() {
    if (_timer?.isActive ?? false) {
      _log('callHeartbeat:stop peerId=$_peerId callId=$_callId');
    }
    _timer?.cancel();
    _timer = null;
    _peerId = null;
    _callId = null;
    _seq = 0;
    _remoteSupported = false;
    _recoveryTriggeredForCurrentMiss = false;
    _lastRemoteHeartbeatAt = null;
    _lastMissedRecoveryAt = null;
    _lastMissedLogAt = null;
    _lastMediaActiveRecoverySkipLogAt = null;
    _lastSendSkipLogAt = null;
  }

  void markRemoteHeartbeat({
    required String peerId,
    required String callId,
    required int seq,
    required int sentAtMs,
  }) {
    if (_peerId != peerId || _callId != callId) {
      _log(
        'callHeartbeat:ignored peerId=$peerId callId=$callId '
        'currentPeerId=$_peerId currentCallId=$_callId',
      );
      return;
    }
    final now = _now();
    final wasRecovering = _recoveryTriggeredForCurrentMiss;
    _remoteSupported = true;
    _recoveryTriggeredForCurrentMiss = false;
    _lastRemoteHeartbeatAt = now;
    final ageMs = sentAtMs > 0 ? now.millisecondsSinceEpoch - sentAtMs : -1;
    if (wasRecovering) {
      _log('callHeartbeat:remote recovered seq=$seq ageMs=$ageMs');
    }
  }

  Future<void> _sendHeartbeat() async {
    final peerId = _peerId;
    final callId = _callId;
    if (peerId == null || callId == null) {
      return;
    }
    if (!_isSignalingConnected()) {
      _logSendSkip('signaling-not-connected');
      return;
    }
    _seq += 1;
    final sentAtMs = _now().millisecondsSinceEpoch;
    try {
      await _sendSignal(peerId, 'call_heartbeat', {
        'callId': callId,
        'signalScope': 'call',
        'seq': _seq,
        'sentAtMs': sentAtMs,
      });
    } catch (error) {
      _logSendSkip('send-error:$error');
    }
  }

  void _logSendSkip(String reason) {
    final now = _now();
    final lastLogAt = _lastSendSkipLogAt;
    if (lastLogAt != null && now.difference(lastLogAt) < logThrottle) {
      return;
    }
    _lastSendSkipLogAt = now;
    _log('callHeartbeat:send skipped reason=$reason');
  }

  Future<void> _checkRemoteHeartbeat() async {
    if (!_remoteSupported) {
      return;
    }
    final lastRemoteAt = _lastRemoteHeartbeatAt;
    if (lastRemoteAt == null) {
      return;
    }
    final now = _now();
    final missedFor = now.difference(lastRemoteAt);
    final warningLimit = _interval * missedWarningThreshold;
    if (missedFor < warningLimit) {
      return;
    }
    _logMissedHeartbeat(missedFor);
    final recoveryLimit = _interval * missedRecoveryThreshold;
    if (missedFor < recoveryLimit) {
      return;
    }
    if (_recoveryTriggeredForCurrentMiss) {
      return;
    }
    final lastRecoveryAt = _lastMissedRecoveryAt;
    if (lastRecoveryAt != null &&
        now.difference(lastRecoveryAt) < missedRecoveryCooldown) {
      return;
    }
    if (_isMediaRecentlyActive?.call() ?? false) {
      _logMediaActiveRecoverySkip(missedFor);
      return;
    }
    _recoveryTriggeredForCurrentMiss = true;
    _lastMissedRecoveryAt = now;
    await _onHeartbeatMissed(
      'Call heartbeat missed for ${missedFor.inMilliseconds}ms',
    );
  }

  void _logMissedHeartbeat(Duration missedFor) {
    final now = _now();
    final lastLogAt = _lastMissedLogAt;
    if (lastLogAt != null && now.difference(lastLogAt) < logThrottle) {
      return;
    }
    _lastMissedLogAt = now;
    _log(
      'diagnostic:warning callHeartbeat missed '
      'peerId=$_peerId callId=$_callId missedMs=${missedFor.inMilliseconds}',
    );
  }

  void _logMediaActiveRecoverySkip(Duration missedFor) {
    final now = _now();
    final lastLogAt = _lastMediaActiveRecoverySkipLogAt;
    if (lastLogAt != null && now.difference(lastLogAt) < logThrottle) {
      return;
    }
    _lastMediaActiveRecoverySkipLogAt = now;
    _log(
      'callHeartbeat:recovery defer media-active '
      'peerId=$_peerId callId=$_callId missedMs=${missedFor.inMilliseconds}',
    );
  }
}
