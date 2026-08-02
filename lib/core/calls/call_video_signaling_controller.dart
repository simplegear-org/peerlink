import 'dart:async';

import '../signaling/signaling_service.dart';
import 'call_epoch_timer.dart';
import 'call_video_state.dart';

class CallVideoSignalingController {
  const CallVideoSignalingController({
    required SignalingService signaling,
    required CallVideoState state,
    required void Function(String message) log,
    required int Function() getSessionEpoch,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required Future<void> Function(String reason) onRemoteVideoFlowStalled,
    required void Function() scheduleVideoQualityUpgrade,
  }) : _signaling = signaling,
       _state = state,
       _log = log,
       _getSessionEpoch = getSessionEpoch,
       _getPeerId = getPeerId,
       _getCallId = getCallId,
       _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
       _onRemoteVideoFlowStalled = onRemoteVideoFlowStalled,
       _scheduleVideoQualityUpgrade = scheduleVideoQualityUpgrade;

  final SignalingService _signaling;
  final CallVideoState _state;
  final void Function(String message) _log;
  final int Function() _getSessionEpoch;
  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final void Function(bool active) _onRemoteVideoFlowChanged;
  final Future<void> Function(String reason) _onRemoteVideoFlowStalled;
  final void Function() _scheduleVideoQualityUpgrade;

  void scheduleVideoUplinkFallback(int version) {
    cancelVideoUplinkFallback();
    _state.pendingVideoFlowVersion = version;
    _log('video:fallback disabled version=$version');
  }

  void scheduleRemoteVideoFlowRecovery(int version) {
    cancelRemoteVideoFlowRecovery();
    _state.pendingRemoteVideoRecoveryVersion = version;
    final expectedEpoch = _getSessionEpoch();
    _state.remoteVideoFlowRecoveryTimer = CallEpochTimer.arm(
      duration: const Duration(seconds: 4),
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: _getSessionEpoch,
      onCurrent: () async {
        if (_state.pendingRemoteVideoRecoveryVersion != version ||
            !_state.remoteVideoEnabled ||
            _state.remoteVideoFlowSeen) {
          return;
        }
        _log('video:flow recovery timeout version=$version');
        await _onRemoteVideoFlowStalled(
          'Remote video flow timeout version=$version',
        );
      },
    );
  }

  void cancelRemoteVideoFlowRecovery() {
    _state.remoteVideoFlowRecoveryTimer?.cancel();
    _state.remoteVideoFlowRecoveryTimer = null;
    _state.pendingRemoteVideoRecoveryVersion = null;
  }

  void cancelVideoUplinkFallback() {
    if (_state.videoUplinkFallbackTimer?.isActive ?? false) {
      _log('video:fallback canceled');
    }
    _state.videoUplinkFallbackTimer?.cancel();
    _state.videoUplinkFallbackTimer = null;
    _state.pendingVideoFlowVersion = null;
  }

  Future<void> sendVideoState({
    required bool enabled,
    required String peerId,
    required String callId,
  }) async {
    final version = _state.videoStateVersion + 1;
    _state.videoStateVersion = version;
    _state.pendingVideoStateVersion = version;
    _state.pendingVideoStateEnabled = enabled;
    _state.pendingVideoStateAttempts = 0;
    await sendVideoStateAttempt(
      enabled: enabled,
      peerId: peerId,
      callId: callId,
      version: version,
    );
    if (enabled) {
      scheduleVideoUplinkFallback(version);
    } else {
      cancelVideoUplinkFallback();
    }
  }

