import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import 'audio_call_peer.dart';
import 'call_models.dart';

typedef CallPeerBestEffortSender =
    Future<void> Function(
      String peerId,
      String type,
      Map<String, dynamic> data, {
      required String purpose,
    });

class CallPeerBindingHelper {
  const CallPeerBindingHelper();

  AudioCallPeer createPeer({
    required String localPeerId,
    required SignalingService signaling,
    required TurnAllocator? turnAllocator,
    required String peerId,
    required String callId,
    required bool Function(AudioCallPeer peer, String peerId, String callId)
    isCurrentPeerInstance,
    required CallState Function() getState,
    required void Function() cancelConnectAttemptTimeout,
    required String Function(TransportMode mode) transportLabelFor,
    required void Function(CallState state) emit,
    required void Function() markLocalMediaReady,
    required void Function() markRemoteMediaTimeoutHandled,
    required void Function() updateActiveState,
    required void Function() armMediaReadyTimeout,
    required void Function({required bool recovering, required String status})
    handleIceRecoveryState,
    required CallPeerBestEffortSender sendBestEffortSignal,
    required void Function({required int sentBytes, required int receivedBytes})
    applyStats,
    required bool Function(MediaStream? stream) streamHasVideo,
    required bool Function() getTurnFallbackAttempted,
    required Future<void> Function({
      required String peerId,
      required String callId,
      required String reason,
    })
    retryViaTurn,
    required Future<void> Function(String error) failAndReset,
  }) {
    late final AudioCallPeer peer;
    peer = AudioCallPeer(
      localPeerId: localPeerId,
      signaling: signaling,
      turnAllocator: turnAllocator,
      onConnected: (mode) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        cancelConnectAttemptTimeout();
        emit(
          getState().copyWith(
            transportMode: mode,
            transportLabel: transportLabelFor(mode),
            debugStatus: mode == TransportMode.turn
                ? 'Транспорт через TURN готов, аудио уже поднимается, видеоканал подготовлен'
                : 'Прямой транспорт готов, аудио уже поднимается, видеоканал подготовлен',
          ),
        );
        updateActiveState();
        armMediaReadyTimeout();
      },
      onMediaFlow: () async {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        markLocalMediaReady();
        updateActiveState();
        final currentState = getState();
        final currentPeerId = currentState.peerId;
        final currentCallId = currentState.callId;
        if (currentPeerId != null && currentCallId != null) {
          await sendBestEffortSignal(currentPeerId, 'call_media_ready', {
            'callId': currentCallId,
            'signalScope': 'call',
          }, purpose: 'подтверждение аудио');
          armMediaReadyTimeout();
        }
      },
      onStats: ({required int sentBytes, required int receivedBytes}) {
        if (!isCurrentPeerInstance(peer, peerId, callId) || getState().isIdle) {
          return;
        }
        applyStats(sentBytes: sentBytes, receivedBytes: receivedBytes);
      },
      onMediaTypeChanged: (mediaType) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        emit(
          getState().copyWith(
            mediaType: mediaType,
            localVideoEnabled: mediaType == CallMediaType.video,
          ),
        );
      },
      onLocalStream: (stream) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        emit(
          getState().copyWith(
            localStream: stream,
            localVideoAvailable: streamHasVideo(stream),
            isFrontCamera: peer.isFrontCamera,
          ),
        );
      },
      onRemoteStream: (stream) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        final state = getState();
        final remoteVideoAvailable = streamHasVideo(stream);
        emit(
          state.copyWith(
            remoteStream: stream,
            remoteVideoAvailable: remoteVideoAvailable,
            remoteVideoActive: remoteVideoAvailable && state.remoteVideoEnabled
                ? true
                : (remoteVideoAvailable ? state.remoteVideoActive : false),
          ),
        );
      },
      onRemoteVideoFlowChanged: (active) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        final state = getState();
        emit(
          state.copyWith(
            remoteVideoActive: active,
            debugStatus: active
                ? 'Собеседник передает видео'
                : (state.remoteVideoEnabled
                      ? 'Ожидаем видеопоток'
                      : state.debugStatus),
          ),
        );
      },
      onRemoteVideoTrackChanged: (trackId) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        emit(
          getState().copyWith(
            remoteVideoTrackId: trackId,
            clearRemoteVideoTrackId: trackId == null,
          ),
        );
      },
      onVideoCodecChanged: (codec) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        emit(
          getState().copyWith(
            videoCodec: codec,
            clearVideoCodec: codec == null || codec.isEmpty,
          ),
        );
      },
      onIceRecoveryStateChanged:
          ({required bool recovering, required String status}) {
            if (!isCurrentPeerInstance(peer, peerId, callId)) {
              return;
            }
            handleIceRecoveryState(recovering: recovering, status: status);
          },
      onError: (error) {
        if (!isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        if (getState().phase != CallPhase.active &&
            getState().transportMode != TransportMode.turn &&
            !getTurnFallbackAttempted() &&
            turnAllocator?.allocate() != null) {
          unawaited(
            retryViaTurn(peerId: peerId, callId: callId, reason: error),
          );
          return;
        }
        markRemoteMediaTimeoutHandled();
        unawaited(failAndReset(error));
      },
    );
    return peer;
  }
}
