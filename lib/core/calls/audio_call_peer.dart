import 'dart:async';
import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'call_models.dart';
import 'call_negotiation_controller.dart';
import 'call_video_controller.dart';
import 'call_video_state.dart';

part 'audio_call_peer_helpers.dart';
part 'audio_call_peer_media_stats.dart';

class AudioCallPeer {
  static const Duration _iceDisconnectedGrace = Duration(seconds: 8);
  static const Duration _iceFailedGrace = Duration(seconds: 6);

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
  final void Function({
    required int sentBytes,
    required int receivedBytes,
  }) _onStats;
  final void Function(String error) _onError;
  late final CallNegotiationController _negotiationController;
  late final CallVideoController _videoController;

  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  MediaStream? _videoSourceStream;
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
  bool _localVideoTrackAttached = false;
  bool _remoteVideoTrackSeen = false;
  final CallVideoState _videoState = CallVideoState();
  bool _connected = false;
  bool _mediaFlowNotified = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _iceRestartInProgress = false;
  bool _renegotiationInProgress = false;
  bool _startedAsOfferer = false;
  String? _pendingRenegotiationReason;
  String? _pendingIceRestartReason;
  bool _isFrontCamera = true;
  Timer? _iceDisconnectedTimer;
  Timer? _iceFailedTimer;
  Timer? _audioStatsTimer;
  Timer? _mediaFlowFallbackTimer;
  int _lastInboundBytes = -1;
  int _lastInboundPackets = -1;
  double _lastInboundAudioEnergy = -1;
  double _lastInboundSamplesDuration = -1;
  int _reportedSentBytes = 0;
  int _reportedReceivedBytes = 0;
  int _logSeq = 0;

  AudioCallPeer({
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
    required void Function({
      required int sentBytes,
      required int receivedBytes,
    }) onStats,
    required void Function(String error) onError,
  })  : _signaling = signaling,
        _turnAllocator = turnAllocator,
        _onConnected = onConnected,
        _onMediaFlow = onMediaFlow,
        _onMediaTypeChanged = onMediaTypeChanged,
        _onLocalStream = onLocalStream,
        _onRemoteStream = onRemoteStream,
        _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
        _onRemoteVideoTrackChanged = onRemoteVideoTrackChanged,
        _onVideoCodecChanged = onVideoCodecChanged,
        _onStats = onStats,
        _onError = onError {
    _negotiationController = CallNegotiationController(
      signaling: _signaling,
      turnAllocator: _turnAllocator,
      log: _log,
      onVideoCodecChanged: _onVideoCodecChanged,
      rewriteVideoCodecs: _preferVideoCodecsInSdp,
      extractVideoCodec: _extractPreferredVideoCodec,
      onTurnCredentialsAllocated: (creds) => _activeTurnCredentials = creds,
      getPeer: () => _peer,
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getMode: () => _mode,
      getMediaType: () => _mediaType,
      getConnected: () => _connected,
      getRemoteDescriptionSet: () => _remoteDescriptionSet,
      getIceRestartInProgress: () => _iceRestartInProgress,
      setIceRestartInProgress: (value) => _iceRestartInProgress = value,
      getRenegotiationInProgress: () => _renegotiationInProgress,
      getPendingIceRestartReason: () => _pendingIceRestartReason,
      setPendingIceRestartReason: (value) => _pendingIceRestartReason = value,
    );
    _videoController = CallVideoController(
      signaling: _signaling,
      state: _videoState,
      log: _log,
      extractVideoMids: _extractVideoMids,
      onRemoteVideoFlowChanged: _onRemoteVideoFlowChanged,
      getPeerId: () => _peerId,
      getCallId: () => _callId,
      getStartedAsOfferer: () => _startedAsOfferer,
      getMediaType: () => _mediaType,
      getLocalVideoTrackAttached: () => _localVideoTrackAttached,
      getPeer: () => _peer,
    );
  }

  bool get isMuted => _muted;
  bool get speakerOn => _speakerOn;
  bool get isFrontCamera => _isFrontCamera;
  RTCRtpSender? get _videoSendSender => _videoState.videoSendSender;
  set _videoSendSender(RTCRtpSender? value) => _videoState.videoSendSender = value;
  RTCRtpTransceiver? get _videoSendTransceiver => _videoState.videoSendTransceiver;
  set _videoSendTransceiver(RTCRtpTransceiver? value) =>
      _videoState.videoSendTransceiver = value;
  RTCRtpTransceiver? get _videoReceiveTransceiver =>
      _videoState.videoReceiveTransceiver;
  set _videoReceiveTransceiver(RTCRtpTransceiver? value) =>
      _videoState.videoReceiveTransceiver = value;
  bool get _remoteVideoEnabled => _videoState.remoteVideoEnabled;
  set _remoteVideoEnabled(bool value) => _videoState.remoteVideoEnabled = value;
  bool get _remoteVideoFlowSeen => _videoState.remoteVideoFlowSeen;
  set _remoteVideoFlowSeen(bool value) => _videoState.remoteVideoFlowSeen = value;
  int? get _pendingRemoteVideoFlowAckVersion =>
      _videoState.pendingRemoteVideoFlowAckVersion;
  set _pendingRemoteVideoFlowAckVersion(int? value) =>
      _videoState.pendingRemoteVideoFlowAckVersion = value;
  int get _lastInboundVideoBytes => _videoState.lastInboundVideoBytes;
  set _lastInboundVideoBytes(int value) => _videoState.lastInboundVideoBytes = value;
  int get _lastInboundVideoFramesDecoded => _videoState.lastInboundVideoFramesDecoded;
  set _lastInboundVideoFramesDecoded(int value) =>
      _videoState.lastInboundVideoFramesDecoded = value;

