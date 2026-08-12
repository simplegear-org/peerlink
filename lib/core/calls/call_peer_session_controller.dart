import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import 'call_media_stream_controller.dart';
import 'call_models.dart';
import 'call_offer_processing_gate.dart';
import 'call_signaling_invariants.dart';
import 'call_sdp_utils.dart';
import 'call_video_state.dart';

class CallPeerSessionController {
  final CallOfferProcessingGate _offerProcessingGate =
      CallOfferProcessingGate();
  Future<void> _signalHandlingQueue = Future<void>.value();
  final SignalingService _signaling;
  final CallVideoState _videoState;
  final void Function(String message) _log;
  final void Function(String error) _onError;
  final void Function(String? trackId) _onRemoteVideoTrackChanged;
  final void Function(String? codec) _onVideoCodecChanged;

  final RTCPeerConnection? Function() _getPeer;
  final void Function(RTCPeerConnection? peer) _setPeer;
  final void Function(String? value) _setPeerId;
  final void Function(String? value) _setCallId;
  final TransportMode? Function() _getMode;
  final void Function(TransportMode? value) _setMode;
  final CallMediaType Function() _getMediaType;
  final void Function(CallMediaType value) _setMediaType;
  final void Function(bool value) _setStartedAsOfferer;
  final bool Function() _getRemoteDescriptionSet;
  final void Function(bool value) _setRemoteDescriptionSet;
  final void Function(bool value) _setIceConnected;
  final void Function(bool value) _setRemoteTrackSeen;
  final void Function(bool value) _setRemoteAudioTrackSeen;
  final void Function(bool value) _setRemoteAudioFlowSeen;
  final void Function(bool value) _setRemoteVideoTrackSeen;
  final void Function(bool value) _setConnected;
  final void Function(bool value) _setMediaFlowNotified;
  final void Function(bool value) _setRenegotiationInProgress;
  final void Function(String? value) _setPendingRenegotiationReason;
  final List<RTCIceCandidate> Function() _getPendingIce;
  final void Function(int? value) _setPendingRemoteVideoFlowAckVersion;
  final void Function(bool value) _setRemoteVideoEnabled;
  final void Function(bool value) _setRemoteVideoFlowSeen;
  final CallMediaStreamController _mediaStreamController;
  final Future<Map<String, dynamic>> Function(TransportMode mode)
  _buildRtcConfig;
  final void Function(RTCPeerConnection peer) _bindPeerEvents;
  final bool Function() _getMuted;
  final bool Function() _getSpeakerOn;
  final bool Function() _getStartedAsOfferer;
  final Future<void> Function(bool enabled) _applySpeakerOn;
  final Future<void> Function() _syncLocalMediaTracks;
  final Future<void> Function() _refreshVideoChannelHandles;
  final Future<void> Function() _ensureVideoTransceiverDirectionsForRole;
  final RTCSessionDescription Function(RTCSessionDescription description)
  _withPreferredVideoCodecs;
  final void Function(String? sdp) _captureExpectedVideoMidsForLocalOffer;
  final void Function(String? sdp) _captureExpectedVideoMidsForRemoteOffer;
  final void Function(String? sdp) _captureExpectedVideoMidsForRemoteAnswer;
  final void Function(String? sdp) _updateNegotiatedVideoCodec;
  final void Function() _armPostIceRecoveryFlowWatch;
  final void Function(String reason) _resetPostIceRecoveryFlowWatch;
  final void Function() _stopAudioStatsPolling;
  final void Function() _cancelMediaFlowFallback;
  final void Function() _cancelIceRecoveryTimers;
  final void Function() _cancelVideoUplinkFallback;
  final void Function() _cancelRemoteVideoFlowRecovery;
  final void Function() _cancelPendingVideoStateAck;
  final void Function() _cancelVideoQualityUpgrade;
  final Future<void> Function() _disposeRemoteStream;
  final Future<void> Function() _clearRemoteRenderStreamTracks;
  final void Function() _resetLocalVideoAttachment;
  final Future<void> Function() _closePeer;
  final void Function() _clearVideoTransports;
  final TransportMode? Function(dynamic raw) _parseMode;
  final void Function() _bumpSessionEpoch;

