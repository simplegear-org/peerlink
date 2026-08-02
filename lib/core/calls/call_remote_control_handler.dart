import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'audio_call_peer.dart';
import 'call_heartbeat_controller.dart';
import 'call_models.dart';
import 'call_runtime_tracking.dart';
import 'call_state_update_helper.dart';

class CallRemoteControlHandler {
  const CallRemoteControlHandler({
    required CallHeartbeatController heartbeatController,
    required CallRuntimeTracking runtimeTracking,
    required CallState Function() getState,
    required AudioCallPeer? Function() getPeer,
    required void Function(CallState state) emit,
    required void Function(String message) log,
    required void Function() markRemoteMediaReady,
    required void Function() cancelMediaReadyTimeout,
    required void Function() updateActiveState,
    required void Function() armMediaReadyTimeout,
    required bool Function(MediaStream? stream) streamHasVideo,
  }) : _heartbeatController = heartbeatController,
       _runtimeTracking = runtimeTracking,
       _getState = getState,
       _getPeer = getPeer,
       _emit = emit,
       _log = log,
       _markRemoteMediaReady = markRemoteMediaReady,
       _cancelMediaReadyTimeout = cancelMediaReadyTimeout,
       _updateActiveState = updateActiveState,
       _armMediaReadyTimeout = armMediaReadyTimeout,
       _streamHasVideo = streamHasVideo;

  static const CallStateUpdateHelper _stateUpdateHelper =
      CallStateUpdateHelper();

  final CallHeartbeatController _heartbeatController;
  final CallRuntimeTracking _runtimeTracking;
  final CallState Function() _getState;
  final AudioCallPeer? Function() _getPeer;
  final void Function(CallState state) _emit;
  final void Function(String message) _log;
  final void Function() _markRemoteMediaReady;
  final void Function() _cancelMediaReadyTimeout;
  final void Function() _updateActiveState;
  final void Function() _armMediaReadyTimeout;
  final bool Function(MediaStream? stream) _streamHasVideo;

  Future<void> handleRemoteMediaReady({
    required String peerId,
    required String callId,
  }) async {
    _markRemoteMediaReady();
    _cancelMediaReadyTimeout();
    _updateActiveState();
    _armMediaReadyTimeout();
  }

  Future<void> handleRemoteHeartbeat({
    required String peerId,
    required String callId,
    required int seq,
    required int sentAtMs,
  }) async {
    _heartbeatController.markRemoteHeartbeat(
      peerId: peerId,
      callId: callId,
      seq: seq,
      sentAtMs: sentAtMs,
    );
  }

  Future<void> handleRemoteAudioMuteState({
    required String peerId,
    required String callId,
    required bool muted,
    required int version,
  }) async {
    if (!_runtimeTracking.shouldApplyRemoteAudioMuteVersion(version)) {
      _log(
        'audioMute:remote ignored peerId=$peerId callId=$callId '
        'muted=$muted version=$version lastVersion=${_runtimeTracking.remoteAudioMuteVersion}',
      );
      return;
    }
    _runtimeTracking.applyRemoteAudioMute(muted: muted, version: version);
    _log(
      'audioMute:remote peerId=$peerId callId=$callId '
      'muted=$muted version=$version',
    );
    await _getPeer()?.handleRemoteAudioMuteState(
      muted: muted,
      version: version,
    );
  }

  Future<void> handleRemoteVideoState({
    required String peerId,
    required String callId,
    required bool enabled,
    required int version,
  }) async {
    if (!_runtimeTracking.shouldApplyRemoteVideoStateVersion(version)) {
      _log(
        'video:remote ignored peerId=$peerId callId=$callId '
        'enabled=$enabled version=$version '
        'lastVersion=${_runtimeTracking.remoteVideoStateVersion}',
      );
      return;
    }
    _runtimeTracking.applyRemoteVideoState(enabled: enabled, version: version);
    _emit(
      _stateUpdateHelper.applyRemoteVideoState(
        currentState: _getState(),
        enabled: enabled,
        streamHasVideo: _streamHasVideo,
      ),
    );
    await _getPeer()?.handleRemoteVideoState(
      enabled: enabled,
      version: version,
      peerId: peerId,
      callId: callId,
    );
  }

  Future<void> handleRemoteVideoStateAck({
    required String peerId,
    required String callId,
    required bool enabled,
    required int version,
  }) async {
    await _getPeer()?.handleVideoStateAck(enabled: enabled, version: version);
  }

  Future<void> handleRemoteVideoFlowAck({
    required String peerId,
    required String callId,
    required int version,
  }) async {
    await _getPeer()?.handleVideoFlowAck(version: version);
  }
}
