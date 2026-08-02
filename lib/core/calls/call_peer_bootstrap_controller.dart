import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import '../turn/turn_allocator.dart';
import 'audio_call_peer.dart';
import 'call_models.dart';
import 'call_network_policy_helper.dart';
import 'call_peer_binding_helper.dart';
import 'call_peer_invariant_helper.dart';
import 'call_peer_lifecycle_helper.dart';
import 'call_runtime_tracking.dart';

class CallPeerBootstrapController {
  const CallPeerBootstrapController({
    required String localPeerId,
    required SignalingService signaling,
    required TurnAllocator? turnAllocator,
    required CallNetworkPolicyHelper networkPolicyHelper,
    required CallRuntimeTracking runtimeTracking,
    required CallState Function() getState,
    required AudioCallPeer? Function() getPeer,
    required void Function(AudioCallPeer? peer) setPeer,
    required bool Function(AudioCallPeer peer, String peerId, String callId)
    isCurrentPeerInstance,
    required void Function() cancelConnectAttemptTimeout,
    required void Function() markLocalMediaReady,
    required void Function() markRemoteMediaTimeoutHandled,
    required void Function() updateActiveState,
    required void Function() armMediaReadyTimeout,
    required void Function({required bool recovering, required String status})
    handleIceRecoveryState,
    required Future<void> Function(
      String peerId,
      String type,
      Map<String, dynamic> data, {
      required String purpose,
    })
    sendBestEffortSignal,
    required void Function({required int sentBytes, required int receivedBytes})
    applyStats,
    required bool Function(MediaStream? stream) streamHasVideo,
    required bool Function() getTurnFallbackAttempted,
    required Future<void> Function({
      required String peerId,
      required String callId,
      required String reason,
    })
    retryViaTurn,
    required Future<void> Function(String error) failAndReset,
    required void Function() resetPeerStatsTracking,
    required void Function(bool muted, {required String purpose})
    sendAudioMuteState,
    required void Function(CallState state) emit,
    required void Function(String message) log,
  }) : _localPeerId = localPeerId,
       _signaling = signaling,
       _turnAllocator = turnAllocator,
       _networkPolicyHelper = networkPolicyHelper,
       _runtimeTracking = runtimeTracking,
       _getState = getState,
       _getPeer = getPeer,
       _setPeer = setPeer,
       _isCurrentPeerInstance = isCurrentPeerInstance,
       _cancelConnectAttemptTimeout = cancelConnectAttemptTimeout,
       _markLocalMediaReady = markLocalMediaReady,
       _markRemoteMediaTimeoutHandled = markRemoteMediaTimeoutHandled,
       _updateActiveState = updateActiveState,
       _armMediaReadyTimeout = armMediaReadyTimeout,
       _handleIceRecoveryState = handleIceRecoveryState,
       _sendBestEffortSignal = sendBestEffortSignal,
       _applyStats = applyStats,
       _streamHasVideo = streamHasVideo,
       _getTurnFallbackAttempted = getTurnFallbackAttempted,
       _retryViaTurn = retryViaTurn,
       _failAndReset = failAndReset,
       _resetPeerStatsTracking = resetPeerStatsTracking,
       _sendAudioMuteState = sendAudioMuteState,
       _emit = emit,
       _log = log;

  static const CallPeerBindingHelper _peerBindingHelper =
      CallPeerBindingHelper();
  static const CallPeerInvariantHelper _peerInvariantHelper =
      CallPeerInvariantHelper();
  static const CallPeerLifecycleHelper _peerLifecycleHelper =
      CallPeerLifecycleHelper();

