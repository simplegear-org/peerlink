import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'call_media_stream_controller.dart';
import 'call_sdp_utils.dart';

class CallPeerEventController {
  final SignalingService _signaling;
  final TurnAllocator? _turnAllocator;
  final CallMediaStreamController _mediaStreamController;
  final void Function(String message) _log;
  final RTCPeerConnection? Function() _getPeer;
  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final TransportMode? Function() _getMode;
  final int Function() _getSessionEpoch;
  final TurnCredentials? Function() _getActiveTurnCredentials;
  final void Function(bool connected) _setIceConnected;
  final void Function(bool active) _setRemoteTrackSeen;
  final void Function(bool active) _setRemoteAudioTrackSeen;
  final void Function(bool active) _setRemoteVideoTrackSeen;
  final void Function(String value) _setLastSignalingStateLabel;
  final void Function(String? trackId) _onRemoteVideoTrackChanged;
  final void Function() _notifyConnected;
  final void Function() _ensureAudioStatsPolling;
  final void Function() _armMediaFlowFallback;
  final void Function() _beginIceRecoveryFlowWatch;
  final void Function() _armPostIceRecoveryFlowWatch;
  final void Function() _cancelIceRecoveryTimers;
  final void Function() _armIceDisconnectedTimer;
  final void Function(String error) _armIceFailureState;

  const CallPeerEventController({
    required SignalingService signaling,
    required TurnAllocator? turnAllocator,
    required CallMediaStreamController mediaStreamController,
    required void Function(String message) log,
    required RTCPeerConnection? Function() getPeer,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required TransportMode? Function() getMode,
    required int Function() getSessionEpoch,
    required TurnCredentials? Function() getActiveTurnCredentials,
    required void Function(bool connected) setIceConnected,
    required void Function(bool active) setRemoteTrackSeen,
    required void Function(bool active) setRemoteAudioTrackSeen,
    required void Function(bool active) setRemoteVideoTrackSeen,
    required void Function(String value) setLastSignalingStateLabel,
    required void Function(String? trackId) onRemoteVideoTrackChanged,
    required void Function() notifyConnected,
    required void Function() ensureAudioStatsPolling,
    required void Function() armMediaFlowFallback,
    required void Function() beginIceRecoveryFlowWatch,
    required void Function() armPostIceRecoveryFlowWatch,
    required void Function() cancelIceRecoveryTimers,
    required void Function() armIceDisconnectedTimer,
    required void Function(String error) armIceFailureState,
  }) : _signaling = signaling,
       _turnAllocator = turnAllocator,
       _mediaStreamController = mediaStreamController,
       _log = log,
       _getPeer = getPeer,
       _getPeerId = getPeerId,
       _getCallId = getCallId,
       _getMode = getMode,
       _getSessionEpoch = getSessionEpoch,
       _getActiveTurnCredentials = getActiveTurnCredentials,
       _setIceConnected = setIceConnected,
       _setRemoteTrackSeen = setRemoteTrackSeen,
       _setRemoteAudioTrackSeen = setRemoteAudioTrackSeen,
       _setRemoteVideoTrackSeen = setRemoteVideoTrackSeen,
       _setLastSignalingStateLabel = setLastSignalingStateLabel,
       _onRemoteVideoTrackChanged = onRemoteVideoTrackChanged,
       _notifyConnected = notifyConnected,
       _ensureAudioStatsPolling = ensureAudioStatsPolling,
       _armMediaFlowFallback = armMediaFlowFallback,
       _beginIceRecoveryFlowWatch = beginIceRecoveryFlowWatch,
       _armPostIceRecoveryFlowWatch = armPostIceRecoveryFlowWatch,
       _cancelIceRecoveryTimers = cancelIceRecoveryTimers,
       _armIceDisconnectedTimer = armIceDisconnectedTimer,
       _armIceFailureState = armIceFailureState;

