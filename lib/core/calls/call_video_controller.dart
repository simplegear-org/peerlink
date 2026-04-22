import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import 'call_models.dart';
import 'call_video_state.dart';

class CallVideoController {
  final SignalingService _signaling;
  final CallVideoState _state;
  final void Function(String message) _log;
  final List<String> Function(String? sdp) _extractVideoMids;
  final void Function(bool active) _onRemoteVideoFlowChanged;

  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final bool Function() _getStartedAsOfferer;
  final CallMediaType Function() _getMediaType;
  final bool Function() _getLocalVideoTrackAttached;
  final RTCPeerConnection? Function() _getPeer;

  const CallVideoController({
    required SignalingService signaling,
    required CallVideoState state,
    required void Function(String message) log,
    required List<String> Function(String? sdp) extractVideoMids,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required bool Function() getStartedAsOfferer,
    required CallMediaType Function() getMediaType,
    required bool Function() getLocalVideoTrackAttached,
    required RTCPeerConnection? Function() getPeer,
  })  : _signaling = signaling,
        _state = state,
        _log = log,
        _extractVideoMids = extractVideoMids,
        _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
        _getPeerId = getPeerId,
        _getCallId = getCallId,
        _getStartedAsOfferer = getStartedAsOfferer,
        _getMediaType = getMediaType,
        _getLocalVideoTrackAttached = getLocalVideoTrackAttached,
        _getPeer = getPeer;

  void scheduleVideoUplinkFallback(int version) {
    cancelVideoUplinkFallback();
    _state.pendingVideoFlowVersion = version;
    _log('video:fallback disabled version=$version');
  }

  void cancelVideoUplinkFallback() {
    if (_state.videoUplinkFallbackTimer?.isActive ?? false) {
      _log('video:fallback canceled');
    }
    _state.videoUplinkFallbackTimer?.cancel();
    _state.videoUplinkFallbackTimer = null;
    _state.pendingVideoFlowVersion = null;
  }

  Future<void> sendVideoState({
    required bool enabled,
    required String peerId,
    required String callId,
  }) async {
    final version = _state.videoStateVersion + 1;
    _state.videoStateVersion = version;
    _state.pendingVideoStateVersion = version;
    _state.pendingVideoStateEnabled = enabled;
    _state.pendingVideoStateAttempts = 0;
    await sendVideoStateAttempt(
      enabled: enabled,
      peerId: peerId,
      callId: callId,
      version: version,
    );
    if (enabled) {
      scheduleVideoUplinkFallback(version);
    } else {
      cancelVideoUplinkFallback();
    }
  }

  Future<void> handleRemoteVideoState({
    required bool enabled,
    required int version,
    required String peerId,
    required String callId,
  }) async {
    await _signaling.sendSignal(peerId, 'call_video_state_ack', {
      'callId': callId,
      'signalScope': 'call',
      'enabled': enabled,
      'version': version,
    });
    _state.remoteVideoEnabled = enabled;
    if (enabled) {
      _state.pendingRemoteVideoFlowAckVersion = version;
      _state.remoteVideoFlowSeen = false;
      _state.lastInboundVideoBytes = -1;
      _state.lastInboundVideoFramesDecoded = -1;
      _onRemoteVideoFlowChanged(false);
      _log('video:remote state enabled version=$version awaiting-flow');
      return;
    }
    _state.pendingRemoteVideoFlowAckVersion = null;
    _state.lastInboundVideoBytes = -1;
    _state.lastInboundVideoFramesDecoded = -1;
    if (_state.remoteVideoFlowSeen) {
      _state.remoteVideoFlowSeen = false;
      _onRemoteVideoFlowChanged(false);
    }
    _log('video:remote state disabled version=$version');
  }

  void handleVideoStateAck({
    required bool enabled,
    required int version,
  }) {
    final pendingVersion = _state.pendingVideoStateVersion;
    final pendingEnabled = _state.pendingVideoStateEnabled;
    if (pendingVersion != version || pendingEnabled != enabled) {
      _log(
        'video:ack ignored version=$version enabled=$enabled '
        'pendingVersion=$pendingVersion pendingEnabled=$pendingEnabled',
      );
      return;
    }
    _log('video:ack received version=$version enabled=$enabled');
    cancelPendingVideoStateAck();
  }

  void handleVideoFlowAck({required int version}) {
    if (_state.pendingVideoFlowVersion != version) {
      _log(
        'video:flow ack ignored version=$version '
        'pendingVersion=${_state.pendingVideoFlowVersion}',
      );
      return;
    }
    _log('video:flow ack received version=$version');
    cancelVideoUplinkFallback();
    scheduleVideoQualityUpgrade();
  }

