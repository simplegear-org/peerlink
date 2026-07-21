import 'audio_call_peer.dart';
import 'call_models.dart';

class CallPeerLifecycleHelper {
  const CallPeerLifecycleHelper();

  Future<AudioCallPeer?> attachAndPreparePeer({
    required AudioCallPeer peer,
    required String peerId,
    required String callId,
    required CallState currentState,
    required bool Function(String peerId, String callId) matchesCurrentCall,
    required void Function(AudioCallPeer? peer) setPeer,
    required void Function() resetPeerStatsTracking,
    required void Function(CallState state) emit,
    required void Function(String message) log,
  }) async {
    log('peerLifecycle:attach start peerId=$peerId callId=$callId');
    setPeer(peer);
    resetPeerStatsTracking();

    log('peerLifecycle:applyMuted start muted=${currentState.isMuted}');
    await peer.setMuted(currentState.isMuted);
    log('peerLifecycle:applyMuted done muted=${currentState.isMuted}');
    log('peerLifecycle:applySpeaker start speakerOn=${currentState.speakerOn}');
    await peer.setSpeakerOn(currentState.speakerOn);
    log('peerLifecycle:applySpeaker done speakerOn=${currentState.speakerOn}');
    if (!matchesCurrentCall(peerId, callId)) {
      log('peerLifecycle:dispose mismatch peerId=$peerId callId=$callId');
      setPeer(null);
      await peer.dispose();
      return null;
    }

    emit(
      currentState.copyWith(
        phase: CallPhase.connecting,
        peerId: peerId,
        callId: callId,
        debugStatus: 'Готовим WebRTC сессию аудио + видео',
        localVideoEnabled: false,
        localVideoAvailable: false,
        remoteVideoEnabled: false,
        remoteVideoAvailable: false,
        remoteVideoActive: false,
        clearRemoteVideoTrackId: true,
        clearVideoCodec: true,
        videoToggleInProgress: false,
        localStream: null,
        remoteStream: null,
      ),
    );
    log('peerLifecycle:attach ready peerId=$peerId callId=$callId');
    return peer;
  }

  Future<void> resetToIdle({
    required void Function() cancelOutgoingTimeout,
    required void Function() cancelConnectAttemptTimeout,
    required void Function() clearMediaReadyTimeout,
    required void Function() resetRuntimeTracking,
    required Future<void> Function() disposePeer,
    required void Function(AudioCallPeer? peer) setPeer,
    required void Function(CallState state) emit,
  }) async {
    cancelOutgoingTimeout();
    cancelConnectAttemptTimeout();
    clearMediaReadyTimeout();
    resetRuntimeTracking();
    await disposePeer();
    setPeer(null);
    emit(const CallState(phase: CallPhase.idle));
  }
}