  Future<void> startOutgoing({
    required String peerId,
    required String callId,
    required TransportMode mode,
    required CallMediaType mediaType,
  }) async {
    _peerId = peerId;
    _callId = callId;
    _mode = mode;
    _mediaType = mediaType;
    _startedAsOfferer = true;
    _remoteDescriptionSet = false;
    _iceConnected = false;
    _remoteTrackSeen = false;
    _remoteAudioTrackSeen = false;
    _remoteAudioFlowSeen = false;
    _localVideoTrackAttached = false;
    _remoteVideoTrackSeen = false;
    _remoteVideoFlowSeen = false;
    _remoteVideoEnabled = false;
    _onRemoteVideoTrackChanged(null);
    _onVideoCodecChanged(null);
    _connected = false;
    _mediaFlowNotified = false;
    _iceRestartInProgress = false;
    _videoState.pendingVideoFlowVersion = null;
    _pendingRemoteVideoFlowAckVersion = null;
    _stopAudioStatsPolling();
    _cancelMediaFlowFallback();
    _pendingIce.clear();

    await _preparePeerConnection();

    final rawOffer = await _peer!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    final offer = _withPreferredVideoCodecs(rawOffer);
    await _peer!.setLocalDescription(offer);
    _captureExpectedVideoMidsForLocalOffer(offer.sdp);

    await _signaling.sendOffer(peerId, {
      ...offer.toMap(),
      'callId': callId,
      'signalScope': 'call',
      'transportMode': mode.name,
      'mediaType': _mediaType.name,
    });
    _log('offer:sent mode=${mode.name}');
  }

  Future<void> handleSignal(SignalingMessage message) async {
    final peerId = message.fromPeerId;
    final data = message.data;
    final callId = data['callId']?.toString();
    final mode = _parseMode(data['transportMode']);

    if (callId == null || callId.isEmpty) {
      _log('signal:drop missing callId type=${message.type}');
      return;
    }

    _peerId = peerId;
    _callId = callId;
    _mode ??= mode ?? TransportMode.direct;
    if (message.type == 'offer') {
      final nextMode = mode ?? TransportMode.direct;
      _startedAsOfferer = false;
      await _resetPeerForIncomingOffer(nextMode);
      _mode = nextMode;
      await _preparePeerConnection();
      final sdp = data['sdp']?.toString();
      final type = data['type']?.toString() ?? 'offer';
      if (sdp == null || sdp.isEmpty) {
        _onError('Invalid remote offer');
        return;
      }

      await _peer!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );
      _captureExpectedVideoMidsForRemoteOffer(sdp);
      await _refreshVideoChannelHandles();
      await _ensureVideoTransceiverDirectionsForRole();
      if (_mediaType == CallMediaType.video) {
        await _syncLocalMediaTracks();
        _log('video:offer applied restored local video sender');
      }
      _remoteDescriptionSet = true;
      _iceRestartInProgress = false;
      _log('offer:remote description set');
      await _drainPendingIce();
      final rawAnswer = await _peer!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      final answer = _withPreferredVideoCodecs(rawAnswer);
      await _peer!.setLocalDescription(answer);
      _updateNegotiatedVideoCodec(answer.sdp);
      await _signaling.sendAnswer(peerId, {
        ...answer.toMap(),
        'callId': callId,
        'signalScope': 'call',
        'transportMode': _mode!.name,
        'mediaType': _mediaType.name,
      });
      _log('answer:sent mode=${_mode!.name}');
      await _drainQueuedIceRestartIfReady();
      return;
    }

    if (message.type == 'answer') {
      final sdp = data['sdp']?.toString();
      final type = data['type']?.toString() ?? 'answer';
      if (_peer == null || sdp == null || sdp.isEmpty) {
        return;
      }
      final signalingState = await _peer!.getSignalingState();
      final localDescription = await _peer!.getLocalDescription();
      final isWaitingForAnswer =
          signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer ||
          localDescription?.type == 'offer';
      if (!isWaitingForAnswer) {
        _log(
          'answer:ignored signalingState=$signalingState localDescriptionType=${localDescription?.type}',
        );
        return;
      }
      try {
        await _peer!.setRemoteDescription(
        RTCSessionDescription(sdp, type),
      );
      _captureExpectedVideoMidsForRemoteAnswer(sdp);
      _updateNegotiatedVideoCodec(sdp);
      await _refreshVideoChannelHandles();
      } catch (error) {
        final currentState = await _peer!.getSignalingState();
        final localType = (await _peer!.getLocalDescription())?.type;
        final errorText = error.toString();
        final becameStable =
            currentState == RTCSignalingState.RTCSignalingStateStable &&
            localType != 'offer';
        if (becameStable ||
            errorText.contains('Called in wrong state: stable')) {
          _log(
            'answer:ignored late signalingState=$currentState '
            'localDescriptionType=$localType error=$error',
          );
          return;
        }
        rethrow;
      }
      _remoteDescriptionSet = true;
      _iceRestartInProgress = false;
      _log('answer:remote description set');
      await _drainPendingIce();
      _log('answer:applied');
      await _drainQueuedIceRestartIfReady();
      return;
    }

