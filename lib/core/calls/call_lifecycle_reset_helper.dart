import 'call_models.dart';

typedef CallLifecycleSignalSender =
    void Function(
      String peerId,
      String type,
      Map<String, dynamic> data, {
      required String purpose,
    });

class CallLifecycleResetHelper {
  const CallLifecycleResetHelper();

  Future<void> failAndReset({
    required CallState currentState,
    required String error,
    required int expectedEpoch,
    required int Function() getCurrentEpoch,
    required void Function(CallState state) emit,
    required Future<void> Function() resetToIdle,
    required CallLifecycleSignalSender sendDetachedSignal,
  }) async {
    final peerId = currentState.peerId;
    final callId = currentState.callId;
    if (peerId != null && callId != null) {
      sendDetachedSignal(peerId, 'call_end', {
        'callId': callId,
        'signalScope': 'call',
        'reason': error,
      }, purpose: 'сбой звонка');
    }
    emit(
      currentState.copyWith(
        phase: CallPhase.failed,
        error: error,
        debugStatus: error,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (getCurrentEpoch() != expectedEpoch) {
      return;
    }
    await resetToIdle();
  }

  Future<void> endAndReset({
    required CallState currentState,
    required String status,
    required int expectedEpoch,
    required int Function() getCurrentEpoch,
    required void Function(CallState state) emit,
    required Future<void> Function() resetToIdle,
  }) async {
    emit(
      currentState.copyWith(
        phase: CallPhase.ended,
        debugStatus: status,
        clearError: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (getCurrentEpoch() != expectedEpoch) {
      return;
    }
    await resetToIdle();
  }
}