  Future<void> handleRemoteVideoState({
    required bool enabled,
    required int version,
    required String peerId,
    required String callId,
  }) async {
    await _signaling.sendSignal(peerId, 'call_video_state_ack', {
      'callId': callId,
      'signalScope': 'call',
      'enabled': enabled,
      'version': version,
    });
    if (version <= _state.remoteVideoStateVersion) {
      _log(
        'video:remote state ignored enabled=$enabled version=$version '
        'lastVersion=${_state.remoteVideoStateVersion}',
      );
      return;
    }
    _state.remoteVideoStateVersion = version;
    _state.remoteVideoEnabled = enabled;
    if (enabled) {
      _state.pendingRemoteVideoFlowAckVersion = version;
      _state.remoteVideoFlowSeen = false;
      _state.lastInboundVideoBytes = -1;
      _state.lastInboundVideoFramesDecoded = -1;
      _onRemoteVideoFlowChanged(false);
      scheduleRemoteVideoFlowRecovery(version);
      _log('video:remote state enabled version=$version awaiting-flow');
      return;
    }
    cancelRemoteVideoFlowRecovery();
    _state.pendingRemoteVideoFlowAckVersion = null;
    _state.lastInboundVideoBytes = -1;
    _state.lastInboundVideoFramesDecoded = -1;
    if (_state.remoteVideoFlowSeen) {
      _state.remoteVideoFlowSeen = false;
      _onRemoteVideoFlowChanged(false);
    }
    _log('video:remote state disabled version=$version');
  }

  void handleVideoStateAck({required bool enabled, required int version}) {
    final pendingVersion = _state.pendingVideoStateVersion;
    final pendingEnabled = _state.pendingVideoStateEnabled;
    if (pendingVersion != version || pendingEnabled != enabled) {
      _log(
        'video:ack ignored version=$version enabled=$enabled '
        'pendingVersion=$pendingVersion pendingEnabled=$pendingEnabled',
      );
      return;
    }
    _log('video:ack received version=$version enabled=$enabled');
    cancelPendingVideoStateAck();
  }

  void handleVideoFlowAck({required int version}) {
    if (_state.pendingVideoFlowVersion != version) {
      _log(
        'video:flow ack ignored version=$version '
        'pendingVersion=${_state.pendingVideoFlowVersion}',
      );
      return;
    }
    _log('video:flow ack received version=$version');
    cancelVideoUplinkFallback();
    _scheduleVideoQualityUpgrade();
  }

  void markRemoteVideoFlowDetected() {
    cancelRemoteVideoFlowRecovery();
  }

  Future<void> sendVideoStateAttempt({
    required bool enabled,
    required String peerId,
    required String callId,
    required int version,
  }) async {
    _state.pendingVideoStateAttempts += 1;
    _log(
      'video:state send enabled=$enabled version=$version '
      'attempt=${_state.pendingVideoStateAttempts}',
    );
    await _signaling.sendSignal(peerId, 'call_video_state', {
      'callId': callId,
      'signalScope': 'call',
      'enabled': enabled,
      'version': version,
    });
    try {
      await _signaling.sendSignal(peerId, 'call_video_mute_state', {
        'callId': callId,
        'signalScope': 'call',
        'muted': !enabled,
        'version': version,
      });
    } catch (error) {
      _log(
        'video:mute-state send skipped enabled=$enabled '
        'version=$version error=$error',
      );
    }
    _state.videoStateAckTimer?.cancel();
    final expectedEpoch = _getSessionEpoch();
    _state.videoStateAckTimer = CallEpochTimer.arm(
      duration: const Duration(milliseconds: 1200),
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: _getSessionEpoch,
      onStale: cancelPendingVideoStateAck,
      onCurrent: () {
        if (_state.pendingVideoStateVersion != version ||
            _state.pendingVideoStateEnabled != enabled) {
          return;
        }
        if (_state.pendingVideoStateAttempts >= 5) {
          _log('video:ack timeout enabled=$enabled version=$version');
          cancelPendingVideoStateAck();
          return;
        }
        final currentPeerId = _getPeerId();
        final currentCallId = _getCallId();
        if (currentPeerId == null || currentCallId == null) {
          cancelPendingVideoStateAck();
          return;
        }
        unawaited(
          sendVideoStateAttempt(
            enabled: enabled,
            peerId: currentPeerId,
            callId: currentCallId,
            version: version,
          ),
        );
      },
    );
  }

  void cancelPendingVideoStateAck() {
    _state.videoStateAckTimer?.cancel();
    _state.videoStateAckTimer = null;
    _state.pendingVideoStateVersion = null;
    _state.pendingVideoStateEnabled = null;
    _state.pendingVideoStateAttempts = 0;
  }
}