  CallPeerSessionController({
    required SignalingService signaling,
    required CallVideoState videoState,
    required void Function(String message) log,
    required void Function(String error) onError,
    required void Function(String? trackId) onRemoteVideoTrackChanged,
    required void Function(String? codec) onVideoCodecChanged,
    required RTCPeerConnection? Function() getPeer,
    required void Function(RTCPeerConnection? peer) setPeer,
    required void Function(String? value) setPeerId,
    required void Function(String? value) setCallId,
    required TransportMode? Function() getMode,
    required void Function(TransportMode? value) setMode,
    required CallMediaType Function() getMediaType,
    required void Function(CallMediaType value) setMediaType,
    required void Function(bool value) setStartedAsOfferer,
    required bool Function() getRemoteDescriptionSet,
    required void Function(bool value) setRemoteDescriptionSet,
    required void Function(bool value) setIceConnected,
    required void Function(bool value) setRemoteTrackSeen,
    required void Function(bool value) setRemoteAudioTrackSeen,
    required void Function(bool value) setRemoteAudioFlowSeen,
    required void Function(bool value) setRemoteVideoTrackSeen,
    required void Function(bool value) setConnected,
    required void Function(bool value) setMediaFlowNotified,
    required void Function(bool value) setRenegotiationInProgress,
    required void Function(String? value) setPendingRenegotiationReason,
    required List<RTCIceCandidate> Function() getPendingIce,
    required void Function(int? value) setPendingRemoteVideoFlowAckVersion,
    required void Function(bool value) setRemoteVideoEnabled,
    required void Function(bool value) setRemoteVideoFlowSeen,
    required CallMediaStreamController mediaStreamController,
    required Future<Map<String, dynamic>> Function(TransportMode mode)
    buildRtcConfig,
    required void Function(RTCPeerConnection peer) bindPeerEvents,
    required bool Function() getMuted,
    required bool Function() getSpeakerOn,
    required bool Function() getStartedAsOfferer,
    required Future<void> Function(bool enabled) applySpeakerOn,
    required Future<void> Function() syncLocalMediaTracks,
    required Future<void> Function() refreshVideoChannelHandles,
    required Future<void> Function() ensureVideoTransceiverDirectionsForRole,
    required RTCSessionDescription Function(RTCSessionDescription description)
    withPreferredVideoCodecs,
    required void Function(String? sdp) captureExpectedVideoMidsForLocalOffer,
    required void Function(String? sdp) captureExpectedVideoMidsForRemoteOffer,
    required void Function(String? sdp) captureExpectedVideoMidsForRemoteAnswer,
    required void Function(String? sdp) updateNegotiatedVideoCodec,
    required void Function() armPostIceRecoveryFlowWatch,
    required void Function(String reason) resetPostIceRecoveryFlowWatch,
    required void Function() stopAudioStatsPolling,
    required void Function() cancelMediaFlowFallback,
    required void Function() cancelIceRecoveryTimers,
    required void Function() cancelVideoUplinkFallback,
    required void Function() cancelRemoteVideoFlowRecovery,
    required void Function() cancelPendingVideoStateAck,
    required void Function() cancelVideoQualityUpgrade,
    required Future<void> Function() disposeRemoteStream,
    required Future<void> Function() clearRemoteRenderStreamTracks,
    required void Function() resetLocalVideoAttachment,
    required Future<void> Function() closePeer,
    required void Function() clearVideoTransports,
    required TransportMode? Function(dynamic raw) parseMode,
    required void Function() bumpSessionEpoch,
  }) : _signaling = signaling,
       _videoState = videoState,
       _log = log,
       _onError = onError,
       _onRemoteVideoTrackChanged = onRemoteVideoTrackChanged,
       _onVideoCodecChanged = onVideoCodecChanged,
       _getPeer = getPeer,
       _setPeer = setPeer,
       _setPeerId = setPeerId,
       _setCallId = setCallId,
       _getMode = getMode,
       _setMode = setMode,
       _getMediaType = getMediaType,
       _setMediaType = setMediaType,
       _setStartedAsOfferer = setStartedAsOfferer,
       _getRemoteDescriptionSet = getRemoteDescriptionSet,
       _setRemoteDescriptionSet = setRemoteDescriptionSet,
       _setIceConnected = setIceConnected,
       _setRemoteTrackSeen = setRemoteTrackSeen,
       _setRemoteAudioTrackSeen = setRemoteAudioTrackSeen,
       _setRemoteAudioFlowSeen = setRemoteAudioFlowSeen,
       _setRemoteVideoTrackSeen = setRemoteVideoTrackSeen,
       _setConnected = setConnected,
       _setMediaFlowNotified = setMediaFlowNotified,
       _setRenegotiationInProgress = setRenegotiationInProgress,
       _setPendingRenegotiationReason = setPendingRenegotiationReason,
       _getPendingIce = getPendingIce,
       _setPendingRemoteVideoFlowAckVersion =
           setPendingRemoteVideoFlowAckVersion,
       _setRemoteVideoEnabled = setRemoteVideoEnabled,
       _setRemoteVideoFlowSeen = setRemoteVideoFlowSeen,
       _mediaStreamController = mediaStreamController,
       _buildRtcConfig = buildRtcConfig,
       _bindPeerEvents = bindPeerEvents,
       _getMuted = getMuted,
       _getSpeakerOn = getSpeakerOn,
       _getStartedAsOfferer = getStartedAsOfferer,
       _applySpeakerOn = applySpeakerOn,
       _syncLocalMediaTracks = syncLocalMediaTracks,
       _refreshVideoChannelHandles = refreshVideoChannelHandles,
       _ensureVideoTransceiverDirectionsForRole =
           ensureVideoTransceiverDirectionsForRole,
       _withPreferredVideoCodecs = withPreferredVideoCodecs,
       _captureExpectedVideoMidsForLocalOffer =
           captureExpectedVideoMidsForLocalOffer,
       _captureExpectedVideoMidsForRemoteOffer =
           captureExpectedVideoMidsForRemoteOffer,
       _captureExpectedVideoMidsForRemoteAnswer =
           captureExpectedVideoMidsForRemoteAnswer,
       _updateNegotiatedVideoCodec = updateNegotiatedVideoCodec,
       _armPostIceRecoveryFlowWatch = armPostIceRecoveryFlowWatch,
       _resetPostIceRecoveryFlowWatch = resetPostIceRecoveryFlowWatch,
       _stopAudioStatsPolling = stopAudioStatsPolling,
       _cancelMediaFlowFallback = cancelMediaFlowFallback,
       _cancelIceRecoveryTimers = cancelIceRecoveryTimers,
       _cancelVideoUplinkFallback = cancelVideoUplinkFallback,
       _cancelRemoteVideoFlowRecovery = cancelRemoteVideoFlowRecovery,
       _cancelPendingVideoStateAck = cancelPendingVideoStateAck,
       _cancelVideoQualityUpgrade = cancelVideoQualityUpgrade,
       _disposeRemoteStream = disposeRemoteStream,
       _clearRemoteRenderStreamTracks = clearRemoteRenderStreamTracks,
       _resetLocalVideoAttachment = resetLocalVideoAttachment,
       _closePeer = closePeer,
       _clearVideoTransports = clearVideoTransports,
       _parseMode = parseMode,
       _bumpSessionEpoch = bumpSessionEpoch;

