import 'dart:async';

import 'audio_call_peer.dart';
import 'call_recovery_coordinator.dart';
import 'call_models.dart';

class CallMediaTimeoutHelper {
  const CallMediaTimeoutHelper();

  Timer armMediaReadyTimeout({
    required Duration timeout,
    required CallState Function() getState,
    required bool Function() getLocalMediaReady,
    required bool Function() getRemoteMediaReady,
    required int expectedEpoch,
    required int Function() getCurrentEpoch,
    required AudioCallPeer? expectedPeer,
    required String? expectedPeerId,
    required String? expectedCallId,
    required bool Function(String peerId, String callId) matchesCurrentCall,
    required AudioCallPeer? Function() getPeer,
    required int Function() getMediaRecoveryAttempt,
    required void Function(int value) setMediaRecoveryAttempt,
    required Future<CallRecoveryDisposition> Function({
      required int attempt,
      required bool localMediaReady,
      required bool remoteMediaReady,
    })
    onMediaReadyTimeout,
    required void Function(String message) log,
    required void Function() rearmMediaReadyTimeout,
  }) {
    return Timer(timeout, () {
      if (getCurrentEpoch() != expectedEpoch) {
        return;
      }
      if (expectedPeerId == null ||
          expectedCallId == null ||
          expectedPeer == null) {
        return;
      }
      if (!identical(getPeer(), expectedPeer) ||
          !matchesCurrentCall(expectedPeerId, expectedCallId)) {
        return;
      }
      if (getState().isActive ||
          (getLocalMediaReady() && getRemoteMediaReady())) {
        return;
      }

      final attempt = getMediaRecoveryAttempt() + 1;
      setMediaRecoveryAttempt(attempt);
      final localReady = getLocalMediaReady();
      final remoteReady = getRemoteMediaReady();
      log(
        'mediaReady timeout: observe local=$localReady remote=$remoteReady '
        'attempt=$attempt',
      );
      unawaited(
        onMediaReadyTimeout(
          attempt: attempt,
          localMediaReady: localReady,
          remoteMediaReady: remoteReady,
        ).then((disposition) {
          if (disposition == CallRecoveryDisposition.retryLater) {
            rearmMediaReadyTimeout();
          }
        }),
      );
    });
  }
}
