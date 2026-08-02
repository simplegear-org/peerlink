import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'call_camera_flip_controller.dart';
import 'call_connection_state_controller.dart';
import 'call_media_flow_controller.dart';
import 'call_local_media_controller.dart';
import 'call_local_audio_outbound_refresher.dart';
import 'call_media_stream_controller.dart';
import 'call_media_stats_utils.dart';
import 'call_models.dart';
import 'call_negotiation_controller.dart';
import 'call_peer_event_controller.dart';
import 'call_peer_runtime_snapshot.dart';
import 'call_peer_session_controller.dart';
import 'call_renegotiation_orchestrator.dart';
import 'call_remote_audio_mute_controller.dart';
import 'call_recovery_coordinator.dart';
import 'call_recovery_stats_tracker.dart';
import 'call_sdp_utils.dart';
import 'call_session_epoch.dart';
import 'call_signal_transition_serializer.dart';
import 'call_video_controller.dart';
import 'call_video_state.dart';
import 'call_runtime_logger.dart';

class AudioCallPeer {
  final SignalingService _signaling;
  final TurnAllocator? _turnAllocator;
  final void Function(TransportMode mode) _onConnected;
  final Future<void> Function() _onMediaFlow;
  final void Function(CallMediaType mediaType) _onMediaTypeChanged;
  final void Function(MediaStream stream) _onLocalStream;
  final void Function(MediaStream stream) _onRemoteStream;
  final void Function(bool active) _onRemoteVideoFlowChanged;
  final void Function(String? trackId) _onRemoteVideoTrackChanged;
  final void Function(String? codec) _onVideoCodecChanged;
  final void Function({required bool recovering, required String status})
  _onIceRecoveryStateChanged;
  final void Function({required int sentBytes, required int receivedBytes})
  _onStats;
  final void Function(String error) _onError;
  late final CallMediaFlowController _mediaFlowController;
  late final CallConnectionStateController _connectionStateController;
  late final CallLocalMediaController _localMediaController;
  late final CallNegotiationController _negotiationController;
  late final CallPeerEventController _peerEventController;
  late final CallPeerSessionController _peerSessionController;
  late final CallRecoveryCoordinator _recoveryCoordinator;
  late final CallVideoController _videoController;
  late final CallMediaStreamController _mediaStreamController;
  late final CallCameraFlipController _cameraFlipController;
  late final CallRenegotiationOrchestrator _renegotiationOrchestrator;
  late final CallSignalTransitionSerializer _signalTransitionSerializer;
  late final CallPeerRuntimeSnapshot _runtimeSnapshot;
  late final CallRecoveryStatsTracker _recoveryStatsTracker;
  late final CallLocalAudioOutboundRefresher _localAudioOutboundRefresher;
  late final CallRemoteAudioMuteController _remoteAudioMuteController;

  RTCPeerConnection? _peer;
  String? _peerId;
  String? _callId;
  TransportMode? _mode;
  CallMediaType _mediaType = CallMediaType.audio;
  final List<RTCIceCandidate> _pendingIce = <RTCIceCandidate>[];
  bool _remoteDescriptionSet = false;
  bool _iceConnected = false;
  TurnCredentials? _activeTurnCredentials;
  bool _remoteTrackSeen = false;
  bool _remoteAudioTrackSeen = false;
  bool _remoteAudioFlowSeen = false;
  bool _remoteAudioMuted = false;
  bool _remoteVideoTrackSeen = false;
  final CallVideoState _videoState = CallVideoState();
  bool _connected = false;
  bool _mediaFlowNotified = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _startedAsOfferer = false;
  String _lastSignalingStateLabel = 'unknown';
  CallSessionEpoch _sessionEpoch = CallSessionEpoch.initial();
  late final CallRuntimeLogger _logger;

