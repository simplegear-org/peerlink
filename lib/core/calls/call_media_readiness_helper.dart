import 'call_models.dart';
import '../transport/transport_mode.dart';

class CallMediaReadinessHelper {
  const CallMediaReadinessHelper();

  CallState buildReadinessState({
    required CallState currentState,
    required bool localMediaReady,
    required bool remoteMediaReady,
    required DateTime now,
  }) {
    if (currentState.isRecovering) {
      return currentState;
    }
    if (localMediaReady && remoteMediaReady) {
      if (currentState.phase == CallPhase.active) {
        return currentState;
      }
      return currentState.copyWith(
        phase: CallPhase.active,
        debugStatus: currentState.transportMode == TransportMode.turn
            ? 'Звонок через TURN активен, видеоканал готов'
            : 'Звонок активен, видеоканал готов',
        connectedAt: now,
      );
    }

    final waitingFor = <String>[];
    if (!localMediaReady) {
      waitingFor.add('локальный входящий аудиопоток');
    }
    if (!remoteMediaReady) {
      waitingFor.add('подтверждение второй стороны');
    }

    return currentState.copyWith(
      phase: CallPhase.connecting,
      debugStatus: 'Ждем ${waitingFor.join(' и ')}',
    );
  }
}