    if (message.type == 'ice') {
      if (_peer == null) {
        return;
      }
      final candidate = data['candidate']?.toString();
      if (candidate == null || candidate.isEmpty) {
        return;
      }
      final rtcCandidate = RTCIceCandidate(
        candidate,
        data['sdpMid']?.toString(),
        data['sdpMLineIndex'] is int
            ? data['sdpMLineIndex'] as int
            : int.tryParse(data['sdpMLineIndex']?.toString() ?? ''),
      );
      if (!_remoteDescriptionSet) {
        _pendingIce.add(rtcCandidate);
        _log(
          'ice:queued type=${_candidateType(candidate)} '
          'protocol=${_candidateProtocol(candidate)} '
          'address=${_candidateAddress(candidate)} '
          'remote description not ready',
        );
        return;
      }
      try {
        await _peer!.addCandidate(rtcCandidate);
        _log(
          'ice:added type=${_candidateType(candidate)} '
          'protocol=${_candidateProtocol(candidate)} '
          'address=${_candidateAddress(candidate)}',
        );
      } catch (error) {
        _pendingIce.add(rtcCandidate);
        _log(
          'ice:re-queued type=${_candidateType(candidate)} '
          'protocol=${_candidateProtocol(candidate)} '
          'address=${_candidateAddress(candidate)} '
          'addCandidate error=$error',
        );
      }
      return;
    }
  }

  Future<void> setMuted(bool muted) async {
    _muted = muted;
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = !muted;
    }
  }

  Future<void> setSpeakerOn(bool enabled) async {
    _speakerOn = enabled;
    await Helper.setSpeakerphoneOn(enabled);
  }

  Future<void> flipCamera() async {
    final videoTracks = _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (videoTracks.isEmpty) {
      return;
    }
    await Helper.switchCamera(videoTracks.first);
    _isFrontCamera = !_isFrontCamera;
    if (_localStream != null) {
      _onLocalStream(_localStream!);
    }
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

    _log('mediaType:update next=${next.name} reason="$reason"');
    await _setLocalVideoEnabled(next == CallMediaType.video);
  }

  Future<void> dispose() async {
    _cancelIceRecoveryTimers();
    _cancelVideoUplinkFallback();
    _cancelMediaFlowFallback();
    _cancelPendingVideoStateAck();
    _cancelVideoQualityUpgrade();
    await _disposePeerConnection();
    await _disposeLocalStream();
    await _disposeVideoSourceStream();
  }

  Future<void> restartIce(String reason) {
    return _triggerIceRestart(reason);
  }

  Future<void> forceRenegotiation(String reason) async {
    if (_iceRestartInProgress) {
      _pendingRenegotiationReason = reason;
      _log('renegotiation:queued ice-restart-in-progress reason="$reason"');
      return;
    }
    if (_renegotiationInProgress) {
      _pendingRenegotiationReason = reason;
      _log('renegotiation:queued already-in-progress reason="$reason"');
      return;
    }
    _renegotiationInProgress = true;
    try {
      await _runRenegotiation(reason);
    } finally {
      _renegotiationInProgress = false;
    }
    final pendingReason = _pendingRenegotiationReason;
    if (pendingReason != null && !_iceRestartInProgress) {
      _pendingRenegotiationReason = null;
      await forceRenegotiation(pendingReason);
    }
    final pendingIceRestartReason = _pendingIceRestartReason;
    if (pendingIceRestartReason != null && !_iceRestartInProgress) {
      _pendingIceRestartReason = null;
      await restartIce(pendingIceRestartReason);
    }
  }

  Future<void> _runRenegotiation(String reason) async {
    return _negotiationController.runRenegotiation(reason);
  }

  Future<void> _preparePeerConnection() async {
    if (_peer != null) {
      return;
    }

    final config = await _negotiationController.buildRtcConfig(_mode ?? TransportMode.direct);
    _peer = await createPeerConnection(config);
    _bindPeerEvents();

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    _onLocalStream(_localStream!);

    final localTracks =
        List<MediaStreamTrack>.from(_localStream!.getTracks());
    for (final track in localTracks) {
      await _peer!.addTrack(track, _localStream!);
      if (track.kind == 'audio') {
        track.enabled = !_muted;
      }
    }

    if (_startedAsOfferer) {
      _videoSendTransceiver = await _peer!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.SendOnly,
          streams: [_localStream!],
        ),
      );
      _videoReceiveTransceiver = await _peer!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
      await _refreshVideoChannelHandles();
      _log(
        'video:bootstrap role=offerer '
        'sendSenderId=${_videoSendSender?.senderId} '
        'sendMid=${_videoSendTransceiver?.mid} recvMid=${_videoReceiveTransceiver?.mid}',
      );
    } else {
      _log('video:bootstrap role=answerer awaiting remote video transceivers');
    }

    // If the call was already in local video mode before peer recreation,
    // restore the sender path immediately on the new peer for the offerer.
    if (_startedAsOfferer && _mediaType == CallMediaType.video) {
      await _syncLocalMediaTracks();
      _log('video:bootstrap restored local video after peer recreate');
    }
  }

  Future<void> _resetPeerForIncomingOffer(TransportMode mode) async {
    RTCSignalingState? signalingState;
    String? localDescriptionType;
    if (_peer != null) {
      signalingState = await _peer!.getSignalingState();
      localDescriptionType = (await _peer!.getLocalDescription())?.type;
    }

    final hasPendingLocalOffer =
        signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer ||
        localDescriptionType == 'offer';

    final requiresRecreate =
        _peer != null &&
        (_mode != mode ||
            !_remoteDescriptionSet ||
            _iceRestartInProgress ||
            hasPendingLocalOffer);
    if (requiresRecreate) {
      _log(
        'offer:recreate peer currentMode=${_mode?.name ?? 'unknown'} nextMode=${mode.name} '
        'remoteDescriptionSet=$_remoteDescriptionSet iceRestartInProgress=$_iceRestartInProgress '
        'signalingState=$signalingState localDescriptionType=$localDescriptionType',
      );
      await _disposePeerConnection();
    } else if (_peer != null) {
      _log(
        'offer:reusing existing peer mode=${_mode?.name ?? mode.name} '
        'signalingState=$signalingState localDescriptionType=$localDescriptionType',
      );
    }

    _remoteDescriptionSet = false;
    _iceRestartInProgress = false;
    _renegotiationInProgress = false;
    _pendingRenegotiationReason = null;
    _pendingIceRestartReason = null;
    _videoState.pendingVideoFlowVersion = null;
    _pendingRemoteVideoFlowAckVersion = null;
    _pendingIce.clear();

    if (!requiresRecreate) {
      return;
    }

    _iceConnected = false;
    _remoteTrackSeen = false;
    _remoteAudioTrackSeen = false;
    _remoteAudioFlowSeen = false;
    _remoteVideoTrackSeen = false;
    _remoteVideoFlowSeen = false;
    _remoteVideoEnabled = false;
    _onRemoteVideoTrackChanged(null);
    _onVideoCodecChanged(null);
    _connected = false;
    _mediaFlowNotified = false;
    _stopAudioStatsPolling();
    _cancelMediaFlowFallback();
  }



  void _bindPeerEvents() {
    _peer!.onIceCandidate = (candidate) {
      final peerId = _peerId;
      final callId = _callId;
      final mode = _mode;
      if (peerId == null || callId == null || mode == null) {
        return;
      }
      _log(
        'ice:local type=${_candidateType(candidate.candidate)} '
        'protocol=${_candidateProtocol(candidate.candidate)} '
        'address=${_candidateAddress(candidate.candidate)} '
        'mid=${candidate.sdpMid} mline=${candidate.sdpMLineIndex}',
      );
      _signaling.sendIce(peerId, {
        ...candidate.toMap(),
        'callId': callId,
        'signalScope': 'call',
        'transportMode': mode.name,
      });
    };

    _peer!.onIceGatheringState = (state) {
      _log('iceGatheringState=$state');
    };

    _peer!.onConnectionState = (state) {
      _log('peerConnectionState=$state');
    };

    _peer!.onSignalingState = (state) {
      _log('signalingState=$state');
    };

    _peer!.onIceConnectionState = (state) {
      _log('iceState=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _cancelIceRecoveryTimers();
        _iceConnected = true;
        _iceRestartInProgress = false;
        _notifyConnected();
        // Report success for TURN server
        if (_activeTurnCredentials != null) {
          _turnAllocator?.reportSuccess(_activeTurnCredentials!.url);
        }
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateChecking) {
        _iceConnected = false;
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _iceConnected = false;
        _armIceFailureTimer(
          _iceFailedTimer,
          _iceFailedGrace,
          'ICE connection failed',
        );
        // Report failure for TURN server
        if (_activeTurnCredentials != null) {
          _turnAllocator?.reportFailure(_activeTurnCredentials!.url);
        }
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _iceConnected = false;
        _armIceDisconnectedTimer();
        // Report failure for TURN server
        if (_activeTurnCredentials != null) {
          _turnAllocator?.reportFailure(_activeTurnCredentials!.url);
        }
      }
      if (state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _cancelIceRecoveryTimers();
        _iceConnected = false;
      }
    };

    _peer!.onTrack = (event) {
      _remoteTrackSeen = true;
      final kind = event.track.kind;
      _log('track:remote kind=$kind');
      if (kind == 'video') {
        _remoteVideoTrackSeen = true;
        _onRemoteVideoTrackChanged(event.track.id);
      }
      if (event.streams.isNotEmpty) {
        unawaited(_ingestRemoteStream(event.streams.first));
      } else {
        unawaited(_attachRemoteTrack(event.track));
      }
      if (kind == 'audio') {
        _remoteAudioTrackSeen = true;
        _ensureAudioStatsPolling();
        _armMediaFlowFallback();
      }
      _notifyConnected();
    };

    _peer!.onAddStream = (stream) {
      _remoteTrackSeen = true;
      _log(
        'stream:remote added audio=${stream.getAudioTracks().length} '
        'video=${stream.getVideoTracks().length}',
      );
      // Under unified-plan, onTrack is the authoritative source for remote
      // tracks. onAddStream can arrive later with an audio-only stream and
      // accidentally wipe the already attached video track from the render
      // stream, so we do not merge it back into UI state here.
      if (!_remoteVideoTrackSeen && stream.getVideoTracks().isNotEmpty) {
        unawaited(_ingestRemoteStream(stream));
      }
      if (stream.getAudioTracks().isNotEmpty) {
        _remoteAudioTrackSeen = true;
        _armMediaFlowFallback();
      }
      _ensureAudioStatsPolling();
      _notifyConnected();
    };
  }

  void _notifyConnected() {
    if (_connected || _mode == null) {
      return;
    }
    if (!_iceConnected || !_remoteTrackSeen) {
      _log(
        'connected:waiting ice=$_iceConnected remoteTrack=$_remoteTrackSeen audioFlow=$_remoteAudioFlowSeen',
      );
      return;
    }
    _connected = true;
    _log(
      'connected transportReady=true remoteTrackSeen=$_remoteTrackSeen audioFlow=$_remoteAudioFlowSeen',
    );
    _onConnected(_mode!);
    _armMediaFlowFallback();
  }

  Future<void> _drainPendingIce() async {
    if (_peer == null || !_remoteDescriptionSet || _pendingIce.isEmpty) {
      return;
    }

    _log('ice:drain count=${_pendingIce.length}');
    final queued = List<RTCIceCandidate>.from(_pendingIce);
    for (final candidate in queued) {
      try {
        await _peer!.addCandidate(candidate);
        _pendingIce.remove(candidate);
        _log(
          'ice:drain added type=${_candidateType(candidate.candidate)} '
          'protocol=${_candidateProtocol(candidate.candidate)} '
          'address=${_candidateAddress(candidate.candidate)}',
        );
      } catch (error) {
        _pendingIce.add(candidate);
        _log(
          'ice:drain re-queued type=${_candidateType(candidate.candidate)} '
          'protocol=${_candidateProtocol(candidate.candidate)} '
          'address=${_candidateAddress(candidate.candidate)} '
          'error=$error',
        );
      }
    }
  }

  RTCSessionDescription _withPreferredVideoCodecs(
    RTCSessionDescription description,
  ) {
    return _negotiationController.withPreferredVideoCodecs(description);
  }

  void _updateNegotiatedVideoCodec(String? sdp) {
    _negotiationController.updateNegotiatedVideoCodec(sdp);
  }

  Future<void> _disposePeerConnection() async {
    _cancelIceRecoveryTimers();
    _cancelVideoUplinkFallback();
    _cancelPendingVideoStateAck();
    try {
      await _peer?.close();
    } catch (_) {
      // Ignore peer close errors during cleanup.
    }
    _peer = null;
    _videoSendSender = null;
    _videoSendTransceiver = null;
    _videoReceiveTransceiver = null;
    _videoState.expectedVideoSendMid = null;
    _videoState.expectedVideoReceiveMid = null;
    _pendingIce.clear();
    await _disposeRemoteStream();
    _remoteDescriptionSet = false;
    _iceConnected = false;
    _remoteTrackSeen = false;
    _remoteAudioTrackSeen = false;
    _remoteAudioFlowSeen = false;
    _localVideoTrackAttached = false;
    _remoteVideoTrackSeen = false;
    _remoteVideoFlowSeen = false;
    _remoteVideoEnabled = false;
    _onVideoCodecChanged(null);
    _connected = false;
    _mediaFlowNotified = false;
    _iceRestartInProgress = false;
    _renegotiationInProgress = false;
    _pendingRenegotiationReason = null;
    _pendingIceRestartReason = null;
    _videoState.pendingVideoFlowVersion = null;
    _pendingRemoteVideoFlowAckVersion = null;
    _stopAudioStatsPolling();
    _cancelMediaFlowFallback();
    _cancelVideoQualityUpgrade();
    _activeTurnCredentials = null;
  }

  void _armIceDisconnectedTimer() {
    if (!_connected) {
      _onError('ICE connection disconnected');
      return;
    }
    unawaited(_triggerIceRestart('ICE connection disconnected'));
    _armIceFailureTimer(
      _iceDisconnectedTimer,
      _iceDisconnectedGrace,
      'ICE connection disconnected',
    );
  }

  void _armIceFailureTimer(
    Timer? currentTimer,
    Duration grace,
    String error,
  ) {
    if (!_connected) {
      _onError(error);
      return;
    }
    unawaited(_triggerIceRestart(error));
    if (currentTimer?.isActive ?? false) {
      return;
    }
    _log('ice:grace start error="$error" graceMs=${grace.inMilliseconds}');
    final timer = Timer(grace, () {
      _log('ice:grace expired error="$error"');
      _onError(error);
    });
    if (error == 'ICE connection disconnected') {
      _iceDisconnectedTimer = timer;
      return;
    }
    _iceFailedTimer = timer;
  }

  void _cancelIceRecoveryTimers() {
    if (_iceDisconnectedTimer?.isActive ?? false) {
      _log('ice:grace cancel disconnected');
    }
    if (_iceFailedTimer?.isActive ?? false) {
      _log('ice:grace cancel failed');
    }
    _iceDisconnectedTimer?.cancel();
    _iceFailedTimer?.cancel();
    _iceDisconnectedTimer = null;
    _iceFailedTimer = null;
  }

  void _ensureAudioStatsPolling() {
    if (_audioStatsTimer?.isActive ?? false) {
      return;
    }
    _audioStatsTimer = Timer.periodic(
      const Duration(milliseconds: 600),
      (_) => unawaited(_pollInboundAudioStats()),
    );
    unawaited(_pollInboundAudioStats());
  }

  Future<void> _pollInboundAudioStats() async {
    final peer = _peer;
    if (peer == null) {
      return;
    }
    try {
      final reports = await peer.getStats();
      final stats = _extractAudioTrafficStats(reports);
      if (stats.sentBytes != _reportedSentBytes ||
          stats.receivedBytes != _reportedReceivedBytes) {
        _reportedSentBytes = stats.sentBytes;
        _reportedReceivedBytes = stats.receivedBytes;
        _onStats(
          sentBytes: stats.sentBytes,
          receivedBytes: stats.receivedBytes,
        );
      }
      if (!_remoteAudioFlowSeen && _detectInboundAudioFlow(stats)) {
        _remoteAudioFlowSeen = true;
        _cancelMediaFlowFallback();
        _log('audio:flow detected');
        if (!_mediaFlowNotified) {
          _mediaFlowNotified = true;
          unawaited(_onMediaFlow());
        }
        _notifyConnected();
      }
      if (_remoteVideoEnabled &&
          !_remoteVideoFlowSeen &&
          _detectInboundVideoFlow(stats)) {
        _remoteVideoFlowSeen = true;
        _log('video:flow detected remoteTrackSeen=$_remoteVideoTrackSeen');
        _onRemoteVideoFlowChanged(true);
        final version = _pendingRemoteVideoFlowAckVersion;
        final peerId = _peerId;
        final callId = _callId;
        if (version != null && peerId != null && callId != null) {
          unawaited(_signaling.sendSignal(peerId, 'call_video_flow_ack', {
            'callId': callId,
            'signalScope': 'call',
            'version': version,
          }));
          _log('video:flow ack sent version=$version');
          _pendingRemoteVideoFlowAckVersion = null;
        }
      } else if (_remoteVideoEnabled && _remoteVideoTrackSeen) {
        _log('video:flow waiting trackSeen=true framesPending');
      }
    } catch (error) {
      _log('audio:stats poll error=$error');
    }
  }

  _AudioTrafficStats _extractAudioTrafficStats(List<StatsReport> reports) {
    return _extractAudioTrafficStatsImpl(reports);
  }

  bool _detectInboundAudioFlow(_AudioTrafficStats stats) {
    return _detectInboundAudioFlowImpl(this, stats);
  }

  bool _detectInboundVideoFlow(_AudioTrafficStats stats) {
    return _detectInboundVideoFlowImpl(this, stats);
  }




  void _stopAudioStatsPolling() {
    _audioStatsTimer?.cancel();
    _audioStatsTimer = null;
    _cancelMediaFlowFallback();
    _lastInboundBytes = -1;
    _lastInboundPackets = -1;
    _lastInboundAudioEnergy = -1;
    _lastInboundSamplesDuration = -1;
    _lastInboundVideoBytes = -1;
    _lastInboundVideoFramesDecoded = -1;
    _reportedSentBytes = 0;
    _reportedReceivedBytes = 0;
  }

  void _armMediaFlowFallback() {
    if (_mediaFlowNotified ||
        !_iceConnected ||
        !_remoteAudioTrackSeen ||
        _peer == null) {
      return;
    }
    if (_mediaFlowFallbackTimer?.isActive ?? false) {
      return;
    }
    _mediaFlowFallbackTimer = Timer(const Duration(milliseconds: 1400), () {
      _mediaFlowFallbackTimer = null;
      if (_mediaFlowNotified ||
          !_iceConnected ||
          !_remoteAudioTrackSeen ||
          _peer == null) {
        return;
      }
      _remoteAudioFlowSeen = true;
      _mediaFlowNotified = true;
      _log(
        'audio:flow fallback transportReady=$_iceConnected remoteAudioTrackSeen=$_remoteAudioTrackSeen',
      );
      unawaited(_onMediaFlow());
      _notifyConnected();
    });
  }

  void _cancelMediaFlowFallback() {
    _mediaFlowFallbackTimer?.cancel();
    _mediaFlowFallbackTimer = null;
  }

  Future<void> _triggerIceRestart(String reason) async {
    return _negotiationController.triggerIceRestart(reason);
  }

  Future<void> _drainQueuedIceRestartIfReady() async {
    return _negotiationController.drainQueuedIceRestartIfReady();
  }

  Future<void> _disposeLocalStream() async {
    final tracks =
        List<MediaStreamTrack>.from(_localStream?.getTracks() ?? const <MediaStreamTrack>[]);
    for (final track in tracks) {
      try {
        track.stop();
      } catch (_) {
        // Ignore track cleanup errors.
      }
    }
    try {
      await _localStream?.dispose();
    } catch (_) {
      // Ignore stream cleanup errors.
    }
    _localStream = null;
  }

  Future<void> _disposeVideoSourceStream() async {
    final tracks = List<MediaStreamTrack>.from(
      _videoSourceStream?.getTracks() ?? const <MediaStreamTrack>[],
    );
    for (final track in tracks) {
      try {
        track.stop();
      } catch (_) {
        // Ignore track cleanup errors.
      }
    }
    try {
      await _videoSourceStream?.dispose();
    } catch (_) {
      // Ignore stream cleanup errors.
    }
    _videoSourceStream = null;
  }

  Future<void> _disposeRemoteStream() async {
    try {
      if (_remoteStream != null) {
        await _remoteStream?.dispose();
      }
    } catch (_) {
      // Ignore remote stream cleanup errors.
    }
    _remoteStream = null;
  }

  Future<void> _replaceRemoteStream(MediaStream stream) async {
    _remoteStream = stream;
    _onRemoteStream(stream);
  }

  Future<MediaStream> _ensureRemoteRenderStream() async {
    var stream = _remoteStream;
    if (stream != null) {
      return stream;
    }
    stream = await createLocalMediaStream('remote-${_callId ?? 'call'}');
    await _replaceRemoteStream(stream);
    return stream;
  }

  Future<void> _ingestRemoteStream(MediaStream incoming) async {
    final renderStream = await _ensureRemoteRenderStream();
    final currentAudioTracks = List<MediaStreamTrack>.from(
      renderStream.getAudioTracks(),
    );
    final currentVideoTracks = List<MediaStreamTrack>.from(
      renderStream.getVideoTracks(),
    );
    final incomingAudioTracks = List<MediaStreamTrack>.from(
      incoming.getAudioTracks(),
    );
    final incomingVideoTracks = List<MediaStreamTrack>.from(
      incoming.getVideoTracks(),
    );

    final effectiveTracks = <MediaStreamTrack>[
      if (incomingAudioTracks.isNotEmpty)
        incomingAudioTracks.last
      else if (currentAudioTracks.isNotEmpty)
        currentAudioTracks.last,
      if (incomingVideoTracks.isNotEmpty)
        incomingVideoTracks.last
      else if (currentVideoTracks.isNotEmpty)
        currentVideoTracks.last,
    ];

    var activeStream = renderStream;
    for (final track in effectiveTracks) {
      activeStream = await _mergeRemoteTrack(activeStream, track);
    }
    _log(
      'stream:remote render '
      'nativeAudio=${incoming.getAudioTracks().length} '
      'nativeVideo=${incoming.getVideoTracks().length} '
      'audio=${activeStream.getAudioTracks().length} '
      'video=${activeStream.getVideoTracks().length}',
    );
    _onRemoteStream(activeStream);
  }

  Future<void> _attachRemoteTrack(MediaStreamTrack track) async {
    final stream = await _ensureRemoteRenderStream();
    final activeStream = await _mergeRemoteTrack(stream, track);
    _log(
      'stream:remote track=${track.kind} '
      'audio=${activeStream.getAudioTracks().length} '
      'video=${activeStream.getVideoTracks().length}',
    );
    _onRemoteStream(activeStream);
  }

  Future<MediaStream> _mergeRemoteTrack(
    MediaStream stream,
    MediaStreamTrack track,
  ) async {
    final existingTracks = track.kind == 'video'
        ? List<MediaStreamTrack>.from(stream.getVideoTracks())
        : List<MediaStreamTrack>.from(stream.getAudioTracks());
    final alreadyAttached = existingTracks.any(
      (existing) => existing.id == track.id,
    );
    if (alreadyAttached) {
      return stream;
    }
    for (final existing in existingTracks) {
      try {
        stream.removeTrack(existing);
      } catch (_) {
        // Ignore detach issues for replaced remote tracks.
      }
      _log(
        'stream:remote replaced kind=${track.kind} '
        'oldTrack=${existing.id} newTrack=${track.id}',
      );
    }
    stream.addTrack(track);
    return stream;
  }

  Future<void> _syncLocalMediaTracks() async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    await _refreshVideoChannelHandles();

    final videoTracks = stream.getVideoTracks();
    if (_mediaType == CallMediaType.video && videoTracks.isEmpty) {
      _videoSourceStream ??= await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': 640,
          'height': 360,
          'frameRate': 12,
        },
      });
      _isFrontCamera = true;
      final sourceTracks =
          List<MediaStreamTrack>.from(_videoSourceStream!.getVideoTracks());
      for (final track in sourceTracks) {
        final alreadyAttached = stream
            .getVideoTracks()
            .any((existing) => existing.id == track.id);
        if (!alreadyAttached) {
          stream.addTrack(track);
        }
        final sender = _videoSendSender ?? _videoSendTransceiver?.sender;
        if (sender != null) {
          await sender.replaceTrack(track);
          _videoSendSender = sender;
        } else {
          await _videoSendSender?.replaceTrack(track);
        }
      }
      await _applyInitialVideoQualityProfile();
      _localVideoTrackAttached = true;
      _log(
        'video:sender attached localTracks=${stream.getVideoTracks().length} '
        'sourceTracks=${_videoSourceStream?.getVideoTracks().length ?? 0}',
      );
      _onLocalStream(_videoSourceStream!);
      return;
    }

    if (_mediaType == CallMediaType.audio && videoTracks.isNotEmpty) {
      for (final track in List<MediaStreamTrack>.from(videoTracks)) {
        stream.removeTrack(track);
        track.stop();
      }
      final sender = _videoSendSender ?? _videoSendTransceiver?.sender;
      if (sender != null) {
        await sender.replaceTrack(null);
        _videoSendSender = sender;
      } else {
        await _videoSendSender?.replaceTrack(null);
      }
      _localVideoTrackAttached = false;
      _cancelVideoQualityUpgrade();
      await _disposeVideoSourceStream();
      _log('video:sender detached localTracks=${stream.getVideoTracks().length}');
      _onLocalStream(stream);
    }
  }

  Future<void> _setLocalVideoEnabled(bool enabled) async {
    if ((_mediaType == CallMediaType.video) == enabled) {
      return;
    }

    final peerId = _peerId;
    final callId = _callId;
    if (_peer == null || _localStream == null || peerId == null || callId == null) {
      _mediaType = enabled ? CallMediaType.video : CallMediaType.audio;
      _onMediaTypeChanged(_mediaType);
      return;
    }

    _mediaType = enabled ? CallMediaType.video : CallMediaType.audio;
    _onMediaTypeChanged(_mediaType);
    await _syncLocalMediaTracks();
    await _sendVideoState(
      enabled: enabled,
      peerId: peerId,
      callId: callId,
    );
    if (enabled) {
      await _refreshVideoChannelHandles();
      _log(
        'video:toggle applied enabled=$enabled '
        'senderId=${_videoSendSender?.senderId} '
        'sendMid=${_videoSendTransceiver?.mid} '
        'recvMid=${_videoReceiveTransceiver?.mid} '
        'localAttached=$_localVideoTrackAttached',
      );
    } else {
      _cancelVideoUplinkFallback();
      _log(
        'video:toggle applied enabled=$enabled '
        'localTracks=${_localStream?.getVideoTracks().length ?? 0} '
        'localAttached=$_localVideoTrackAttached',
      );
    }
  }

  void _cancelVideoUplinkFallback() {
    _videoController.cancelVideoUplinkFallback();
  }

  Future<void> _sendVideoState({
    required bool enabled,
    required String peerId,
    required String callId,
  }) async {
    return _videoController.sendVideoState(
      enabled: enabled,
      peerId: peerId,
      callId: callId,
    );
  }

  Future<void> handleRemoteVideoState({
    required bool enabled,
    required int version,
    required String peerId,
    required String callId,
  }) async {
    return _videoController.handleRemoteVideoState(
      enabled: enabled,
      version: version,
      peerId: peerId,
      callId: callId,
    );
  }

  void handleVideoStateAck({
    required bool enabled,
    required int version,
  }) {
    _videoController.handleVideoStateAck(enabled: enabled, version: version);
  }

  void handleVideoFlowAck({
    required int version,
  }) {
    _videoController.handleVideoFlowAck(version: version);
  }

  Future<void> _applyInitialVideoQualityProfile() async {
    return _videoController.applyInitialVideoQualityProfile();
  }

  void _cancelVideoQualityUpgrade() {
    _videoController.cancelVideoQualityUpgrade();
  }

  void _cancelPendingVideoStateAck() {
    _videoController.cancelPendingVideoStateAck();
  }

  Future<void> _refreshVideoChannelHandles() async {
    return _videoController.refreshVideoChannelHandles();
  }

  void _captureExpectedVideoMidsForLocalOffer(String? sdp) {
    _videoController.captureExpectedVideoMidsForLocalOffer(sdp);
  }

  void _captureExpectedVideoMidsForRemoteOffer(String? sdp) {
    _videoController.captureExpectedVideoMidsForRemoteOffer(sdp);
  }

  void _captureExpectedVideoMidsForRemoteAnswer(String? sdp) {
    _videoController.captureExpectedVideoMidsForRemoteAnswer(sdp);
  }

  Future<void> _ensureVideoTransceiverDirectionsForRole() async {
    return _videoController.ensureVideoTransceiverDirectionsForRole();
  }

  TransportMode? _parseMode(dynamic raw) {
    return _negotiationController.parseMode(raw);
  }

  void _log(String message) {
    AppFileLogger.log('[call_peer][${_peerId ?? 'unknown'}][${_logSeq++}] $message');
  }
}