  Future<void> sendVideoStateAttempt({
    required bool enabled,
    required String peerId,
    required String callId,
    required int version,
  }) async {
    _state.pendingVideoStateAttempts += 1;
    _log(
      'video:state send enabled=$enabled version=$version '
      'attempt=${_state.pendingVideoStateAttempts}',
    );
    await _signaling.sendSignal(peerId, 'call_video_state', {
      'callId': callId,
      'signalScope': 'call',
      'enabled': enabled,
      'version': version,
    });
    _state.videoStateAckTimer?.cancel();
    _state.videoStateAckTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_state.pendingVideoStateVersion != version ||
          _state.pendingVideoStateEnabled != enabled) {
        return;
      }
      if (_state.pendingVideoStateAttempts >= 5) {
        _log('video:ack timeout enabled=$enabled version=$version');
        cancelPendingVideoStateAck();
        return;
      }
      final currentPeerId = _getPeerId();
      final currentCallId = _getCallId();
      if (currentPeerId == null || currentCallId == null) {
        cancelPendingVideoStateAck();
        return;
      }
      unawaited(sendVideoStateAttempt(
        enabled: enabled,
        peerId: currentPeerId,
        callId: currentCallId,
        version: version,
      ));
    });
  }

  Future<void> applyInitialVideoQualityProfile() async {
    final sender = _state.videoSendSender;
    if (sender == null) {
      return;
    }
    try {
      final parameters = sender.parameters;
      final encodings = parameters.encodings ?? <RTCRtpEncoding>[];
      if (encodings.isEmpty) {
        encodings.add(
          RTCRtpEncoding(
            active: true,
            maxBitrate: 180000,
            minBitrate: 70000,
            maxFramerate: 12,
            scaleResolutionDownBy: 2.0,
          ),
        );
      } else {
        final encoding = encodings.first;
        encoding.active = true;
        encoding.maxBitrate = 180000;
        encoding.minBitrate = 70000;
        encoding.maxFramerate = 12;
        encoding.scaleResolutionDownBy = 2.0;
      }
      parameters.encodings = encodings;
      await sender.setParameters(parameters);
      _log('video:quality profile=initial bitrate=180000 fps=12 scale=2.0');
    } catch (error) {
      _log('video:quality initial failed error=$error');
    }
  }

  void scheduleVideoQualityUpgrade() {
    cancelVideoQualityUpgrade();
    _state.videoQualityUpgradeTimer = Timer(
      const Duration(seconds: 4),
      () => unawaited(applyUpgradedVideoQualityProfile()),
    );
    _log('video:quality upgrade scheduled delayMs=4000');
  }

  void cancelVideoQualityUpgrade() {
    _state.videoQualityUpgradeTimer?.cancel();
    _state.videoQualityUpgradeTimer = null;
  }

  Future<void> applyUpgradedVideoQualityProfile() async {
    _state.videoQualityUpgradeTimer = null;
    if (_getMediaType() != CallMediaType.video || !_getLocalVideoTrackAttached()) {
      _log('video:quality upgrade skipped no-local-video');
      return;
    }
    final sender = _state.videoSendSender;
    if (sender == null) {
      return;
    }
    try {
      final parameters = sender.parameters;
      final encodings = parameters.encodings ?? <RTCRtpEncoding>[];
      if (encodings.isEmpty) {
        encodings.add(
          RTCRtpEncoding(
            active: true,
            maxBitrate: 450000,
            minBitrate: 120000,
            maxFramerate: 18,
            scaleResolutionDownBy: 1.0,
          ),
        );
      } else {
        final encoding = encodings.first;
        encoding.active = true;
        encoding.maxBitrate = 450000;
        encoding.minBitrate = 120000;
        encoding.maxFramerate = 18;
        encoding.scaleResolutionDownBy = 1.0;
      }
      parameters.encodings = encodings;
      await sender.setParameters(parameters);
      _log('video:quality profile=upgraded bitrate=450000 fps=18 scale=1.0');
    } catch (error) {
      _log('video:quality upgrade failed error=$error');
    }
  }

  void cancelPendingVideoStateAck() {
    _state.videoStateAckTimer?.cancel();
    _state.videoStateAckTimer = null;
    _state.pendingVideoStateVersion = null;
    _state.pendingVideoStateEnabled = null;
    _state.pendingVideoStateAttempts = 0;
  }

  Future<void> refreshVideoChannelHandles() async {
    final peer = _getPeer();
    if (peer == null) {
      _state.videoSendTransceiver = null;
      _state.videoReceiveTransceiver = null;
      _state.videoSendSender = null;
      return;
    }
    try {
      final transceivers = List<RTCRtpTransceiver>.from(
        await peer.getTransceivers(),
      );
      final currentSendSenderId = _state.videoSendSender?.senderId;
      RTCRtpTransceiver? sendTransceiver;
      RTCRtpTransceiver? receiveTransceiver;
      final orderedVideoTransceivers = <RTCRtpTransceiver>[];

      if (_state.expectedVideoSendMid != null ||
          _state.expectedVideoReceiveMid != null) {
        for (final transceiver in transceivers) {
          if (_state.expectedVideoSendMid != null &&
              transceiver.mid == _state.expectedVideoSendMid) {
            sendTransceiver ??= transceiver;
          }
          if (_state.expectedVideoReceiveMid != null &&
              transceiver.mid == _state.expectedVideoReceiveMid) {
            receiveTransceiver ??= transceiver;
          }
        }
      }

      for (final transceiver in transceivers) {
        final mediaKind =
            transceiver.receiver.track?.kind ?? transceiver.sender.track?.kind;
        if (mediaKind != 'video' && mediaKind != null && mediaKind.isNotEmpty) {
          continue;
        }
        orderedVideoTransceivers.add(transceiver);
        final direction = await safeGetDirection(transceiver);
        final currentDirection = await safeGetCurrentDirection(transceiver);

        if (currentSendSenderId != null &&
            currentSendSenderId.isNotEmpty &&
            transceiver.sender.senderId == currentSendSenderId) {
          sendTransceiver = transceiver;
          continue;
        }

        if (_isSendSideDirection(direction) ||
            _isSendSideDirection(currentDirection)) {
          sendTransceiver ??= transceiver;
          continue;
        }
        if (_isReceiveSideDirection(direction) ||
            _isReceiveSideDirection(currentDirection)) {
          receiveTransceiver ??= transceiver;
        }
      }

      if (orderedVideoTransceivers.length >= 2) {
        if (_getStartedAsOfferer()) {
          sendTransceiver ??= orderedVideoTransceivers[0];
          receiveTransceiver ??= orderedVideoTransceivers[1];
        } else {
          receiveTransceiver ??= orderedVideoTransceivers[0];
          sendTransceiver ??= orderedVideoTransceivers[1];
        }
      }

      if (sendTransceiver == null || receiveTransceiver == null) {
        final videoLike = transceivers.where((transceiver) {
          final senderKind = transceiver.sender.track?.kind;
          final receiverKind = transceiver.receiver.track?.kind;
          return senderKind == 'video' || receiverKind == 'video';
        }).toList();
        if (sendTransceiver == null && videoLike.isNotEmpty) {
          sendTransceiver = videoLike.first;
        }
        if (receiveTransceiver == null && videoLike.length > 1) {
          receiveTransceiver = videoLike.firstWhere(
            (candidate) => !identical(candidate, sendTransceiver),
            orElse: () => videoLike.last,
          );
        } else if (receiveTransceiver == null && sendTransceiver != null) {
          receiveTransceiver = sendTransceiver;
        }
      }

      _state.videoSendTransceiver = sendTransceiver;
      _state.videoReceiveTransceiver = receiveTransceiver;
      _state.videoSendSender = sendTransceiver?.sender;
      _log(
        'video:handles refreshed '
        'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
        'videoCount=${orderedVideoTransceivers.length} '
        'expectedSendMid=${_state.expectedVideoSendMid} '
        'expectedRecvMid=${_state.expectedVideoReceiveMid} '
        'sendSenderId=${_state.videoSendSender?.senderId} '
        'sendMid=${_state.videoSendTransceiver?.mid} '
        'sendTrack=${_state.videoSendSender?.track?.kind} '
        'recvMid=${_state.videoReceiveTransceiver?.mid} '
        'recvTrack=${_state.videoReceiveTransceiver?.receiver.track?.kind}',
      );
    } catch (error) {
      _log('video:refresh handles failed error=$error');
    }
  }

  Future<TransceiverDirection?> safeGetDirection(
    RTCRtpTransceiver transceiver,
  ) async {
    try {
      return await transceiver.getDirection();
    } catch (_) {
      return null;
    }
  }

  Future<TransceiverDirection?> safeGetCurrentDirection(
    RTCRtpTransceiver transceiver,
  ) async {
    try {
      return await transceiver.getCurrentDirection();
    } catch (_) {
      return null;
    }
  }

  bool _isSendSideDirection(TransceiverDirection? direction) {
    return direction == TransceiverDirection.SendOnly ||
        direction == TransceiverDirection.SendRecv;
  }

  bool _isReceiveSideDirection(TransceiverDirection? direction) {
    return direction == TransceiverDirection.RecvOnly ||
        direction == TransceiverDirection.SendRecv;
  }

  void captureExpectedVideoMidsForLocalOffer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length >= 2) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[1];
      _log(
        'video:mids local-offer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  void captureExpectedVideoMidsForRemoteOffer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length >= 2) {
      _state.expectedVideoReceiveMid = mids[0];
      _state.expectedVideoSendMid = mids[1];
      _log(
        'video:mids remote-offer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  void captureExpectedVideoMidsForRemoteAnswer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length >= 2) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[1];
      _log(
        'video:mids remote-answer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  Future<void> ensureVideoTransceiverDirectionsForRole() async {
    final sendTransceiver = _state.videoSendTransceiver;
    final receiveTransceiver = _state.videoReceiveTransceiver;
    if (sendTransceiver == null && receiveTransceiver == null) {
      return;
    }
    try {
      if (sendTransceiver != null) {
        await sendTransceiver.setDirection(TransceiverDirection.SendOnly);
      }
      if (receiveTransceiver != null) {
        await receiveTransceiver.setDirection(TransceiverDirection.RecvOnly);
      }
      _log(
        'video:directions enforced '
        'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
        'sendMid=${sendTransceiver?.mid} recvMid=${receiveTransceiver?.mid}',
      );
    } catch (error) {
      _log('video:directions enforce failed error=$error');
    }
  }
}
