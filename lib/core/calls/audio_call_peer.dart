import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'call_connection_state_controller.dart';
import 'call_media_flow_controller.dart';
import 'call_local_media_controller.dart';
import 'call_media_stream_controller.dart';
import 'call_media_stats_utils.dart';
import 'call_models.dart';
import 'call_negotiation_controller.dart';
import 'call_peer_event_controller.dart';
import 'call_peer_session_controller.dart';
import 'call_recovery_coordinator.dart';
import 'call_sdp_utils.dart';
import 'call_session_epoch.dart';
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
  final bool Function()? _hasLocalVideoForFlipOverride;
  final Future<bool> Function()? _canExecuteCameraFlipOverride;
  final Future<void> Function()? _performCameraFlipOverride;
  late final CallMediaFlowController _mediaFlowController;
  late final CallConnectionStateController _connectionStateController;
  late final CallLocalMediaController _localMediaController;
  late final CallNegotiationController _negotiationController;
  late final CallPeerEventController _peerEventController;
  late final CallPeerSessionController _peerSessionController;
  late final CallRecoveryCoordinator _recoveryCoordinator;
  late final CallVideoController _videoController;
  late final CallMediaStreamController _mediaStreamController;

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
  int _remoteAudioMuteVersion = -1;
  bool _remoteVideoTrackSeen = false;
  final CallVideoState _videoState = CallVideoState();
  bool _connected = false;
  bool _mediaFlowNotified = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _renegotiationInProgress = false;
  bool _startedAsOfferer = false;
  String? _pendingRenegotiationReason;
  String _lastSignalingStateLabel = 'unknown';
  CallSessionEpoch _sessionEpoch = CallSessionEpoch.initial();
  late final CallRuntimeLogger _logger;
  Future<void> _signalingTransitionQueue = Future<void>.value();
  int _queuedCameraFlipCount = 0;
  bool _cameraFlipInProgress = false;
  Timer? _queuedCameraFlipRetryTimer;
  int? _lastRecoveryReceivedBytes;

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
       _onError = onError,
       _hasLocalVideoForFlipOverride = hasLocalVideoForFlipOverride,
       _canExecuteCameraFlipOverride = canExecuteCameraFlipOverride,
       _performCameraFlipOverride = performCameraFlipOverride {
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
      setRenegotiationInProgress: (value) => _renegotiationInProgress = value,
      setPendingRenegotiationReason: (value) =>
          _pendingRenegotiationReason = value,
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
    _lastRecoveryReceivedBytes = null;
    _recoveryCoordinator.reset();
  }

  void _recordRecoveryMediaStats(AudioTrafficStats stats) {
    if (stats.selectedCandidatePairId == null) {
      return;
    }
    final receivedBytes = stats.receivedBytes;
    final previous = _lastRecoveryReceivedBytes;
    _lastRecoveryReceivedBytes = receivedBytes;
    if (receivedBytes <= 0) {
      return;
    }
    if (previous != null && receivedBytes <= previous) {
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
    if (_mediaType != CallMediaType.video) {
      return;
    }
    if (!_hasLocalVideoForFlip()) {
      return;
    }
    if (_cameraFlipInProgress) {
      _enqueueCameraFlip('flip-in-progress');
      return;
    }
    if (!await _canExecuteCameraFlip()) {
      _log(
        'video:flip skipped reason=signaling-not-stable '
        'renegotiation=$_renegotiationInProgress signaling=$_lastSignalingStateLabel',
      );
      return;
    }
    await _performCameraFlip();
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
    if (_muted) {
      _log(
        'diagnostic:warning audio-sender refresh skipped reason="$reason" '
        'muted=true snapshot=${_callRuntimeSnapshot()}',
      );
      return;
    }
    final peer = _peer;
    if (peer == null) {
      _log(
        'diagnostic:warning audio-sender refresh skipped reason="$reason" '
        'peer=false snapshot=${_callRuntimeSnapshot()}',
      );
      return;
    }
    _log(
      'diagnostic:warning audio-sender refresh start reason="$reason" '
      'snapshot=${_callRuntimeSnapshot()}',
    );
    await _mediaStreamController.refreshLocalAudioSender(
      peer: peer,
      muted: _muted,
      reason: reason,
    );
    _log(
      'diagnostic:warning audio-sender refresh finish reason="$reason" '
      'snapshot=${_callRuntimeSnapshot()}',
    );
  }

  Future<void> dispose() async {
    _clearQueuedCameraFlip();
    _recoveryCoordinator.dispose();
    await _mediaStreamController.disposeLocalStream();
    await _mediaStreamController.disposeVideoSourceStream();
    await _peerSessionController.disposePeerConnection();
  }

  Future<void> releaseLocalMediaForTeardown() async {
    _clearQueuedCameraFlip();
    _lastRecoveryReceivedBytes = null;
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
      action: () => _runRenegotiation(reason),
    );
  }

  Future<void> _runRenegotiation(String reason) async {
    if (_renegotiationInProgress) {
      _pendingRenegotiationReason = reason;
      _log('renegotiation:queued already-in-progress reason="$reason"');
      return;
    }
    _renegotiationInProgress = true;
    try {
      await _negotiationController.runRenegotiation(reason);
    } finally {
      _renegotiationInProgress = false;
    }
    final pendingReason = _pendingRenegotiationReason;
    if (pendingReason != null) {
      _pendingRenegotiationReason = null;
      await _runRenegotiation(pendingReason);
    }
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
      action: () async {
        if (version <= _remoteAudioMuteVersion) {
          _log(
            'audio:remote mute ignored muted=$muted version=$version '
            'lastVersion=$_remoteAudioMuteVersion',
          );
          return;
        }
        _remoteAudioMuteVersion = version;
        _remoteAudioMuted = muted;
        _remoteAudioFlowSeen = false;
        _log(
          'audio:remote mute state muted=$muted version=$version '
          'snapshot=${_callRuntimeSnapshot()}',
        );
      },
    );
  }

  TransportMode? _parseMode(dynamic raw) {
    return _negotiationController.parseMode(raw);
  }

  void _log(String message) {
    _logger.log(message);
  }

  String _callRuntimeSnapshot() {
    return 'peer=${_peer != null} connected=$_connected iceConnected=$_iceConnected '
        'media=${_mediaType.name} muted=$_muted remoteAudioTrack=$_remoteAudioTrackSeen '
        'remoteAudioFlow=$_remoteAudioFlowSeen remoteAudioMuted=$_remoteAudioMuted '
        'remoteVideoTrack=$_remoteVideoTrackSeen '
        'remoteVideoEnabled=$_remoteVideoEnabled remoteVideoFlow=$_remoteVideoFlowSeen '
        'renegotiation=$_renegotiationInProgress signaling=$_lastSignalingStateLabel';
  }

  Future<void> _serializeSignalingTransition({
    required String label,
    required Future<void> Function() action,
    bool Function()? shouldRun,
  }) async {
    final completer = Completer<void>();
    final previous = _signalingTransitionQueue;
    _signalingTransitionQueue = completer.future;
    try {
      await previous;
      if (shouldRun != null && !shouldRun()) {
        _log('signal-transition:skip label=$label');
        return;
      }
      _log('signal-transition:start label=$label');
      await action();
    } finally {
      _log('signal-transition:done label=$label');
      if (!completer.isCompleted) {
        completer.complete();
      }
      _scheduleQueuedCameraFlipRetry();
    }
  }

  Future<bool> _canExecuteCameraFlip() async {
    final override = _canExecuteCameraFlipOverride;
    if (override != null) {
      return override();
    }
    final peer = _peer;
    if (peer == null) {
      return true;
    }
    final signalingState = await peer.getSignalingState();
    return signalingState == RTCSignalingState.RTCSignalingStateStable &&
        !_renegotiationInProgress;
  }

  void _enqueueCameraFlip(String reason) {
    _queuedCameraFlipCount = 1;
    _log(
      'video:flip queued reason=$reason pending=$_queuedCameraFlipCount '
      'renegotiation=$_renegotiationInProgress signaling=$_lastSignalingStateLabel',
    );
    _scheduleQueuedCameraFlipRetry();
  }

  void _scheduleQueuedCameraFlipRetry() {
    if (_queuedCameraFlipCount == 0 || _cameraFlipInProgress) {
      return;
    }
    if (_queuedCameraFlipRetryTimer?.isActive ?? false) {
      return;
    }
    _queuedCameraFlipRetryTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_drainQueuedCameraFlip());
    });
  }

  Future<void> _drainQueuedCameraFlip() async {
    _queuedCameraFlipRetryTimer?.cancel();
    _queuedCameraFlipRetryTimer = null;
    if (_queuedCameraFlipCount == 0 || _cameraFlipInProgress) {
      return;
    }
    if (!_hasLocalVideoForFlip()) {
      _log('video:flip queue cleared reason=no-local-video');
      _queuedCameraFlipCount = 0;
      return;
    }
    if (!await _canExecuteCameraFlip()) {
      _scheduleQueuedCameraFlipRetry();
      return;
    }
    final pending = _queuedCameraFlipCount;
    _queuedCameraFlipCount = 0;
    if (pending.isEven) {
      _log('video:flip queue coalesced pending=$pending action=no-op');
      return;
    }
    _log('video:flip queue drain pending=$pending action=single-flip');
    await _performCameraFlip();
  }

  Future<void> _performCameraFlip() async {
    final override = _performCameraFlipOverride;
    _cameraFlipInProgress = true;
    try {
      if (override != null) {
        await override();
        return;
      }
      await _localMediaController.flipCamera();
      if (_mediaType == CallMediaType.video) {
        await _videoController.syncLocalMediaTracks();
        await _videoController.refreshVideoChannelHandles();
      }
    } finally {
      _cameraFlipInProgress = false;
      if (_queuedCameraFlipCount > 0) {
        _scheduleQueuedCameraFlipRetry();
      }
    }
  }

  void _clearQueuedCameraFlip() {
    _queuedCameraFlipRetryTimer?.cancel();
    _queuedCameraFlipRetryTimer = null;
    _queuedCameraFlipCount = 0;
    _cameraFlipInProgress = false;
  }

  bool _hasLocalVideoForFlip() {
    final override = _hasLocalVideoForFlipOverride;
    if (override != null) {
      return override();
    }
    final videoTracks =
        _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    return videoTracks.isNotEmpty;
  }
}
