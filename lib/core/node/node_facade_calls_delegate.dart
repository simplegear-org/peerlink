import 'dart:async';

import '../calls/call_models.dart';
import '../calls/call_service.dart';
import 'mesh_node.dart';

class NodeFacadeCallsDelegate {
  NodeFacadeCallsDelegate({required MeshNode node, required CallService calls})
    : _node = node,
      _calls = calls;

  final MeshNode _node;
  final CallService _calls;

  CallState get callState => _calls.state;
  Stream<CallState> get callStateStream => _calls.stateStream;

  Future<void> startCall(String peerId) {
    return _startCallWithPush(peerId, mediaType: CallMediaType.audio);
  }

  Future<void> startVideoCall(String peerId) {
    return _startCallWithPush(peerId, mediaType: CallMediaType.video);
  }

  Future<void> acceptIncomingCall() {
    return _calls.acceptIncomingCall();
  }

  Future<void> rejectIncomingCall() {
    return _calls.rejectIncomingCall();
  }

  Future<void> endCall() async {
    final state = _calls.state;
    final peerId = state.peerId;
    final callId = state.callId;
    final shouldSendVoipEnd =
        state.direction == CallDirection.outgoing &&
        peerId != null &&
        peerId.isNotEmpty &&
        callId != null &&
        callId.isNotEmpty;
    if (shouldSendVoipEnd) {
      unawaited(_sendCallEndPushBestEffort(peerId: peerId, callId: callId));
    }
    return _calls.endCall();
  }

  Future<void> toggleCallMuted() {
    return _calls.toggleMuted();
  }

  Future<void> toggleCallVideo() {
    return _calls.toggleVideo();
  }

  Future<void> flipCallCamera() {
    return _calls.flipCamera();
  }

  Future<void> setCallSpeakerOn(bool enabled) {
    return _calls.setSpeakerOn(enabled);
  }

  Future<void> presentIncomingCallFromPush({
    required String peerId,
    required String callId,
    CallMediaType mediaType = CallMediaType.audio,
  }) {
    return _calls.presentIncomingCallFromPush(
      peerId: peerId,
      callId: callId,
      mediaType: mediaType,
    );
  }

  Future<void> endCallFromRemotePush({
    required String peerId,
    required String callId,
  }) {
    return _calls.endCallFromRemotePush(peerId: peerId, callId: callId);
  }

  Future<void> _startCallWithPush(
    String peerId, {
    required CallMediaType mediaType,
  }) async {
    if (_calls.state.isBusy) {
      throw StateError('Call already in progress');
    }
    final callId = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      await _calls.startOutgoingCall(
        peerId,
        mediaType: mediaType,
        callId: callId,
      );
    } catch (_) {
      rethrow;
    }
    unawaited(
      _sendCallInvitePushBestEffort(
        peerId: peerId,
        callId: callId,
        mediaType: mediaType,
      ),
    );
    final stateAfterStart = _calls.state;
    final signalingInviteWasSent =
        stateAfterStart.callId == callId &&
        stateAfterStart.peerId == peerId &&
        stateAfterStart.phase != CallPhase.failed &&
        stateAfterStart.phase != CallPhase.idle &&
        stateAfterStart.phase != CallPhase.ended;
    if (!signalingInviteWasSent) {
      unawaited(_sendCallEndPushBestEffort(peerId: peerId, callId: callId));
    }
  }

  Future<void> _sendCallInvitePushBestEffort({
    required String peerId,
    required String callId,
    required CallMediaType mediaType,
  }) async {
    try {
      await _node.sendCallInvitePushEvent(
        calleeUserId: peerId,
        callId: callId,
        mediaType: mediaType,
      );
    } catch (_) {
      // Call push is best-effort; signaling path remains source of truth.
    }
  }

  Future<void> _sendCallEndPushBestEffort({
    required String peerId,
    required String callId,
  }) async {
    try {
      await _node.sendCallEndPushEvent(calleeUserId: peerId, callId: callId);
    } catch (_) {}
  }
}
