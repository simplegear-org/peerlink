import 'call_models.dart';

class CallPeerInvariantHelper {
  const CallPeerInvariantHelper();

  bool matchesCurrentCall({
    required CallState currentState,
    required String peerId,
    required String callId,
  }) {
    return !currentState.isIdle &&
        currentState.peerId == peerId &&
        currentState.callId == callId;
  }

  bool hasForeignPeerForActiveCallId({
    required CallState currentState,
    required String peerId,
    required String callId,
  }) {
    return !currentState.isIdle &&
        currentState.callId == callId &&
        currentState.peerId != null &&
        currentState.peerId != peerId;
  }
}
