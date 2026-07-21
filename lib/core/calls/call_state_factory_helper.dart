import 'call_models.dart';

class CallStateFactoryHelper {
  const CallStateFactoryHelper();

  CallState applyMuted(CallState currentState, bool muted) {
    return currentState.copyWith(isMuted: muted);
  }

  CallState applySpeakerOn(CallState currentState, bool enabled) {
    return currentState.copyWith(speakerOn: enabled);
  }

  CallState videoToggleStarted({
    required CallState currentState,
    required bool targetEnabled,
  }) {
    return currentState.copyWith(
      videoToggleInProgress: true,
      debugStatus: targetEnabled ? 'Включаем камеру' : 'Выключаем камеру',
    );
  }

  CallState videoToggleSucceeded({
    required CallState currentState,
    required CallMediaType nextMediaType,
  }) {
    return currentState.copyWith(
      mediaType: nextMediaType,
      localVideoEnabled: nextMediaType == CallMediaType.video,
      videoToggleInProgress: false,
      debugStatus: nextMediaType == CallMediaType.video
          ? 'Камера включена'
          : 'Камера выключена',
    );
  }

  CallState videoToggleFailed({
    required CallState currentState,
    required Object error,
  }) {
    return currentState.copyWith(
      videoToggleInProgress: false,
      debugStatus: 'Не удалось переключить камеру',
      error: error.toString(),
    );
  }
}