  void bind(RTCPeerConnection peer) {
    final expectedEpoch = _getSessionEpoch();
    bool isCurrentBinding() =>
        _getSessionEpoch() == expectedEpoch && identical(_getPeer(), peer);

    peer.onIceCandidate = (candidate) {
      if (!isCurrentBinding()) {
        return;
      }
      final peerId = _getPeerId();
      final callId = _getCallId();
      final mode = _getMode();
      if (peerId == null || callId == null || mode == null) {
        return;
      }
      _log(
        'ice:local type=${candidateType(candidate.candidate)} '
        'protocol=${candidateProtocol(candidate.candidate)} '
        'address=${candidateAddress(candidate.candidate)} '
        'mid=${candidate.sdpMid} mline=${candidate.sdpMLineIndex}',
      );
      _signaling.sendIce(peerId, {
        ...candidate.toMap(),
        'callId': callId,
        'signalScope': 'call',
        'transportMode': mode.name,
      });
    };

    peer.onIceGatheringState = (state) {
      if (!isCurrentBinding()) {
        return;
      }
      _log('iceGatheringState=$state');
    };

    peer.onConnectionState = (state) {
      if (!isCurrentBinding()) {
        return;
      }
      _log('peerConnectionState=$state');
    };

    peer.onSignalingState = (state) {
      if (!isCurrentBinding()) {
        return;
      }
      _setLastSignalingStateLabel(state.toString());
      _log('signalingState=$state');
    };

    peer.onIceConnectionState = (state) {
      if (!isCurrentBinding()) {
        return;
      }
      _log('iceState=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _setIceConnected(true);
        _armPostIceRecoveryFlowWatch();
        _notifyConnected();
        final creds = _getActiveTurnCredentials();
        if (creds != null) {
          _turnAllocator?.reportSuccess(creds.url);
        }
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        _setIceConnected(false);
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _setIceConnected(false);
        _beginIceRecoveryFlowWatch();
        _armIceFailureState('ICE connection failed');
        final creds = _getActiveTurnCredentials();
        _log(
          'diagnostic:warning ice failed action=grace-retry '
          'mode=${_getMode()?.name} turnUrl=${creds?.url} '
          'peerId=${_getPeerId()} callId=${_getCallId()}',
        );
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _setIceConnected(false);
        _beginIceRecoveryFlowWatch();
        _armIceDisconnectedTimer();
        final creds = _getActiveTurnCredentials();
        _log(
          'diagnostic:warning ice disconnected action=grace-watch '
          'mode=${_getMode()?.name} turnUrl=${creds?.url} '
          'peerId=${_getPeerId()} callId=${_getCallId()}',
        );
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _cancelIceRecoveryTimers();
        _setIceConnected(false);
      }
    };

    peer.onTrack = (event) {
      if (!isCurrentBinding()) {
        return;
      }
      _setRemoteTrackSeen(true);
      final kind = event.track.kind;
      final firstStream = event.streams.isNotEmpty ? event.streams.first : null;
      final streamVideoTracks = firstStream?.getVideoTracks() ?? const [];
      final streamPreferredVideoTrack =
          kind == 'video' && streamVideoTracks.isNotEmpty
          ? streamVideoTracks.last
          : null;
      final preferredTrack = streamPreferredVideoTrack ?? event.track;
      _log(
        'track:remote kind=$kind trackId=${event.track.id} '
        'preferredTrackId=${preferredTrack.id} '
        'enabled=${event.track.enabled} muted=${event.track.muted} '
        'streams=${event.streams.length} '
        'streamId=${firstStream?.id} '
        'streamAudio=${firstStream?.getAudioTracks().length ?? 0} '
        'streamVideo=${firstStream?.getVideoTracks().length ?? 0}',
      );
      if (kind == 'video') {
        _setRemoteVideoTrackSeen(true);
        _onRemoteVideoTrackChanged(preferredTrack.id);
      }
      if (event.streams.isNotEmpty) {
        unawaited(
          _mediaStreamController.ingestRemoteStream(
            event.streams.first,
            preferredTrack: preferredTrack,
          ),
        );
      } else {
        unawaited(_mediaStreamController.attachRemoteTrack(event.track));
      }
      if (kind == 'audio') {
        _setRemoteAudioTrackSeen(true);
        _ensureAudioStatsPolling();
        _armMediaFlowFallback();
      }
      _notifyConnected();
    };

    peer.onAddStream = (stream) {
      if (!isCurrentBinding()) {
        return;
      }
      _setRemoteTrackSeen(true);
      _log(
        'stream:remote added id=${stream.id} '
        'audio=${stream.getAudioTracks().length} '
        'video=${stream.getVideoTracks().length} '
        'audioIds=${stream.getAudioTracks().map((track) => track.id).join(",")} '
        'videoIds=${stream.getVideoTracks().map((track) => track.id).join(",")}',
      );
      if (stream.getVideoTracks().isNotEmpty) {
        unawaited(_mediaStreamController.ingestRemoteStream(stream));
      }
      if (stream.getAudioTracks().isNotEmpty) {
        _setRemoteAudioTrackSeen(true);
        _armMediaFlowFallback();
      }
      _ensureAudioStatsPolling();
      _notifyConnected();
    };
  }
}
