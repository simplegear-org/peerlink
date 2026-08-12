import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_epoch_timer.dart';

class CallPostIceRecoveryFlowWatch {
  static const String iceReconnectStalledReason =
      'ICE did not reconnect after recovery signaling';

  CallPostIceRecoveryFlowWatch({
    required void Function(String message) log,
    required RTCPeerConnection? Function() getPeer,
    required bool Function() getIceConnected,
    required bool Function() getIceRecoveryInProgress,
    required bool Function() getRemoteAudioMuted,
    required bool Function() getRemoteAudioFlowSeen,
    required bool Function() getRemoteVideoEnabled,
    required bool Function() getRemoteVideoTrackSeen,
    required bool Function() getRemoteVideoFlowSeen,
    required void Function(bool value) setRemoteAudioFlowSeen,
    required void Function(bool value) setRemoteVideoFlowSeen,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required void Function() onIceMediaRecoveryCompleted,
    required Future<void> Function(String reason) onIceReconnectStalled,
    required Future<void> Function(String reason) onPostIceRecoveryFlowStalled,
    Future<void> Function(String reason)? onPostIceRecoveryVideoOnlyStalled,
    required int Function() getSessionEpoch,
    Duration grace = const Duration(seconds: 4),
  }) : _log = log,
       _getPeer = getPeer,
       _getIceConnected = getIceConnected,
       _getIceRecoveryInProgress = getIceRecoveryInProgress,
       _getRemoteAudioMuted = getRemoteAudioMuted,
       _getRemoteAudioFlowSeen = getRemoteAudioFlowSeen,
       _getRemoteVideoEnabled = getRemoteVideoEnabled,
       _getRemoteVideoTrackSeen = getRemoteVideoTrackSeen,
       _getRemoteVideoFlowSeen = getRemoteVideoFlowSeen,
       _setRemoteAudioFlowSeen = setRemoteAudioFlowSeen,
       _setRemoteVideoFlowSeen = setRemoteVideoFlowSeen,
       _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
       _onIceMediaRecoveryCompleted = onIceMediaRecoveryCompleted,
       _onIceReconnectStalled = onIceReconnectStalled,
       _onPostIceRecoveryFlowStalled = onPostIceRecoveryFlowStalled,
       _onPostIceRecoveryVideoOnlyStalled = onPostIceRecoveryVideoOnlyStalled,
       _getSessionEpoch = getSessionEpoch,
       _grace = grace;

  final void Function(String message) _log;
  final RTCPeerConnection? Function() _getPeer;
  final bool Function() _getIceConnected;
  final bool Function() _getIceRecoveryInProgress;
  final bool Function() _getRemoteAudioMuted;
  final bool Function() _getRemoteAudioFlowSeen;
  final bool Function() _getRemoteVideoEnabled;
  final bool Function() _getRemoteVideoTrackSeen;
  final bool Function() _getRemoteVideoFlowSeen;
  final void Function(bool value) _setRemoteAudioFlowSeen;
  final void Function(bool value) _setRemoteVideoFlowSeen;
  final void Function(bool active) _onRemoteVideoFlowChanged;
  final void Function() _onIceMediaRecoveryCompleted;
  final Future<void> Function(String reason) _onIceReconnectStalled;
  final Future<void> Function(String reason) _onPostIceRecoveryFlowStalled;
  final Future<void> Function(String reason)?
  _onPostIceRecoveryVideoOnlyStalled;
  final int Function() _getSessionEpoch;
  final Duration _grace;

  Timer? _timer;
  int _generation = 0;
  bool _awaitingFlow = false;
  bool _expectRemoteVideo = false;

  bool get isAwaitingFlow => _awaitingFlow;

