import '../signaling/signaling_message.dart';
import '../transport/transport_mode.dart';
import 'call_models.dart';

typedef CallRouterSendSignal =
    Future<void> Function(
      String peerId,
      String type,
      Map<String, dynamic> data,
    );

class CallControlSignalRouter {
  const CallControlSignalRouter({
    required this.sendSignal,
    required this.isPendingRemoteEndedCall,
    required this.rememberPendingRemoteEndedCall,
    required this.parseMediaType,
    required this.cancelOutgoingTimeout,
    required this.emit,
    required this.log,
    required this.endAndReset,
    required this.applyInviteRuntimeMetadata,
    required this.preferredInitialMode,
    required this.startPeerConnection,
    required this.onRemoteMediaReady,
    required this.onRemoteHeartbeat,
    required this.onRemoteAudioMuteState,
    required this.onRemoteVideoState,
    required this.onRemoteVideoStateAck,
    required this.onRemoteVideoFlowAck,
  });

  final CallRouterSendSignal sendSignal;
  final bool Function({required String peerId, required String callId})
  isPendingRemoteEndedCall;
  final void Function({required String peerId, required String callId})
  rememberPendingRemoteEndedCall;
  final CallMediaType Function(Object? raw) parseMediaType;
  final void Function() cancelOutgoingTimeout;
  final void Function(CallState state) emit;
  final void Function(String message) log;
  final Future<void> Function(String status) endAndReset;
  final Future<void> Function(Map<String, dynamic> data)
  applyInviteRuntimeMetadata;
  final Future<TransportMode> Function() preferredInitialMode;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required TransportMode initialMode,
  })
  startPeerConnection;
  final Future<void> Function({required String peerId, required String callId})
  onRemoteMediaReady;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required int seq,
    required int sentAtMs,
  })
  onRemoteHeartbeat;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required bool muted,
    required int version,
  })
  onRemoteAudioMuteState;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required bool enabled,
    required int version,
  })
  onRemoteVideoState;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required bool enabled,
    required int version,
  })
  onRemoteVideoStateAck;
  final Future<void> Function({
    required String peerId,
    required String callId,
    required int version,
  })
  onRemoteVideoFlowAck;

  Future<bool> handle({
    required CallState currentState,
    required SignalingMessage message,
  }) async {
    final peerId = message.fromPeerId;
    final data = message.data;
    final callId = data['callId']?.toString();
    if (callId == null || callId.isEmpty) {
      return false;
    }

    switch (message.type) {
      case 'call_invite':
        if (currentState.isIncoming &&
            currentState.callId == callId &&
            currentState.peerId == peerId) {
          log('invite:ignore duplicate peerId=$peerId callId=$callId');
          return true;
        }
        if (currentState.isBusy) {
          await sendSignal(peerId, 'call_busy', {
            'callId': callId,
            'signalScope': 'call',
          });
          return true;
        }
        if (isPendingRemoteEndedCall(peerId: peerId, callId: callId)) {
          log('invite:signal skip ended peerId=$peerId callId=$callId');
          return true;
        }
        await applyInviteRuntimeMetadata(data);
        final incomingMediaType = parseMediaType(data['mediaType']);
        emit(
          CallState(
            phase: CallPhase.incomingRinging,
            callId: callId,
            peerId: peerId,
            direction: CallDirection.incoming,
            mediaType: incomingMediaType,
            debugStatus: 'Входящий звонок',
          ),
        );
        log('invite:recv peerId=$peerId callId=$callId');
        return true;
      case 'call_accept':
        if (currentState.phase != CallPhase.outgoingRinging ||
            currentState.callId != callId ||
            currentState.peerId != peerId) {
          log(
            'accept:ignored peerId=$peerId callId=$callId '
            'currentPeerId=${currentState.peerId} currentCallId=${currentState.callId} '
            'phase=${currentState.phase.name}',
          );
          return true;
        }
        cancelOutgoingTimeout();
        final preferredMode = await preferredInitialMode();
        emit(
          currentState.copyWith(
            phase: CallPhase.connecting,
            mediaType: currentState.mediaType,
            debugStatus: 'Собеседник принял вызов, используем TURN',
          ),
        );
        await startPeerConnection(
          peerId: peerId,
          callId: callId,
          initialMode: preferredMode,
        );
        return true;
      case 'call_reject':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          log(
            'reject:ignored peerId=$peerId callId=$callId '
            'currentPeerId=${currentState.peerId} currentCallId=${currentState.callId} '
            'phase=${currentState.phase.name}',
          );
          return true;
        }
        if (currentState.phase == CallPhase.ended ||
            currentState.phase == CallPhase.failed) {
          return true;
        }
        await endAndReset('Отклонен');
        return true;
      case 'call_busy':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          log(
            'busy:ignored peerId=$peerId callId=$callId '
            'currentPeerId=${currentState.peerId} currentCallId=${currentState.callId} '
            'phase=${currentState.phase.name}',
          );
          return true;
        }
        if (currentState.phase == CallPhase.ended ||
            currentState.phase == CallPhase.failed) {
          return true;
        }
        await endAndReset('Занят');
        return true;
      case 'call_end':
        if (currentState.callId == callId && currentState.peerId == peerId) {
          rememberPendingRemoteEndedCall(peerId: peerId, callId: callId);
          if (currentState.phase == CallPhase.ended ||
              currentState.phase == CallPhase.failed) {
            return true;
          }
          await endAndReset(_remoteEndStatus(currentState));
        } else {
          log(
            'end:remember foreign peerId=$peerId callId=$callId '
            'currentPeerId=${currentState.peerId} currentCallId=${currentState.callId} '
            'phase=${currentState.phase.name}',
          );
          rememberPendingRemoteEndedCall(peerId: peerId, callId: callId);
        }
        return true;
      case 'call_media_ready':
        if (currentState.callId == callId && currentState.peerId == peerId) {
          log('mediaReady:recv peerId=$peerId callId=$callId');
          await onRemoteMediaReady(peerId: peerId, callId: callId);
        } else {
          log(
            'mediaReady:ignored peerId=$peerId callId=$callId '
            'currentPeerId=${currentState.peerId} currentCallId=${currentState.callId}',
          );
        }
        return true;
      case 'call_heartbeat':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          return true;
        }
        await onRemoteHeartbeat(
          peerId: peerId,
          callId: callId,
          seq: _parseVersion(message.data['seq']),
          sentAtMs: _parseVersion(message.data['sentAtMs']),
        );
        return true;
      case 'call_audio_mute_state':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          log(
            'audioMute:ignored peerId=$peerId callId=$callId '
            'currentPeerId=${currentState.peerId} currentCallId=${currentState.callId}',
          );
          return true;
        }
        await onRemoteAudioMuteState(
          peerId: peerId,
          callId: callId,
          muted: message.data['muted'] == true,
          version: _parseVersion(message.data['version']),
        );
        return true;
      case 'call_video_state':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          return true;
        }
        await onRemoteVideoState(
          peerId: peerId,
          callId: callId,
          enabled: message.data['enabled'] == true,
          version: _parseVersion(message.data['version']),
        );
        return true;
      case 'call_video_mute_state':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          return true;
        }
        await onRemoteVideoState(
          peerId: peerId,
          callId: callId,
          enabled: message.data['muted'] != true,
          version: _parseVersion(message.data['version']),
        );
        return true;
      case 'call_video_state_ack':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          return true;
        }
        await onRemoteVideoStateAck(
          peerId: peerId,
          callId: callId,
          enabled: message.data['enabled'] == true,
          version: _parseVersion(message.data['version']),
        );
        return true;
      case 'call_video_flow_ack':
        if (currentState.callId != callId || currentState.peerId != peerId) {
          return true;
        }
        await onRemoteVideoFlowAck(
          peerId: peerId,
          callId: callId,
          version: _parseVersion(message.data['version']),
        );
        return true;
      default:
        return false;
    }
  }

  String _remoteEndStatus(CallState currentState) {
    if (currentState.isActive) {
      return 'Завершен';
    }
    if (currentState.isIncoming) {
      return 'Пропущен';
    }
    return 'Без ответа';
  }

  int _parseVersion(Object? raw) {
    if (raw is int) {
      return raw;
    }
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}
