import 'dart:async';

import 'call_models.dart';

typedef CallCommandSignalSender =
    Future<void> Function(
      String peerId,
      String type,
      Map<String, dynamic> data,
    );

typedef CallDetachedSignalSender =
    void Function(
      String peerId,
      String type,
      Map<String, dynamic> data, {
      required String purpose,
    });

class CallCommandHelper {
  const CallCommandHelper();

  Future<void> startOutgoingCall({
    required CallState currentState,
    required String peerId,
    required CallMediaType mediaType,
    required String? callId,
    required Map<String, dynamic> inviteMetadata,
    required void Function() resetRuntimeTracking,
    required void Function(CallState state) emit,
    required Future<void> Function(String purpose) waitForSignalingReady,
    required Future<void> Function(String error) failAndReset,
    required void Function(Timer? timer) setOutgoingTimeout,
    required Future<void> Function(String status) endAndReset,
    required CallCommandSignalSender sendSignal,
    required void Function(String message) log,
  }) async {
    if (currentState.isBusy) {
      throw StateError('Call already in progress');
    }

    final normalizedCallId = (callId ?? '').trim();
    final resolvedCallId = normalizedCallId.isNotEmpty
        ? normalizedCallId
        : DateTime.now().microsecondsSinceEpoch.toString();
    resetRuntimeTracking();
    emit(
      CallState(
        phase: CallPhase.outgoingRinging,
        callId: resolvedCallId,
        peerId: peerId,
        direction: CallDirection.outgoing,
        mediaType: mediaType,
        debugStatus: 'Подготавливаем звонок',
      ),
    );

    try {
      await waitForSignalingReady('исходящий звонок');
    } catch (error) {
      await failAndReset(error.toString());
      return;
    }

    emit(
      CallState(
        phase: CallPhase.outgoingRinging,
        callId: resolvedCallId,
        peerId: peerId,
        direction: CallDirection.outgoing,
        mediaType: mediaType,
        debugStatus: 'Отправляем приглашение на звонок',
      ),
    );

    setOutgoingTimeout(
      Timer(const Duration(seconds: 30), () {
        unawaited(endAndReset('Без ответа'));
      }),
    );

    final sanitizedInviteMetadata = Map<String, dynamic>.from(inviteMetadata)
      ..remove('callId')
      ..remove('signalScope')
      ..remove('mediaType');

    await sendSignal(peerId, 'call_invite', {
      'callId': resolvedCallId,
      'signalScope': 'call',
      'mediaType': mediaType.name,
      'videoCapable': true,
      ...sanitizedInviteMetadata,
    });
    log(
      'invite:sent peerId=$peerId callId=$resolvedCallId '
      'metadata=${sanitizedInviteMetadata.keys.join(",")}',
    );
  }

  void presentIncomingCallFromPush({
    required CallState currentState,
    required String peerId,
    required String callId,
    required CallMediaType mediaType,
    required bool Function({required String peerId, required String callId})
    isPendingRemoteEndedCall,
    required void Function() resetRuntimeTracking,
    required void Function(CallState state) emit,
    required void Function(String message) log,
  }) {
    if (currentState.isBusy) {
      return;
    }
    if (isPendingRemoteEndedCall(peerId: peerId, callId: callId)) {
      log('invite:push skip ended peerId=$peerId callId=$callId');
      return;
    }
    resetRuntimeTracking();
    emit(
      CallState(
        phase: CallPhase.incomingRinging,
        callId: callId,
        peerId: peerId,
        direction: CallDirection.incoming,
        mediaType: mediaType,
        debugStatus: 'Входящий звонок',
      ),
    );
    log(
      'invite:push peerId=$peerId callId=$callId mediaType=${mediaType.name}',
    );
  }

  Future<void> acceptIncomingCall({
    required CallState currentState,
    required void Function() resetRuntimeTracking,
    required void Function(CallState state) emit,
    required Future<void> Function(String purpose) waitForSignalingReady,
    required Future<void> Function() waitForRuntimeEnrichment,
    required CallCommandSignalSender sendSignal,
    required CallMediaType Function() getActiveMediaType,
    required void Function(String message) log,
  }) async {
    final peerId = currentState.peerId;
    final callId = currentState.callId;
    if (!currentState.isIncoming || peerId == null || callId == null) {
      return;
    }

    emit(
      currentState.copyWith(
        debugStatus: 'Подготавливаем runtime-конфиг перед ответом',
      ),
    );
    await waitForRuntimeEnrichment();
    emit(
      currentState.copyWith(
        debugStatus: 'Восстанавливаем signaling перед ответом',
      ),
    );
    resetRuntimeTracking();
    await waitForSignalingReady('ответ на звонок');

    await sendSignal(peerId, 'call_accept', {
      'callId': callId,
      'signalScope': 'call',
    });
    final connectingState = currentState.copyWith(
      phase: CallPhase.connecting,
      mediaType: getActiveMediaType(),
    );
    emit(connectingState);
    emit(
      connectingState.copyWith(
        debugStatus: 'Собеседник принял вызов, поднимаем video-capable сессию',
      ),
    );
    log('accept:sent peerId=$peerId callId=$callId');
  }

  Future<void> rejectIncomingCall({
    required CallState currentState,
    required CallDetachedSignalSender sendDetachedSignal,
    required Future<void> Function(String status) endAndReset,
  }) async {
    final peerId = currentState.peerId;
    final callId = currentState.callId;
    if (!currentState.isIncoming || peerId == null || callId == null) {
      return;
    }
    sendDetachedSignal(peerId, 'call_reject', {
      'callId': callId,
      'signalScope': 'call',
    }, purpose: 'отклонение звонка');
    await endAndReset('Отклонен');
  }

  Future<void> endCall({
    required CallState currentState,
    required CallDetachedSignalSender sendDetachedSignal,
    required Future<void> Function(String status) endAndReset,
  }) async {
    if (currentState.phase == CallPhase.ended ||
        currentState.phase == CallPhase.failed) {
      return;
    }
    final peerId = currentState.peerId;
    final callId = currentState.callId;
    if (peerId != null && callId != null) {
      sendDetachedSignal(peerId, 'call_end', {
        'callId': callId,
        'signalScope': 'call',
      }, purpose: 'завершение звонка');
    }
    final wasActiveCall =
        currentState.isActive ||
        currentState.recoveryReturnPhase == CallPhase.active;
    final status = wasActiveCall ? 'Завершен' : 'Отменен';
    await endAndReset(status);
  }

  Future<void> endCallFromRemotePush({
    required CallState currentState,
    required String peerId,
    required String callId,
    required void Function({required String peerId, required String callId})
    rememberPendingRemoteEndedCall,
    required Future<void> Function(String status) endAndReset,
  }) async {
    if ((currentState.phase == CallPhase.ended ||
            currentState.phase == CallPhase.failed) &&
        currentState.callId == callId &&
        currentState.peerId == peerId) {
      return;
    }
    if (currentState.callId != callId || currentState.peerId != peerId) {
      rememberPendingRemoteEndedCall(peerId: peerId, callId: callId);
      return;
    }
    if (currentState.isActive) {
      await endAndReset('Завершен');
    } else if (currentState.isIncoming) {
      await endAndReset('Пропущен');
    } else {
      await endAndReset('Без ответа');
    }
  }
}