  void begin({
    required void Function() resetMediaFlowBaselines,
    required void Function() resetLiveMediaBaselines,
  }) {
    final expectVideo =
        _getRemoteVideoEnabled() &&
        (_getRemoteVideoTrackSeen() || _getRemoteVideoFlowSeen());
    _awaitingFlow = true;
    _expectRemoteVideo = expectVideo;
    _setRemoteAudioFlowSeen(false);
    if (_getRemoteVideoFlowSeen()) {
      _setRemoteVideoFlowSeen(false);
      _onRemoteVideoFlowChanged(false);
    }
    resetMediaFlowBaselines();
    resetLiveMediaBaselines();
    _invalidateTimer();
    _log('ice:media watch start expectVideo=$expectVideo');
  }

  void reset({required String reason}) {
    if (!_awaitingFlow && !(_timer?.isActive ?? false)) {
      return;
    }
    _invalidateTimer();
    _log('ice:media watch reset reason="$reason"');
  }

  void arm() {
    if (!_awaitingFlow || _getPeer() == null || (_timer?.isActive ?? false)) {
      return;
    }
    final expectedEpoch = _getSessionEpoch();
    final expectedGeneration = _generation;
    _timer = CallEpochTimer.arm(
      duration: _grace,
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: _getSessionEpoch,
      onStale: () {
        _timer = null;
      },
      onCurrent: () async {
        _timer = null;
        if (!_isCurrentWatch(
          expectedEpoch: expectedEpoch,
          expectedGeneration: expectedGeneration,
        )) {
          return;
        }
        if (!_getIceConnected()) {
          if (_getIceRecoveryInProgress()) {
            _log('ice:reconnect watch pending recovery');
            return;
          }
          _log('ice:reconnect watch timeout');
          await _onIceReconnectStalled(iceReconnectStalledReason);
          return;
        }
        final missingAudio =
            !_getRemoteAudioMuted() && !_getRemoteAudioFlowSeen();
        final missingVideo = _expectRemoteVideo && !_getRemoteVideoFlowSeen();
        if (!missingAudio && !missingVideo) {
          return;
        }
        _log(
          'ice:media watch timeout missingAudio=$missingAudio '
          'missingVideo=$missingVideo expectVideo=$_expectRemoteVideo',
        );
        if (!missingAudio && missingVideo) {
          final handler = _onPostIceRecoveryVideoOnlyStalled;
          if (handler != null) {
            _generation += 1;
            _awaitingFlow = false;
            _expectRemoteVideo = false;
            _onRemoteVideoFlowChanged(false);
            await handler(
              'Remote video flow did not recover after ICE reconnection',
            );
            if (_getIceRecoveryInProgress()) {
              _log('ice:media recovered audioOnly=true');
              _onIceMediaRecoveryCompleted();
            }
            return;
          }
        }
        await _onPostIceRecoveryFlowStalled(
          'Media flow did not recover after ICE reconnection',
        );
      },
    );
    _log('ice:media watch armed graceMs=${_grace.inMilliseconds}');
  }

  void completeIfReady() {
    if (!_awaitingFlow) {
      return;
    }
    final audioRecovered = _getRemoteAudioMuted() || _getRemoteAudioFlowSeen();
    final videoRecovered = !_expectRemoteVideo || _getRemoteVideoFlowSeen();
    if (!audioRecovered || !videoRecovered) {
      return;
    }
    _awaitingFlow = false;
    _expectRemoteVideo = false;
    _invalidateTimer();
    if (_getIceRecoveryInProgress()) {
      _log('ice:media recovered');
      _onIceMediaRecoveryCompleted();
    }
  }

  void clear() {
    _awaitingFlow = false;
    _expectRemoteVideo = false;
    _invalidateTimer();
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _invalidateTimer() {
    _generation += 1;
    _cancelTimer();
  }

  bool _isCurrentWatch({
    required int expectedEpoch,
    required int expectedGeneration,
  }) {
    return _getSessionEpoch() == expectedEpoch &&
        _generation == expectedGeneration &&
        _awaitingFlow &&
        _getPeer() != null;
  }
}