  AudioCallPeer({
    required String localPeerId,
    required SignalingService signaling,
    required TurnAllocator? turnAllocator,
    required void Function(TransportMode mode) onConnected,
    required Future<void> Function() onMediaFlow,
    required void Function(CallMediaType mediaType) onMediaTypeChanged,
    required void Function(MediaStream stream) onLocalStream,
    required void Function(MediaStream stream) onRemoteStream,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required void Function(String? trackId) onRemoteVideoTrackChanged,
    required void Function(String? codec) onVideoCodecChanged,
    required void Function({required bool recovering, required String status})
    onIceRecoveryStateChanged,
    required void Function({required int sentBytes, required int receivedBytes})
    onStats,
    required void Function(String error) onError,
    bool Function()? hasLocalVideoForFlipOverride,
    Future<bool> Function()? canExecuteCameraFlipOverride,
    Future<void> Function()? performCameraFlipOverride,
  }) : _signaling = signaling,
       _turnAllocator = turnAllocator,
       _onConnected = onConnected,
       _onMediaFlow = onMediaFlow,
       _onMediaTypeChanged = onMediaTypeChanged,
       _onLocalStream = onLocalStream,
       _onRemoteStream = onRemoteStream,
       _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
       _onRemoteVideoTrackChanged = onRemoteVideoTrackChanged,
       _onVideoCodecChanged = onVideoCodecChanged,
       _onIceRecoveryStateChanged = onIceRecoveryStateChanged,
       _onStats = onStats,
       _onError = onError {
    _logger = CallRuntimeLogger(
      channel: 'call_peer',
      getOwnerId: () {
        final peer = _peerId;
        return peer == null || peer.isEmpty ? 'unknown' : peer;
      },
      getContext: () => (
        peerId: _peerId,
        callId: _callId,
        epoch: _sessionEpoch.value,
        role: _startedAsOfferer ? 'offerer' : 'answerer',
        mediaType: _mediaType,
        transportMode: _mode,
        phase: null,
        signalingState: _lastSignalingStateLabel,
      ),
    );
    _signalTransitionSerializer = CallSignalTransitionSerializer(
      log: _log,
      logPrefix: 'signal-transition',
      onAfterTransition: () {
        _cameraFlipController.scheduleQueuedRetry();
      },
    );
    _runtimeSnapshot = CallPeerRuntimeSnapshot(
      hasPeer: () => _peer != null,
      getConnected: () => _connected,
      getIceConnected: () => _iceConnected,
      getMediaType: () => _mediaType,
      getMuted: () => _muted,
      getRemoteAudioTrackSeen: () => _remoteAudioTrackSeen,
      getRemoteAudioFlowSeen: () => _remoteAudioFlowSeen,
      getRemoteAudioMuted: () => _remoteAudioMuted,
      getRemoteVideoTrackSeen: () => _remoteVideoTrackSeen,
      getRemoteVideoEnabled: () => _remoteVideoEnabled,
      getRemoteVideoFlowSeen: () => _remoteVideoFlowSeen,
      getRenegotiationInProgress: () => _renegotiationOrchestrator.inProgress,
      getSignalingStateLabel: () => _lastSignalingStateLabel,
      getTransportMode: () => _mode,
    );
    _recoveryStatsTracker = CallRecoveryStatsTracker();
    _recoveryCoordinator = CallRecoveryCoordinator(
      log: _log,
      onRecoveryStateChanged: _onIceRecoveryStateChanged,
      onFatal: _onError,
    );
    _mediaStreamController = CallMediaStreamController(
      log: _log,
      onLocalStream: _onLocalStream,
      onRemoteStream: _onRemoteStream,
    );
    _connectionStateController = CallConnectionStateController(
      log: _log,
      getMode: () => _mode,
      getConnected: () => _connected,
      setConnected: (value) => _connected = value,
      getIceConnected: () => _iceConnected,
      getRemoteTrackSeen: () => _remoteTrackSeen,
      getRemoteAudioFlowSeen: () => _remoteAudioFlowSeen,
      onConnected: _onConnected,
      armMediaFlowFallback: () => _mediaFlowController.armMediaFlowFallback(),
    );
    _mediaFlowController = CallMediaFlowController(
      signaling: _signaling,
      log: _log,
      getPeer: () => _peer,
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getIceConnected: () => _iceConnected,
      getIceRecoveryInProgress: () => false,
      getLocalAudioMuted: () => _muted,
      getRemoteAudioMuted: () => _remoteAudioMuted,
      getRemoteAudioTrackSeen: () => _remoteAudioTrackSeen,
      getRemoteVideoTrackSeen: () => _remoteVideoTrackSeen,
      getRemoteAudioFlowSeen: () => _remoteAudioFlowSeen,
      setRemoteAudioFlowSeen: (value) => _remoteAudioFlowSeen = value,
      getRemoteVideoEnabled: () => _remoteVideoEnabled,
      getRemoteVideoFlowSeen: () => _remoteVideoFlowSeen,
      setRemoteVideoFlowSeen: (value) => _remoteVideoFlowSeen = value,
      markRemoteVideoFlowDetected: () {
        _videoController.markRemoteVideoFlowDetected();
      },
      getPendingRemoteVideoFlowAckVersion: () =>
          _pendingRemoteVideoFlowAckVersion,
      setPendingRemoteVideoFlowAckVersion: (value) =>
          _pendingRemoteVideoFlowAckVersion = value,
      getMediaFlowNotified: () => _mediaFlowNotified,
      setMediaFlowNotified: (value) => _mediaFlowNotified = value,
      notifyConnected: _connectionStateController.notifyConnected,
      onMediaFlow: _onMediaFlow,
      onRemoteVideoFlowChanged: _onRemoteVideoFlowChanged,
      onIceMediaRecoveryCompleted: () {
        _negotiationController.cancelIceRecoveryTimers();
      },
      onIceReconnectStalled: (reason) {
        return observeRecovery(
          CallRecoveryObservation(
            kind: CallRecoveryObservationKind.postIceRecoveryFlowStalled,
            reason: reason,
          ),
        );
      },
      onPostIceRecoveryFlowStalled: (reason) {
        return observeRecovery(
          CallRecoveryObservation(
            kind: CallRecoveryObservationKind.postIceRecoveryFlowStalled,
            reason: reason,
          ),
        );
      },
      onPostIceRecoveryVideoOnlyStalled: _fallbackToAudioOnlyAfterVideoStall,
      onLiveMediaFlowStalled: (reason) {
        return observeRecovery(
          CallRecoveryObservation(
            kind: CallRecoveryObservationKind.liveMediaFlowStalled,
            reason: reason,
          ),
        );
      },
      onLocalAudioOutboundStalled: _refreshLocalAudioOutbound,
      onStats: ({required sentBytes, required receivedBytes}) {
        _onStats(sentBytes: sentBytes, receivedBytes: receivedBytes);
      },
      onRecoveryStats: _recordRecoveryMediaStats,
      getSessionEpoch: () => _sessionEpoch.value,
      onVideoNetworkStats: ({required stats, required outboundKbps}) {
        return _videoController.handleNetworkStats(
          stats: stats,
          outboundKbps: outboundKbps,
        );
      },
    );
    _negotiationController = CallNegotiationController(
      signaling: _signaling,
      turnAllocator: _turnAllocator,
      log: _log,
      onVideoCodecChanged: _onVideoCodecChanged,
      rewriteVideoCodecs: preferVideoCodecsInSdp,
      extractVideoCodec: extractPreferredVideoCodec,
      onTurnCredentialsAllocated: (creds) => _activeTurnCredentials = creds,
      captureExpectedVideoMidsForLocalOffer: (sdp) {
        _videoController.captureExpectedVideoMidsForLocalOffer(sdp);
      },
      getPeer: () => _peer,
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getMode: () => _mode,
      getMediaType: () => _mediaType,
      getConnected: () => _connected,
      getRemoteDescriptionSet: () => _remoteDescriptionSet,
      observeRecovery: observeRecovery,
    );
    _videoController = CallVideoController(
      signaling: _signaling,
      mediaStreamController: _mediaStreamController,
      state: _videoState,
      log: _log,
      extractVideoMids: extractVideoMids,
      onRemoteVideoFlowChanged: _onRemoteVideoFlowChanged,
      onRemoteVideoFlowStalled: (reason) {
        return observeRecovery(
          CallRecoveryObservation(
            kind: CallRecoveryObservationKind.remoteVideoFlowStalled,
            reason: reason,
          ),
        );
      },
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getStartedAsOfferer: () => _startedAsOfferer,
      getMediaType: () => _mediaType,
      getLocalVideoTrackAttached: () => _localVideoTrackAttached,
      getPeer: () => _peer,
      getSessionEpoch: () => _sessionEpoch.value,
    );
    _localMediaController = CallLocalMediaController(
      mediaStreamController: _mediaStreamController,
      log: _log,
      onMediaTypeChanged: _onMediaTypeChanged,
      getPeer: () => _peer,
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getMediaType: () => _mediaType,
      setMediaType: (value) => _mediaType = value,
      getLocalVideoTrackAttached: () => _localVideoTrackAttached,
      getVideoSendSender: () => _videoSendSender,
      getVideoSendTransceiver: () => _videoSendTransceiver,
      getVideoReceiveTransceiver: () => _videoReceiveTransceiver,
      ensureVideoTransceiversReady: () {
        return _videoController.ensureVideoTransceiversReady();
      },
      requestRenegotiation: (reason) {
        return forceRenegotiation(reason);
      },
      sendVideoState:
          ({
            required bool enabled,
            required String peerId,
            required String callId,
          }) {
            return _videoController.sendVideoState(
              enabled: enabled,
              peerId: peerId,
              callId: callId,
            );
          },
      cancelVideoUplinkFallback: () {
        _videoController.cancelVideoUplinkFallback();
      },
      videoController: _videoController,
    );
    _localAudioOutboundRefresher = CallLocalAudioOutboundRefresher(
      log: _log,
      getMuted: () => _muted,
      getPeer: () => _peer,
      runtimeSnapshot: _callRuntimeSnapshot,
      refreshLocalAudioSender: _mediaStreamController.refreshLocalAudioSender,
    );
    _remoteAudioMuteController = CallRemoteAudioMuteController(
      log: _log,
      setRemoteAudioMuted: (value) => _remoteAudioMuted = value,
      setRemoteAudioFlowSeen: (value) => _remoteAudioFlowSeen = value,
      runtimeSnapshot: _callRuntimeSnapshot,
    );
    _cameraFlipController = CallCameraFlipController(
      log: _log,
      getMediaType: () => _mediaType,
      hasLocalVideo: () {
        final override = hasLocalVideoForFlipOverride;
        if (override != null) {
          return override();
        }
        final videoTracks =
            _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
        return videoTracks.isNotEmpty;
      },
      canExecute: () async {
        final override = canExecuteCameraFlipOverride;
        if (override != null) {
          return override();
        }
        final peer = _peer;
        if (peer == null) {
          return true;
        }
        final signalingState = await peer.getSignalingState();
        return signalingState == RTCSignalingState.RTCSignalingStateStable &&
            !_renegotiationOrchestrator.inProgress;
      },
      performFlip: () async {
        final override = performCameraFlipOverride;
        if (override != null) {
          await override();
          return;
        }
        await _localMediaController.flipCamera();
        if (_mediaType == CallMediaType.video) {
          await _videoController.syncLocalMediaTracks();
          await _videoController.refreshVideoChannelHandles();
        }
      },
      getRenegotiationInProgress: () => _renegotiationOrchestrator.inProgress,
      getSignalingStateLabel: () => _lastSignalingStateLabel,
    );
    _renegotiationOrchestrator = CallRenegotiationOrchestrator(
      log: _log,
      runRenegotiation: _negotiationController.runRenegotiation,
    );
    _peerEventController = CallPeerEventController(
      signaling: _signaling,
      turnAllocator: _turnAllocator,
      mediaStreamController: _mediaStreamController,
      log: _log,
      getPeer: () => _peer,
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getMode: () => _mode,
      getSessionEpoch: () => _sessionEpoch.value,
      getActiveTurnCredentials: () => _activeTurnCredentials,
      setIceConnected: (value) => _iceConnected = value,
      setRemoteTrackSeen: (value) => _remoteTrackSeen = value,
      setRemoteAudioTrackSeen: (value) => _remoteAudioTrackSeen = value,
      setRemoteVideoTrackSeen: (value) => _remoteVideoTrackSeen = value,
      setLastSignalingStateLabel: (value) => _lastSignalingStateLabel = value,
      onRemoteVideoTrackChanged: _onRemoteVideoTrackChanged,
      notifyConnected: _connectionStateController.notifyConnected,
      ensureAudioStatsPolling: () {
        _mediaFlowController.ensureAudioStatsPolling();
      },
      armMediaFlowFallback: () {
        _mediaFlowController.armMediaFlowFallback();
      },
      beginIceRecoveryFlowWatch: () {
        _mediaFlowController.beginIceRecoveryFlowWatch();
      },
      armPostIceRecoveryFlowWatch: () {
        _mediaFlowController.armPostIceRecoveryFlowWatch();
      },
      cancelIceRecoveryTimers: () {
        _negotiationController.cancelIceRecoveryTimers();
      },
      armIceDisconnectedTimer: () {
        _negotiationController.armIceDisconnectedTimer();
      },
      armIceFailureState: (error) {
        _negotiationController.armIceFailureState(error);
      },
    );
    _peerSessionController = CallPeerSessionController(
      signaling: _signaling,
      videoState: _videoState,
      log: _log,
      onError: _onError,
      onRemoteVideoTrackChanged: _onRemoteVideoTrackChanged,
      onVideoCodecChanged: _onVideoCodecChanged,
      getPeer: () => _peer,
      setPeer: (peer) => _peer = peer,
      setPeerId: (value) => _peerId = value,
      setCallId: (value) => _callId = value,
      getMode: () => _mode,
      setMode: (value) => _mode = value,
      getMediaType: () => _mediaType,
      setMediaType: (value) => _mediaType = value,
      setStartedAsOfferer: (value) => _startedAsOfferer = value,
      getRemoteDescriptionSet: () => _remoteDescriptionSet,
      setRemoteDescriptionSet: (value) => _remoteDescriptionSet = value,
      setIceConnected: (value) => _iceConnected = value,
      setRemoteTrackSeen: (value) => _remoteTrackSeen = value,
      setRemoteAudioTrackSeen: (value) => _remoteAudioTrackSeen = value,
      setRemoteAudioFlowSeen: (value) => _remoteAudioFlowSeen = value,
      setRemoteVideoTrackSeen: (value) => _remoteVideoTrackSeen = value,
      setConnected: (value) => _connected = value,
      setMediaFlowNotified: (value) => _mediaFlowNotified = value,
      setRenegotiationInProgress: _renegotiationOrchestrator.setInProgress,
      setPendingRenegotiationReason:
          _renegotiationOrchestrator.setPendingReason,
      getPendingIce: () => _pendingIce,
      setPendingRemoteVideoFlowAckVersion: (value) =>
          _pendingRemoteVideoFlowAckVersion = value,
      setRemoteVideoEnabled: (value) => _remoteVideoEnabled = value,
      setRemoteVideoFlowSeen: (value) => _remoteVideoFlowSeen = value,
      mediaStreamController: _mediaStreamController,
      buildRtcConfig: _negotiationController.buildRtcConfig,
      bindPeerEvents: _peerEventController.bind,
      getMuted: () => _muted,
      getSpeakerOn: () => _speakerOn,
      getStartedAsOfferer: () => _startedAsOfferer,
      applySpeakerOn: _localMediaController.applySpeakerOn,
      syncLocalMediaTracks: _videoController.syncLocalMediaTracks,
      refreshVideoChannelHandles: _videoController.refreshVideoChannelHandles,
      ensureVideoTransceiverDirectionsForRole:
          _videoController.ensureVideoTransceiverDirectionsForRole,
      withPreferredVideoCodecs: _negotiationController.withPreferredVideoCodecs,
      captureExpectedVideoMidsForLocalOffer:
          _videoController.captureExpectedVideoMidsForLocalOffer,
      captureExpectedVideoMidsForRemoteOffer:
          _videoController.captureExpectedVideoMidsForRemoteOffer,
      captureExpectedVideoMidsForRemoteAnswer:
          _videoController.captureExpectedVideoMidsForRemoteAnswer,
      updateNegotiatedVideoCodec:
          _negotiationController.updateNegotiatedVideoCodec,
      armPostIceRecoveryFlowWatch: () {
        _mediaFlowController.armPostIceRecoveryFlowWatch();
      },
      resetPostIceRecoveryFlowWatch: (reason) {
        _mediaFlowController.resetPostIceRecoveryFlowWatch(reason: reason);
      },
      stopAudioStatsPolling: _mediaFlowController.stopAudioStatsPolling,
      cancelMediaFlowFallback: _mediaFlowController.cancelMediaFlowFallback,
      cancelIceRecoveryTimers: _negotiationController.cancelIceRecoveryTimers,
      cancelVideoUplinkFallback: _videoController.cancelVideoUplinkFallback,
      cancelRemoteVideoFlowRecovery:
          _videoController.cancelRemoteVideoFlowRecovery,
      cancelPendingVideoStateAck: _videoController.cancelPendingVideoStateAck,
      cancelVideoQualityUpgrade: _videoController.cancelVideoQualityUpgrade,
      disposeRemoteStream: _mediaStreamController.disposeRemoteStream,
      clearRemoteRenderStreamTracks:
          _mediaStreamController.clearRemoteRenderStreamTracks,
      resetLocalVideoAttachment:
          _mediaStreamController.resetLocalVideoAttachment,
      closePeer: () async {
        final peer = _peer;
        if (peer == null) {
          return;
        }
        try {
          await peer.close();
        } catch (_) {}
        try {
          await peer.dispose();
        } catch (_) {}
      },
      clearVideoTransports: () {
        _videoSendSender = null;
        _videoSendTransceiver = null;
        _videoReceiveTransceiver = null;
        _videoState.expectedVideoSendMid = null;
        _videoState.expectedVideoReceiveMid = null;
        _activeTurnCredentials = null;
      },
      parseMode: _parseMode,
      bumpSessionEpoch: _bumpSessionEpoch,
    );
  }

