import 'dart:async';

import 'call_epoch_timer.dart';
import 'call_models.dart';

class CallCameraFlipController {
  CallCameraFlipController({
    required void Function(String message) log,
    required CallMediaType Function() getMediaType,
    required bool Function() hasLocalVideo,
    required Future<bool> Function() canExecute,
    required Future<void> Function() performFlip,
    required bool Function() getRenegotiationInProgress,
    required String Function() getSignalingStateLabel,
  }) : _log = log,
       _getMediaType = getMediaType,
       _hasLocalVideo = hasLocalVideo,
       _canExecute = canExecute,
       _performFlip = performFlip,
       _getRenegotiationInProgress = getRenegotiationInProgress,
       _getSignalingStateLabel = getSignalingStateLabel;

  final void Function(String message) _log;
  final CallMediaType Function() _getMediaType;
  final bool Function() _hasLocalVideo;
  final Future<bool> Function() _canExecute;
  final Future<void> Function() _performFlip;
  final bool Function() _getRenegotiationInProgress;
  final String Function() _getSignalingStateLabel;

  int _queuedFlipCount = 0;
  int _generation = 0;
  bool _flipInProgress = false;
  Timer? _queuedFlipRetryTimer;

  Future<void> flipCamera() async {
    if (_getMediaType() != CallMediaType.video) {
      return;
    }
    if (!_hasLocalVideo()) {
      return;
    }
    if (_flipInProgress) {
      _enqueueFlip('flip-in-progress');
      return;
    }
    if (!await _canExecute()) {
      _log(
        'video:flip skipped reason=signaling-not-stable '
        'renegotiation=${_getRenegotiationInProgress()} '
        'signaling=${_getSignalingStateLabel()}',
      );
      return;
    }
    await _runFlip();
  }

  void scheduleQueuedRetry() {
    _scheduleQueuedRetry();
  }

  void clear() {
    _generation += 1;
    _queuedFlipRetryTimer?.cancel();
    _queuedFlipRetryTimer = null;
    _queuedFlipCount = 0;
    _flipInProgress = false;
  }

  void _enqueueFlip(String reason) {
    _queuedFlipCount = 1;
    _log(
      'video:flip queued reason=$reason pending=$_queuedFlipCount '
      'renegotiation=${_getRenegotiationInProgress()} '
      'signaling=${_getSignalingStateLabel()}',
    );
    _scheduleQueuedRetry();
  }

  void _scheduleQueuedRetry() {
    if (_queuedFlipCount == 0 || _flipInProgress) {
      return;
    }
    if (_queuedFlipRetryTimer?.isActive ?? false) {
      return;
    }
    final expectedGeneration = _generation;
    _queuedFlipRetryTimer = CallEpochTimer.arm(
      duration: const Duration(milliseconds: 250),
      expectedEpoch: expectedGeneration,
      getCurrentEpoch: () => _generation,
      onCurrent: _drainQueuedFlip,
      onStale: () {
        _queuedFlipRetryTimer = null;
      },
    );
  }

  Future<void> _drainQueuedFlip() async {
    _queuedFlipRetryTimer?.cancel();
    _queuedFlipRetryTimer = null;
    if (_queuedFlipCount == 0 || _flipInProgress) {
      return;
    }
    if (!_hasLocalVideo()) {
      _log('video:flip queue cleared reason=no-local-video');
      _queuedFlipCount = 0;
      return;
    }
    if (!await _canExecute()) {
      _scheduleQueuedRetry();
      return;
    }
    final pending = _queuedFlipCount;
    _queuedFlipCount = 0;
    if (pending.isEven) {
      _log('video:flip queue coalesced pending=$pending action=no-op');
      return;
    }
    _log('video:flip queue drain pending=$pending action=single-flip');
    await _runFlip();
  }

  Future<void> _runFlip() async {
    _flipInProgress = true;
    try {
      await _performFlip();
    } finally {
      _flipInProgress = false;
      if (_queuedFlipCount > 0) {
        _scheduleQueuedRetry();
      }
    }
  }
}