  final String _localPeerId;
  final SignalingService _signaling;
  final TurnAllocator? _turnAllocator;
  final CallNetworkPolicyHelper _networkPolicyHelper;
  final CallRuntimeTracking _runtimeTracking;
  final CallState Function() _getState;
  final AudioCallPeer? Function() _getPeer;
  final void Function(AudioCallPeer? peer) _setPeer;
  final bool Function(AudioCallPeer peer, String peerId, String callId)
  _isCurrentPeerInstance;
  final void Function() _cancelConnectAttemptTimeout;
  final void Function() _markLocalMediaReady;
  final void Function() _markRemoteMediaTimeoutHandled;
  final void Function() _updateActiveState;
  final void Function() _armMediaReadyTimeout;
  final void Function({required bool recovering, required String status})
  _handleIceRecoveryState;
  final Future<void> Function(
    String peerId,
    String type,
    Map<String, dynamic> data, {
    required String purpose,
  })
  _sendBestEffortSignal;
  final void Function({required int sentBytes, required int receivedBytes})
  _applyStats;
  final bool Function(MediaStream? stream) _streamHasVideo;
  final bool Function() _getTurnFallbackAttempted;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required String reason,
  })
  _retryViaTurn;
  final Future<void> Function(String error) _failAndReset;
  final void Function() _resetPeerStatsTracking;
  final void Function(bool muted, {required String purpose})
  _sendAudioMuteState;
  final void Function(CallState state) _emit;
  final void Function(String message) _log;

  Future<AudioCallPeer?> ensurePeer({
    required String peerId,
    required String callId,
  }) async {
    final state = _getState();
    final currentPeer = _getPeer();
    _log(
      'ensurePeer:start peerId=$peerId callId=$callId hasPeer=${currentPeer != null} '
      'matchesCurrent=${_matchesCurrentCall(peerId, callId)}',
    );
    if (_peerInvariantHelper.hasForeignPeerForActiveCallId(
      currentState: state,
      peerId: peerId,
      callId: callId,
    )) {
      _log(
        'ensurePeer:skip foreign-peer same-callId peerId=$peerId callId=$callId '
        'currentPeerId=${state.peerId}',
      );
      return null;
    }

    if (currentPeer != null &&
        _peerInvariantHelper.matchesCurrentCall(
          currentState: state,
          peerId: peerId,
          callId: callId,
        )) {
      _log('ensurePeer:reuse existing peerId=$peerId callId=$callId');
      return currentPeer;
    }

    if (!_matchesCurrentCall(peerId, callId)) {
      _log('ensurePeer:skip mismatch peerId=$peerId callId=$callId');
      return null;
    }

    _log('ensurePeer:create peerId=$peerId callId=$callId');
    final peer = _peerBindingHelper.createPeer(
      localPeerId: _localPeerId,
      signaling: _signaling,
      turnAllocator: _turnAllocator,
      peerId: peerId,
      callId: callId,
      isCurrentPeerInstance: _isCurrentPeerInstance,
      getState: _getState,
      cancelConnectAttemptTimeout: _cancelConnectAttemptTimeout,
      transportLabelFor: _networkPolicyHelper.transportLabelFor,
      emit: _emit,
      markLocalMediaReady: _markLocalMediaReady,
      markRemoteMediaTimeoutHandled: _markRemoteMediaTimeoutHandled,
      updateActiveState: _updateActiveState,
      armMediaReadyTimeout: _armMediaReadyTimeout,
      handleIceRecoveryState: _handleIceRecoveryState,
      sendBestEffortSignal: _sendBestEffortSignal,
      applyStats: _applyStats,
      streamHasVideo: _streamHasVideo,
      getTurnFallbackAttempted: _getTurnFallbackAttempted,
      retryViaTurn: _retryViaTurn,
      failAndReset: _failAndReset,
    );

    _log('ensurePeer:attach begin peerId=$peerId callId=$callId');
    final attached = await _peerLifecycleHelper.attachAndPreparePeer(
      peer: peer,
      peerId: peerId,
      callId: callId,
      currentState: _getState(),
      matchesCurrentCall: _matchesCurrentCall,
      setPeer: _setPeer,
      resetPeerStatsTracking: _resetPeerStatsTracking,
      emit: _emit,
      log: _log,
    );
    _log(
      'ensurePeer:attach done peerId=$peerId callId=$callId '
      'attached=${attached != null}',
    );
    final remoteAudioMute = _runtimeTracking.remoteAudioMuteSnapshot;
    if (attached != null && remoteAudioMute != null) {
      await attached.handleRemoteAudioMuteState(
        muted: remoteAudioMute.muted,
        version: remoteAudioMute.version,
      );
    }
    final remoteVideoState = _runtimeTracking.remoteVideoStateSnapshot;
    if (attached != null && remoteVideoState != null) {
      await attached.handleRemoteVideoState(
        enabled: remoteVideoState.enabled,
        version: remoteVideoState.version,
        peerId: peerId,
        callId: callId,
      );
    }
    if (attached != null && _getState().isMuted) {
      _sendAudioMuteState(
        _getState().isMuted,
        purpose: 'синхронизация mute после attach',
      );
    }
    return attached;
  }

  bool _matchesCurrentCall(String peerId, String callId) {
    return _peerInvariantHelper.matchesCurrentCall(
      currentState: _getState(),
      peerId: peerId,
      callId: callId,
    );
  }
}