  void _bumpSessionEpoch() {
    _sessionEpoch = _sessionEpoch.next();
    _lastSignalingStateLabel = 'unknown';
    _recoveryStatsTracker.reset();
    _recoveryCoordinator.reset();
  }

  void _recordRecoveryMediaStats(AudioTrafficStats stats) {
    if (!_recoveryStatsTracker.recordInboundAdvanced(stats)) {
      return;
    }
    unawaited(
      observeRecovery(
        const CallRecoveryObservation(
          kind: CallRecoveryObservationKind.mediaAdvanced,
          reason: 'inbound stats advanced',
        ),
      ),
    );
  }

  bool get isMuted => _muted;
  bool get speakerOn => _speakerOn;
  bool get isFrontCamera => _mediaStreamController.isFrontCamera;
  MediaStream? get _localStream => _mediaStreamController.localStream;
  bool get _localVideoTrackAttached =>
      _mediaStreamController.localVideoTrackAttached;
  RTCRtpSender? get _videoSendSender => _videoState.videoSendSender;
  set _videoSendSender(RTCRtpSender? value) =>
      _videoState.videoSendSender = value;
  RTCRtpTransceiver? get _videoSendTransceiver =>
      _videoState.videoSendTransceiver;
  set _videoSendTransceiver(RTCRtpTransceiver? value) =>
      _videoState.videoSendTransceiver = value;
  RTCRtpTransceiver? get _videoReceiveTransceiver =>
      _videoState.videoReceiveTransceiver;
  set _videoReceiveTransceiver(RTCRtpTransceiver? value) =>
      _videoState.videoReceiveTransceiver = value;
  bool get _remoteVideoEnabled => _videoState.remoteVideoEnabled;
  set _remoteVideoEnabled(bool value) => _videoState.remoteVideoEnabled = value;
  bool get _remoteVideoFlowSeen => _videoState.remoteVideoFlowSeen;
  set _remoteVideoFlowSeen(bool value) =>
      _videoState.remoteVideoFlowSeen = value;
  int? get _pendingRemoteVideoFlowAckVersion =>
      _videoState.pendingRemoteVideoFlowAckVersion;
  set _pendingRemoteVideoFlowAckVersion(int? value) =>
      _videoState.pendingRemoteVideoFlowAckVersion = value;