  bool _shouldOfferVideo() => _getMediaType() == CallMediaType.video;

  Future<String?> _safeGetLocalDescriptionType(
    RTCPeerConnection peer, {
    String? context,
  }) async {
    try {
      return (await peer.getLocalDescription())?.type;
    } catch (error) {
      _log(
        'localDescription:unavailable'
        '${context == null ? "" : " context=$context"} error=$error',
      );
      return null;
    }
  }

  Future<void> startOutgoing({
    required String peerId,
    required String callId,
    required TransportMode mode,
    required CallMediaType mediaType,
  }) async {
    _bumpSessionEpoch();
    _setPeerId(peerId);
    _setCallId(callId);
    _setMode(mode);
    _setMediaType(mediaType);
    _setStartedAsOfferer(true);
    _setRemoteDescriptionSet(false);
    _setIceConnected(false);
    _setRemoteTrackSeen(false);
    _setRemoteAudioTrackSeen(false);
    _setRemoteAudioFlowSeen(false);
    _resetLocalVideoAttachment();
    _setRemoteVideoTrackSeen(false);
    _setRemoteVideoFlowSeen(false);
    _setRemoteVideoEnabled(false);
    _onRemoteVideoTrackChanged(null);
    _onVideoCodecChanged(null);
    _setConnected(false);
    _setMediaFlowNotified(false);
    _resetPeerRuntimeBookkeeping();
    _clearPeerRuntimeSchedulers();
    _signalHandlingQueue = Future<void>.value();

    _log('startOutgoing:preparePeerConnection begin');
    await preparePeerConnection();
    _log('startOutgoing:preparePeerConnection done');

    final peer = _getPeer();
    if (peer == null) {
      throw StateError('Peer connection not prepared');
    }

    _log('startOutgoing:createOffer begin');
    final rawOffer = await peer.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': _shouldOfferVideo(),
    });
    _log('startOutgoing:createOffer done');
    final offer = _withPreferredVideoCodecs(rawOffer);
    _log('sdp:local-offer ${sdpMediaSummary(offer.sdp)}');
    _log('startOutgoing:setLocalDescription begin');
    await peer.setLocalDescription(offer);
    _log('startOutgoing:setLocalDescription done');
    _captureExpectedVideoMidsForLocalOffer(offer.sdp);

    _log('startOutgoing:sendOffer begin');
    await _signaling.sendOffer(peerId, {
      ...offer.toMap(),
      'callId': callId,
      'signalScope': 'call',
      'transportMode': mode.name,
      'mediaType': mediaType.name,
    });
    _log('startOutgoing:sendOffer done');
    _log('offer:sent mode=${mode.name}');
  }

  Future<void> handleSignal(SignalingMessage message) async {
    final completer = Completer<void>();
    final previous = _signalHandlingQueue;
    _signalHandlingQueue = completer.future;
    try {
      await previous;
      final peerId = message.fromPeerId;
      final data = message.data;
      final callId = data['callId']?.toString();
      final mode = _parseMode(data['transportMode']);

      if (callId == null || callId.isEmpty) {
        _log('signal:drop missing callId type=${message.type}');
        return;
      }

      _setPeerId(peerId);
      _setCallId(callId);
      _setMode(_getMode() ?? mode ?? TransportMode.direct);
      _log('signal:serial enter type=${message.type} callId=$callId');
      if (message.type == 'offer') {
        await _handleOffer(
          peerId: peerId,
          callId: callId,
          mode: mode ?? TransportMode.direct,
          data: data,
        );
        return;
      }

      if (message.type == 'answer') {
        await _handleAnswer(data);
        return;
      }

      if (message.type == 'ice') {
        await _handleIce(data);
        return;
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }

  Future<void> resetPeerForIncomingOffer(
    TransportMode mode, {
    bool forceRecreate = false,
  }) async {
    RTCSignalingState? signalingState;
    String? localDescriptionType;
    final peer = _getPeer();
    if (peer != null) {
      signalingState = await peer.getSignalingState();
      localDescriptionType = await _safeGetLocalDescriptionType(
        peer,
        context: 'resetPeerForIncomingOffer',
      );
    }

    var requiresRecreate =
        CallSignalingInvariants.shouldRecreatePeerForIncomingOffer(
          hasPeer: peer != null,
          modeChanged: _getMode() != mode,
          remoteDescriptionSet: _getRemoteDescriptionSet(),
          signalingState: signalingState,
          localDescriptionType: localDescriptionType,
        );
    final sameSessionRecoveryOffer =
        peer != null && _getMode() == mode && _getRemoteDescriptionSet();
    if (forceRecreate && peer != null) {
      requiresRecreate = true;
    }
    if (requiresRecreate && sameSessionRecoveryOffer && !forceRecreate) {
      requiresRecreate = false;
      _log(
        'offer:recreate suppressed same-session '
        'signalingState=$signalingState '
        'localDescriptionType=$localDescriptionType',
      );
    }
    if (requiresRecreate) {
      _bumpSessionEpoch();
      _log(
        'offer:recreate peer currentMode=${_getMode()?.name ?? 'unknown'} nextMode=${mode.name} '
        'force=$forceRecreate '
        'remoteDescriptionSet=${_getRemoteDescriptionSet()} '
        'signalingState=$signalingState localDescriptionType=$localDescriptionType',
      );
      await disposePeerConnection(disposeRemoteStream: false);
    } else if (peer != null) {
      _log(
        'offer:reusing existing peer mode=${_getMode()?.name ?? mode.name} '
        'signalingState=$signalingState localDescriptionType=$localDescriptionType',
      );
    }

    _setRemoteDescriptionSet(false);
    _setRenegotiationInProgress(false);
    _setPendingRenegotiationReason(null);
    _resetPeerRuntimeBookkeeping();

    if (!requiresRecreate) {
      return;
    }

    _setIceConnected(false);
    _setRemoteTrackSeen(false);
    _setRemoteAudioTrackSeen(false);
    _setRemoteAudioFlowSeen(false);
    _setRemoteVideoTrackSeen(false);
    _setRemoteVideoFlowSeen(false);
    _setRemoteVideoEnabled(false);
    _onRemoteVideoTrackChanged(null);
    _onVideoCodecChanged(null);
    _setConnected(false);
    _setMediaFlowNotified(false);
    _clearPeerRuntimeSchedulers();
  }

  Future<void> disposePeerConnection({bool disposeRemoteStream = true}) async {
    _bumpSessionEpoch();
    _clearPeerRuntimeSchedulers();
    await _closePeer();
    _setPeer(null);
    _clearVideoTransports();
    if (disposeRemoteStream) {
      await _disposeRemoteStream();
    } else {
      await _clearRemoteRenderStreamTracks();
    }
    _setRemoteDescriptionSet(false);
    _setIceConnected(false);
    _setRemoteTrackSeen(false);
    _setRemoteAudioTrackSeen(false);
    _setRemoteAudioFlowSeen(false);
    _resetLocalVideoAttachment();
    _setRemoteVideoTrackSeen(false);
    _setRemoteVideoFlowSeen(false);
    _setRemoteVideoEnabled(false);
    _onVideoCodecChanged(null);
    _setConnected(false);
    _setMediaFlowNotified(false);
    _setRenegotiationInProgress(false);
    _setPendingRenegotiationReason(null);
    _resetPeerRuntimeBookkeeping();
    _offerProcessingGate.reset();
    _signalHandlingQueue = Future<void>.value();
  }

  void _clearPeerRuntimeSchedulers() {
    _cancelIceRecoveryTimers();
    _cancelVideoUplinkFallback();
    _cancelRemoteVideoFlowRecovery();
    _cancelPendingVideoStateAck();
    _stopAudioStatsPolling();
    _cancelMediaFlowFallback();
    _cancelVideoQualityUpgrade();
  }

  void _resetPeerRuntimeBookkeeping() {
    _videoState.pendingVideoFlowVersion = null;
    _setPendingRemoteVideoFlowAckVersion(null);
    _getPendingIce().clear();
  }

  Future<void> preparePeerConnection() async {
    if (_getPeer() != null) {
      return;
    }

    final config = await _buildRtcConfig(_getMode() ?? TransportMode.direct);
    final peer = await createPeerConnection(config);
    _setPeer(peer);
    _bindPeerEvents(peer);
    _log('preparePeerConnection:createInitialLocalStream begin');
    await _mediaStreamController.createInitialLocalStream(muted: _getMuted());
    _log('preparePeerConnection:createInitialLocalStream done');
    await _applySpeakerOn(_getSpeakerOn());
    _log(
      'preparePeerConnection:applySpeakerOn done enabled=${_getSpeakerOn()}',
    );
    _log('preparePeerConnection:addInitialLocalTracks begin');
    await _mediaStreamController.addInitialLocalTracksToPeer(peer);
    _log('preparePeerConnection:addInitialLocalTracks done');

    if (_getStartedAsOfferer() && _getMediaType() == CallMediaType.video) {
      _videoState.videoSendTransceiver = await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      _videoState.videoReceiveTransceiver = _videoState.videoSendTransceiver;
      await _refreshVideoChannelHandles();
      _log(
        'video:bootstrap role=offerer '
        'preNegotiated=false shared=true '
        'sendSenderId=${_videoState.videoSendSender?.senderId} '
        'sendMid=${_videoState.videoSendTransceiver?.mid} '
        'recvMid=${_videoState.videoReceiveTransceiver?.mid}',
      );
    } else if (_getStartedAsOfferer()) {
      _log('video:bootstrap role=offerer deferred until local video enabled');
    } else {
      _log('video:bootstrap role=answerer awaiting remote video transceivers');
    }

    if (_getStartedAsOfferer() && _getMediaType() == CallMediaType.video) {
      await _syncLocalMediaTracks();
      _log('video:bootstrap restored local video after peer recreate');
    }
  }

  Future<void> drainPendingIce() async {
    final peer = _getPeer();
    final pendingIce = _getPendingIce();
    if (peer == null || !_getRemoteDescriptionSet() || pendingIce.isEmpty) {
      return;
    }

    _log('ice:drain count=${pendingIce.length}');
    final queued = List<RTCIceCandidate>.from(pendingIce);
    for (final candidate in queued) {
      try {
        await peer.addCandidate(candidate);
        pendingIce.remove(candidate);
        _log(
          'ice:drain added type=${candidateType(candidate.candidate)} '
          'protocol=${candidateProtocol(candidate.candidate)} '
          'address=${candidateAddress(candidate.candidate)}',
        );
      } catch (error) {
        pendingIce.add(candidate);
        _log(
          'ice:drain re-queued type=${candidateType(candidate.candidate)} '
          'protocol=${candidateProtocol(candidate.candidate)} '
          'address=${candidateAddress(candidate.candidate)} error=$error',
        );
      }
    }
  }

  Future<void> _handleOffer({
    required String peerId,
    required String callId,
    required TransportMode mode,
    required Map<String, dynamic> data,
  }) async {
    final sameSessionRemoteOffer =
        _getPeer() != null && _getMode() == mode && _getRemoteDescriptionSet();
    if (sameSessionRemoteOffer) {
      _resetPostIceRecoveryFlowWatch('remote same-session offer');
      _log('offer:remote same-session accepted');
    }
    _setStartedAsOfferer(false);
    final forceTransportRebuild = data['recoveryTransportRebuild'] == true;
    await resetPeerForIncomingOffer(mode, forceRecreate: forceTransportRebuild);
    _setMode(mode);
    await preparePeerConnection();
    final sdp = data['sdp']?.toString();
    final type = data['type']?.toString() ?? 'offer';
    if (sdp == null || sdp.isEmpty) {
      _onError('Invalid remote offer');
      return;
    }
    _log('sdp:remote-offer ${sdpMediaSummary(sdp)}');
    final offerKey = '$callId:${mode.name}:${sdp.hashCode}';
    await _offerProcessingGate.runIfAccepted(
      offerKey: offerKey,
      log: _log,
      action: () async {
        var peer = _getPeer();
        if (peer == null) {
          return;
        }

        final signalingState = await peer.getSignalingState();
        final localDescriptionType = await _safeGetLocalDescriptionType(
          peer,
          context: 'offer-before-remote',
        );
        if (CallSignalingInvariants.shouldRollbackLocalOfferForIncomingOffer(
          signalingState: signalingState,
          localDescriptionType: localDescriptionType,
        )) {
          await _rollbackLocalOfferIfNeeded(
            peer: peer,
            signalingState: signalingState,
            localDescriptionType: localDescriptionType,
          );
        }

        try {
          await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
        } catch (error) {
          final currentSignalingState = await peer.getSignalingState();
          final currentLocalDescriptionType =
              await _safeGetLocalDescriptionType(
                peer,
                context: 'offer-setRemoteDescription-error',
              );
          if (CallSignalingInvariants.shouldRollbackLocalOfferForIncomingOffer(
                signalingState: currentSignalingState,
                localDescriptionType: currentLocalDescriptionType,
              ) &&
              error.toString().contains('have-local-offer')) {
            await _rollbackLocalOfferIfNeeded(
              peer: peer,
              signalingState: currentSignalingState,
              localDescriptionType: currentLocalDescriptionType,
            );
            await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
            _log(
              'offer:setRemoteDescription retried after rollback '
              'signalingState=$currentSignalingState '
              'localDescriptionType=$currentLocalDescriptionType',
            );
          } else {
            rethrow;
          }
        }
        if (!identical(_getPeer(), peer)) {
          _log('offer:aborted stale-peer after setRemoteDescription');
          return;
        }
        _captureExpectedVideoMidsForRemoteOffer(sdp);
        await _refreshVideoChannelHandles();
        peer = _getPeer();
        if (peer == null) {
          _log('offer:aborted peer missing after refreshVideoChannelHandles');
          return;
        }
        await _ensureVideoTransceiverDirectionsForRole();
        peer = _getPeer();
        if (peer == null) {
          _log(
            'offer:aborted peer missing after ensureVideoTransceiverDirections',
          );
          return;
        }
        if (_getMediaType() == CallMediaType.video) {
          await _syncLocalMediaTracks();
          peer = _getPeer();
          if (peer == null) {
            _log('offer:aborted peer missing after syncLocalMediaTracks');
            return;
          }
          await _refreshVideoChannelHandles();
          peer = _getPeer();
          if (peer == null) {
            _log('offer:aborted peer missing after video handles post-sync');
            return;
          }
          await _ensureVideoTransceiverDirectionsForRole();
          peer = _getPeer();
          if (peer == null) {
            _log('offer:aborted peer missing after video directions post-sync');
            return;
          }
          _log('video:offer applied restored local video sender');
        }
        _setRemoteDescriptionSet(true);
        _log('offer:remote description set');
        await drainPendingIce();
        peer = _getPeer();
        if (peer == null) {
          _log('offer:aborted peer missing before createAnswer');
          return;
        }
        final answerSignalingState = await peer.getSignalingState();
        final answerLocalDescriptionType = await _safeGetLocalDescriptionType(
          peer,
          context: 'offer-before-answer',
        );
        final canAnswer = CallSignalingInvariants.canCreateAnswer(
          signalingState: answerSignalingState,
          localDescriptionType: answerLocalDescriptionType,
        );
        if (!canAnswer) {
          _log(
            'answer:skip signalingState=$answerSignalingState '
            'localDescriptionType=$answerLocalDescriptionType',
          );
          return;
        }
        final rawAnswer = await peer.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': _shouldOfferVideo(),
        });
        final answer = _withPreferredVideoCodecs(rawAnswer);
        _log('sdp:local-answer ${sdpMediaSummary(answer.sdp)}');
        try {
          await peer.setLocalDescription(answer);
        } catch (error) {
          final currentState = await peer.getSignalingState();
          final currentLocalType = await _safeGetLocalDescriptionType(
            peer,
            context: 'answer-setLocalDescription-error',
          );
          _log(
            'answer:setLocalDescription failed '
            'state=$currentState localDescriptionType=$currentLocalType error=$error',
          );
          if (CallSignalingInvariants.shouldIgnoreSetDescriptionErrorAsLate(
            signalingState: currentState,
            localDescriptionType: currentLocalType,
            error: error,
          )) {
            return;
          }
          _onError('Не удалось применить answer локально: $error');
          return;
        }
        _updateNegotiatedVideoCodec(answer.sdp);
        await _signaling.sendAnswer(peerId, {
          ...answer.toMap(),
          'callId': callId,
          'signalScope': 'call',
          'transportMode': mode.name,
          'mediaType': _getMediaType().name,
        });
        _log('answer:sent mode=${mode.name}');
        _armPostIceRecoveryFlowWatch();
      },
    );
  }

  Future<void> _rollbackLocalOfferIfNeeded({
    required RTCPeerConnection peer,
    required RTCSignalingState? signalingState,
    required String? localDescriptionType,
  }) async {
    try {
      await peer.setLocalDescription(RTCSessionDescription('', 'rollback'));
      _log(
        'offer:rollback local pending offer '
        'signalingState=$signalingState '
        'localDescriptionType=$localDescriptionType',
      );
    } catch (error) {
      _log(
        'offer:rollback skipped signalingState=$signalingState '
        'localDescriptionType=$localDescriptionType error=$error',
      );
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    final sdp = data['sdp']?.toString();
    final type = data['type']?.toString() ?? 'answer';
    final peer = _getPeer();
    if (peer == null || sdp == null || sdp.isEmpty) {
      return;
    }
    _log('sdp:remote-answer ${sdpMediaSummary(sdp)}');
    final signalingState = await peer.getSignalingState();
    RTCSessionDescription? localDescription;
    try {
      localDescription = await peer.getLocalDescription();
    } catch (error) {
      _log('localDescription:unavailable context=answer-handle error=$error');
    }
    final isWaitingForAnswer = CallSignalingInvariants.isWaitingForAnswer(
      signalingState: signalingState,
      localDescriptionType: localDescription?.type,
    );
    if (!isWaitingForAnswer) {
      _log(
        'answer:ignored signalingState=$signalingState localDescriptionType=${localDescription?.type}',
      );
      return;
    }
    try {
      await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
      _captureExpectedVideoMidsForRemoteAnswer(sdp);
      _updateNegotiatedVideoCodec(sdp);
      await _refreshVideoChannelHandles();
    } catch (error) {
      final currentState = await peer.getSignalingState();
      final localType = await _safeGetLocalDescriptionType(
        peer,
        context: 'answer-setRemoteDescription-error',
      );
      if (CallSignalingInvariants.shouldIgnoreSetDescriptionErrorAsLate(
        signalingState: currentState,
        localDescriptionType: localType,
        error: error,
      )) {
        _log(
          'answer:ignored late signalingState=$currentState '
          'localDescriptionType=$localType error=$error',
        );
        return;
      }
      rethrow;
    }
    _setRemoteDescriptionSet(true);
    _log('answer:remote description set');
    await drainPendingIce();
    _log('answer:applied');
    _armPostIceRecoveryFlowWatch();
  }

  Future<void> _handleIce(Map<String, dynamic> data) async {
    final peer = _getPeer();
    if (peer == null) {
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
    if (!_getRemoteDescriptionSet()) {
      _getPendingIce().add(rtcCandidate);
      _log(
        'ice:queued type=${candidateType(candidate)} '
        'protocol=${candidateProtocol(candidate)} '
        'address=${candidateAddress(candidate)} remote description not ready',
      );
      return;
    }
    try {
      await peer.addCandidate(rtcCandidate);
      _log(
        'ice:added type=${candidateType(candidate)} '
        'protocol=${candidateProtocol(candidate)} '
        'address=${candidateAddress(candidate)}',
      );
    } catch (error) {
      _getPendingIce().add(rtcCandidate);
      _log(
        'ice:re-queued type=${candidateType(candidate)} '
        'protocol=${candidateProtocol(candidate)} '
        'address=${candidateAddress(candidate)} addCandidate error=$error',
      );
    }
  }
}
