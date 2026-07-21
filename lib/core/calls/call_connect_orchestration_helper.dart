import 'dart:async';

import '../transport/transport_mode.dart';
import 'audio_call_peer.dart';
import 'call_models.dart';

class CallConnectOrchestrationHelper {
  const CallConnectOrchestrationHelper();

  Future<void> startPeerConnection({
    required String peerId,
    required String callId,
    required TransportMode initialMode,
    required Future<AudioCallPeer?> Function({
      required String peerId,
      required String callId,
    })
    ensurePeer,
    required bool Function(String peerId, String callId) matchesCurrentCall,
    required void Function(CallState state) emit,
    required CallState Function() getState,
    required String Function(TransportMode mode) transportLabelFor,
    required CallMediaType Function() getActiveMediaType,
    required void Function(String message) log,
    required Future<void> Function({
      required String peerId,
      required String callId,
      required String reason,
    })
    retryViaTurn,
    required Future<void> Function(String error) failAndReset,
    required void Function({
      required String peerId,
      required String callId,
      required TransportMode mode,
    })
    armConnectAttemptTimeout,
  }) async {
    try {
      final peer = await ensurePeer(peerId: peerId, callId: callId);
      if (peer == null || !matchesCurrentCall(peerId, callId)) {
        return;
      }
      try {
        emit(
          getState().copyWith(
            phase: CallPhase.connecting,
            transportMode: initialMode,
            transportLabel: transportLabelFor(initialMode),
            debugStatus: initialMode == TransportMode.turn
                ? 'Текущая сеть mobile, сразу используем TURN'
                : 'Пробуем прямое соединение (STUN/direct)',
          ),
        );
        await peer.startOutgoing(
          peerId: peerId,
          callId: callId,
          mode: initialMode,
          mediaType: getActiveMediaType(),
        );
        armConnectAttemptTimeout(
          peerId: peerId,
          callId: callId,
          mode: initialMode,
        );
      } catch (error) {
        log('${initialMode.name} failed: $error');
        if (initialMode == TransportMode.direct) {
          await retryViaTurn(
            peerId: peerId,
            callId: callId,
            reason: 'Direct не удался: $error',
          );
          return;
        }
        rethrow;
      }
    } catch (error) {
      await failAndReset('Не удалось установить звонок: $error');
    }
  }

  Timer armConnectAttemptTimeout({
    required Duration timeout,
    required String peerId,
    required String callId,
    required TransportMode mode,
    required int expectedEpoch,
    required CallState Function() getState,
    required int Function() getCurrentEpoch,
    required bool Function() getTurnFallbackAttempted,
    required bool Function() hasTurnAvailableNow,
    required void Function(String message) log,
    required Future<void> Function({
      required String peerId,
      required String callId,
      required String reason,
    })
    retryViaTurn,
    required Future<void> Function(String error) failAndReset,
  }) {
    log(
      'connect timeout armed mode=${mode.name} timeoutMs=${timeout.inMilliseconds}',
    );
    return Timer(timeout, () {
      if (getCurrentEpoch() != expectedEpoch) {
        return;
      }
      final state = getState();
      if (state.peerId != peerId ||
          state.callId != callId ||
          state.phase == CallPhase.active) {
        return;
      }

      if (mode == TransportMode.direct &&
          !getTurnFallbackAttempted() &&
          hasTurnAvailableNow()) {
        log('connect timeout: switching to TURN');
        unawaited(
          retryViaTurn(
            peerId: peerId,
            callId: callId,
            reason: 'Direct timeout',
          ),
        );
        return;
      }

      unawaited(failAndReset('Не удалось установить $mode соединение'));
    });
  }

  Future<void> retryViaTurn({
    required String peerId,
    required String callId,
    required String reason,
    required bool Function() getTurnFallbackAttempted,
    required void Function(bool value) setTurnFallbackAttempted,
    required void Function() cancelConnectAttemptTimeout,
    required void Function() clearMediaReadyTimeout,
    required void Function() resetMediaRuntimeTracking,
    required Future<bool> Function() hasTurnAvailable,
    required void Function(CallState state) emit,
    required CallState Function() getState,
    required Future<void> Function(String error) failAndReset,
    required void Function(String message) log,
    required Future<void> Function() disposePeer,
    required void Function(AudioCallPeer? peer) setPeer,
    required Future<AudioCallPeer?> Function({
      required String peerId,
      required String callId,
    })
    ensurePeer,
    required bool Function(String peerId, String callId) matchesCurrentCall,
    required CallMediaType Function() getActiveMediaType,
    required void Function({
      required String peerId,
      required String callId,
      required TransportMode mode,
    })
    armConnectAttemptTimeout,
  }) async {
    if (getTurnFallbackAttempted()) {
      return;
    }
    setTurnFallbackAttempted(true);
    cancelConnectAttemptTimeout();
    clearMediaReadyTimeout();
    resetMediaRuntimeTracking();

    if (!await hasTurnAvailable()) {
      emit(
        getState().copyWith(
          debugStatus: 'TURN недоступен после ошибки: $reason',
        ),
      );
      await failAndReset('TURN недоступен');
      return;
    }

    log('retryViaTurn reason=$reason');
    emit(
      getState().copyWith(
        phase: CallPhase.connecting,
        transportMode: TransportMode.turn,
        transportLabel: 'TURN relay',
        debugStatus: 'Direct не удался, переключаемся на TURN',
      ),
    );

    await disposePeer();
    setPeer(null);
    final peer = await ensurePeer(peerId: peerId, callId: callId);
    if (peer == null || !matchesCurrentCall(peerId, callId)) {
      return;
    }
    await peer.startOutgoing(
      peerId: peerId,
      callId: callId,
      mode: TransportMode.turn,
      mediaType: getActiveMediaType(),
    );
    armConnectAttemptTimeout(
      peerId: peerId,
      callId: callId,
      mode: TransportMode.turn,
    );
  }
}