  Future<void> startOutgoing({
    required String peerId,
    required String callId,
    required TransportMode mode,
    required CallMediaType mediaType,
  }) async {
    await _peerSessionController.startOutgoing(
      peerId: peerId,
      callId: callId,
      mode: mode,
      mediaType: mediaType,
    );
  }

  Future<void> handleSignal(SignalingMessage message) async {
    await _serializeSignalingTransition(
      label: 'peer-signal:${message.type}',
      action: () => _peerSessionController.handleSignal(message),
    );
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    await _localMediaController.setMuted(muted);
  }

  Future<void> setSpeakerOn(bool enabled) async {
    _speakerOn = enabled;
    await _localMediaController.setSpeakerOn(enabled);
  }

  Future<void> flipCamera() async {
    await _cameraFlipController.flipCamera();
  }

  Future<CallMediaType> toggleVideo() async {
    final next = _mediaType == CallMediaType.video
        ? CallMediaType.audio
        : CallMediaType.video;
    await setMediaType(next, reason: 'local toggle');
    return _mediaType;
  }

  Future<void> setMediaType(
    CallMediaType next, {
    required String reason,
  }) async {
    if (_mediaType == next) {
      return;
    }

    _log(
      'mediaType:update next=${next.name} reason="$reason" '
      'snapshot=${_callRuntimeSnapshot()}',
    );
    await _localMediaController.setLocalVideoEnabled(
      next == CallMediaType.video,
    );
  }

  Future<void> _fallbackToAudioOnlyAfterVideoStall(String reason) async {
    _log('video:flow fallback audio-only reason="$reason"');
    _videoController.cancelRemoteVideoFlowRecovery();
    _remoteVideoFlowSeen = false;
    _onRemoteVideoFlowChanged(false);
    if (_mediaType == CallMediaType.video) {
      await _localMediaController.setLocalVideoEnabled(false);
    }
  }

  Future<void> _refreshLocalAudioOutbound(String reason) async {
    await _localAudioOutboundRefresher.refresh(reason);
  }

  Future<void> dispose() async {
    _cameraFlipController.clear();
    _recoveryCoordinator.dispose();
    await _mediaStreamController.disposeLocalStream();
    await _mediaStreamController.disposeVideoSourceStream();
    await _peerSessionController.disposePeerConnection();
  }

  Future<void> releaseLocalMediaForTeardown() async {
    _cameraFlipController.clear();
    _recoveryStatsTracker.reset();
    _recoveryCoordinator.reset();
    _log('media:release_local reason=terminal-transition');
    final sender = _videoSendSender ?? _videoSendTransceiver?.sender;
    if (sender != null) {
      try {
        await sender.replaceTrack(null);
      } catch (_) {}
    }
    await _mediaStreamController.disposeVideoSourceStream();
    await _mediaStreamController.disposeLocalStream();
  }

  Future<void> restartIce(String reason) {
    return observeRecovery(
      CallRecoveryObservation(
        kind: CallRecoveryObservationKind.liveMediaFlowStalled,
        reason: reason,
      ),
    );
  }

  Future<CallRecoveryDisposition> observeRecovery(
    CallRecoveryObservation observation,
  ) {
    return _recoveryCoordinator.observe(observation);
  }

  Future<void> forceRenegotiation(String reason) async {
    await _serializeSignalingTransition(
      label: 'renegotiation',
      action: () => _renegotiationOrchestrator.run(reason),
    );
  }

  Future<void> handleRemoteVideoState({
    required bool enabled,
    required int version,
    required String peerId,
    required String callId,
  }) async {
    await _serializeSignalingTransition(
      label: 'remote-video-state',
      action: () => _videoController.handleRemoteVideoState(
        enabled: enabled,
        version: version,
        peerId: peerId,
        callId: callId,
      ),
    );
  }

  Future<void> handleVideoStateAck({
    required bool enabled,
    required int version,
  }) async {
    await _serializeSignalingTransition(
      label: 'video-state-ack',
      action: () async {
        _videoController.handleVideoStateAck(
          enabled: enabled,
          version: version,
        );
      },
    );
  }

  Future<void> handleVideoFlowAck({required int version}) async {
    await _serializeSignalingTransition(
      label: 'video-flow-ack',
      action: () async {
        _videoController.handleVideoFlowAck(version: version);
      },
    );
  }

  Future<void> handleRemoteAudioMuteState({
    required bool muted,
    required int version,
  }) async {
    await _serializeSignalingTransition(
      label: 'remote-audio-mute',
      action: () async =>
          _remoteAudioMuteController.handle(muted: muted, version: version),
    );
  }

  TransportMode? _parseMode(dynamic raw) {
    return _negotiationController.parseMode(raw);
  }

  void _log(String message) {
    _logger.log(message);
  }

  String _callRuntimeSnapshot() {
    return _runtimeSnapshot.format();
  }

  Future<void> _serializeSignalingTransition({
    required String label,
    required Future<void> Function() action,
    bool Function()? shouldRun,
  }) async {
    return _signalTransitionSerializer.serialize(
      label: label,
      action: action,
      shouldRun: shouldRun,
    );
  }
}
