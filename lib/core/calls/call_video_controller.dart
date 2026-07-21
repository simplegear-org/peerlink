import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import 'call_media_stream_controller.dart';
import 'call_media_stats_utils.dart';
import 'call_models.dart';
import 'call_video_state.dart';

class _VideoQualityProfile {
  const _VideoQualityProfile({
    required this.name,
    required this.maxBitrate,
    required this.maxFramerate,
    required this.scaleResolutionDownBy,
  });

  final String name;
  final int maxBitrate;
  final int maxFramerate;
  final double scaleResolutionDownBy;
}

class _VideoSdpSection {
  const _VideoSdpSection({required this.mid, required this.direction});

  final String mid;
  final String direction;
}

class CallVideoController {
  static const List<_VideoQualityProfile> _qualityProfiles =
      <_VideoQualityProfile>[
        _VideoQualityProfile(
          name: 'floor',
          maxBitrate: 220000,
          maxFramerate: 12,
          scaleResolutionDownBy: 2.0,
        ),
        _VideoQualityProfile(
          name: 'safe',
          maxBitrate: 450000,
          maxFramerate: 20,
          scaleResolutionDownBy: 1.0,
        ),
        _VideoQualityProfile(
          name: 'balanced',
          maxBitrate: 750000,
          maxFramerate: 24,
          scaleResolutionDownBy: 1.0,
        ),
        _VideoQualityProfile(
          name: 'standard',
          maxBitrate: 1100000,
          maxFramerate: 24,
          scaleResolutionDownBy: 1.0,
        ),
      ];
  static const int _initialQualityIndex = 1;
  static const int _flowAckUpgradeQualityIndex = 2;
  static const Duration _flowAckUpgradeDelay = Duration(seconds: 4);
  static const int _stablePollsBeforeUpgrade = 10;
  static const int _poorPollsBeforeDowngrade = 2;
  static const Duration _videoNetworkDiagnosticThrottle = Duration(seconds: 5);

  final SignalingService _signaling;
  final CallVideoState _state;
  final void Function(String message) _log;
  final List<String> Function(String? sdp) _extractVideoMids;
  final void Function(bool active) _onRemoteVideoFlowChanged;
  final Future<void> Function(String reason) _onRemoteVideoFlowStalled;

  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final bool Function() _getStartedAsOfferer;
  final CallMediaType Function() _getMediaType;
  final bool Function() _getLocalVideoTrackAttached;
  final RTCPeerConnection? Function() _getPeer;
  final int Function() _getSessionEpoch;
  final CallMediaStreamController _mediaStreamController;

  const CallVideoController({
    required SignalingService signaling,
    required CallMediaStreamController mediaStreamController,
    required CallVideoState state,
    required void Function(String message) log,
    required List<String> Function(String? sdp) extractVideoMids,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required Future<void> Function(String reason) onRemoteVideoFlowStalled,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required bool Function() getStartedAsOfferer,
    required CallMediaType Function() getMediaType,
    required bool Function() getLocalVideoTrackAttached,
    required RTCPeerConnection? Function() getPeer,
    required int Function() getSessionEpoch,
  }) : _signaling = signaling,
       _state = state,
       _log = log,
       _extractVideoMids = extractVideoMids,
       _onRemoteVideoFlowChanged = onRemoteVideoFlowChanged,
       _onRemoteVideoFlowStalled = onRemoteVideoFlowStalled,
       _getPeerId = getPeerId,
       _getCallId = getCallId,
       _getStartedAsOfferer = getStartedAsOfferer,
       _getMediaType = getMediaType,
       _getLocalVideoTrackAttached = getLocalVideoTrackAttached,
       _getPeer = getPeer,
       _getSessionEpoch = getSessionEpoch,
       _mediaStreamController = mediaStreamController;

  void scheduleVideoUplinkFallback(int version) {
    cancelVideoUplinkFallback();
    _state.pendingVideoFlowVersion = version;
    _log('video:fallback disabled version=$version');
  }

  void scheduleRemoteVideoFlowRecovery(int version) {
    cancelRemoteVideoFlowRecovery();
    _state.pendingRemoteVideoRecoveryVersion = version;
    final expectedEpoch = _getSessionEpoch();
    _state.remoteVideoFlowRecoveryTimer = Timer(
      const Duration(seconds: 4),
      () async {
        if (_getSessionEpoch() != expectedEpoch) {
          return;
        }
        if (_state.pendingRemoteVideoRecoveryVersion != version ||
            !_state.remoteVideoEnabled ||
            _state.remoteVideoFlowSeen) {
          return;
        }
        _log('video:flow recovery timeout version=$version');
        await _onRemoteVideoFlowStalled(
          'Remote video flow timeout version=$version',
        );
      },
    );
  }

  void cancelRemoteVideoFlowRecovery() {
    _state.remoteVideoFlowRecoveryTimer?.cancel();
    _state.remoteVideoFlowRecoveryTimer = null;
    _state.pendingRemoteVideoRecoveryVersion = null;
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
    if (version <= _state.remoteVideoStateVersion) {
      _log(
        'video:remote state ignored enabled=$enabled version=$version '
        'lastVersion=${_state.remoteVideoStateVersion}',
      );
      return;
    }
    _state.remoteVideoStateVersion = version;
    _state.remoteVideoEnabled = enabled;
    if (enabled) {
      _state.pendingRemoteVideoFlowAckVersion = version;
      _state.remoteVideoFlowSeen = false;
      _state.lastInboundVideoBytes = -1;
      _state.lastInboundVideoFramesDecoded = -1;
      _onRemoteVideoFlowChanged(false);
      scheduleRemoteVideoFlowRecovery(version);
      _log('video:remote state enabled version=$version awaiting-flow');
      return;
    }
    cancelRemoteVideoFlowRecovery();
    _state.pendingRemoteVideoFlowAckVersion = null;
    _state.lastInboundVideoBytes = -1;
    _state.lastInboundVideoFramesDecoded = -1;
    if (_state.remoteVideoFlowSeen) {
      _state.remoteVideoFlowSeen = false;
      _onRemoteVideoFlowChanged(false);
    }
    _log('video:remote state disabled version=$version');
  }

  void handleVideoStateAck({required bool enabled, required int version}) {
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

  void markRemoteVideoFlowDetected() {
    cancelRemoteVideoFlowRecovery();
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
    try {
      await _signaling.sendSignal(peerId, 'call_video_mute_state', {
        'callId': callId,
        'signalScope': 'call',
        'muted': !enabled,
        'version': version,
      });
    } catch (error) {
      _log(
        'video:mute-state send skipped enabled=$enabled '
        'version=$version error=$error',
      );
    }
    _state.videoStateAckTimer?.cancel();
    final expectedEpoch = _getSessionEpoch();
    _state.videoStateAckTimer = Timer(const Duration(milliseconds: 1200), () {
      if (_getSessionEpoch() != expectedEpoch) {
        cancelPendingVideoStateAck();
        return;
      }
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
      unawaited(
        sendVideoStateAttempt(
          enabled: enabled,
          peerId: currentPeerId,
          callId: currentCallId,
          version: version,
        ),
      );
    });
  }

  Future<void> applyInitialVideoQualityProfile() async {
    await _applyVideoQualityProfile(
      _qualityProfiles[_initialQualityIndex],
      reason: 'initial',
    );
  }

  Future<void> _applyVideoQualityProfile(
    _VideoQualityProfile profile, {
    required String reason,
  }) async {
    final sender = _state.videoSendSender;
    if (sender == null) {
      _log(
        'diagnostic:warning video-quality skipped reason=sender-missing '
        '${_videoChannelSnapshot()}',
      );
      return;
    }
    try {
      final parameters = sender.parameters;
      final encodings = parameters.encodings ?? <RTCRtpEncoding>[];
      if (encodings.isEmpty) {
        encodings.add(
          RTCRtpEncoding(
            active: true,
            maxBitrate: profile.maxBitrate,
            maxFramerate: profile.maxFramerate,
            scaleResolutionDownBy: profile.scaleResolutionDownBy,
          ),
        );
      } else {
        final encoding = encodings.first;
        encoding.active = true;
        encoding.maxBitrate = profile.maxBitrate;
        encoding.minBitrate = null;
        encoding.maxFramerate = profile.maxFramerate;
        encoding.scaleResolutionDownBy = profile.scaleResolutionDownBy;
      }
      parameters.encodings = encodings;
      await sender.setParameters(parameters);
      _state.localVideoQualityProfile = profile.name;
      _state.videoQualityStablePolls = 0;
      _state.videoQualityPoorPolls = 0;
      _log(
        'video:quality profile=${profile.name} '
        'bitrate=${profile.maxBitrate} fps=${profile.maxFramerate} '
        'scale=${profile.scaleResolutionDownBy} reason=$reason',
      );
    } catch (error) {
      _log('video:quality ${profile.name} failed error=$error');
    }
  }

  void scheduleVideoQualityUpgrade() {
    cancelVideoQualityUpgrade();
    final expectedEpoch = _getSessionEpoch();
    _state.videoQualityUpgradeTimer = Timer(_flowAckUpgradeDelay, () {
      if (_getSessionEpoch() != expectedEpoch) {
        cancelVideoQualityUpgrade();
        return;
      }
      unawaited(applyUpgradedVideoQualityProfile());
    });
    _log(
      'video:quality upgrade scheduled '
      'delayMs=${_flowAckUpgradeDelay.inMilliseconds}',
    );
  }

  void cancelVideoQualityUpgrade() {
    _state.videoQualityUpgradeTimer?.cancel();
    _state.videoQualityUpgradeTimer = null;
  }

  Future<void> applyUpgradedVideoQualityProfile() async {
    _state.videoQualityUpgradeTimer = null;
    if (_getMediaType() != CallMediaType.video ||
        !_getLocalVideoTrackAttached()) {
      _log('video:quality upgrade skipped no-local-video');
      return;
    }
    await _applyVideoQualityProfile(
      _qualityProfiles[_flowAckUpgradeQualityIndex],
      reason: 'flow-ack-upgrade',
    );
  }

  Future<void> handleNetworkStats({
    required AudioTrafficStats stats,
    required double outboundKbps,
  }) async {
    if (_getMediaType() != CallMediaType.video ||
        !_getLocalVideoTrackAttached() ||
        _state.videoSendSender == null) {
      return;
    }
    final currentIndex = _currentQualityIndex();
    final currentProfile = _qualityProfiles[currentIndex];
    final audioLossDelta = _packetLossDelta(
      stats.audioPacketsLost,
      _state.lastVideoQualityAudioPacketsLost,
    );
    final videoLossDelta = _packetLossDelta(
      stats.videoPacketsLost,
      _state.lastVideoQualityVideoPacketsLost,
    );
    _state.lastVideoQualityAudioPacketsLost = stats.audioPacketsLost;
    _state.lastVideoQualityVideoPacketsLost = stats.videoPacketsLost;

    final overshooting =
        outboundKbps > (currentProfile.maxBitrate / 1000) * 1.8;
    final poorNetwork =
        overshooting ||
        stats.currentRoundTripTimeMs >= 450 ||
        stats.videoJitterMs >= 90 ||
        audioLossDelta >= 4 ||
        videoLossDelta >= 3;
    final networkCause = _videoNetworkCause(
      overshooting: overshooting,
      stats: stats,
      audioLossDelta: audioLossDelta,
      videoLossDelta: videoLossDelta,
    );
    if (poorNetwork) {
      _state.videoQualityStablePolls = 0;
      _state.videoQualityPoorPolls += 1;
      _logVideoNetworkDiagnostic(
        stats: stats,
        outboundKbps: outboundKbps,
        profile: currentProfile,
        cause: networkCause,
        audioLossDelta: audioLossDelta,
        videoLossDelta: videoLossDelta,
        warning: true,
      );
      if (_state.videoQualityPoorPolls >= _poorPollsBeforeDowngrade &&
          currentIndex > 0) {
        await _applyVideoQualityProfile(
          _qualityProfiles[currentIndex - 1],
          reason:
              'adaptive-down actualOutKbps=${outboundKbps.toStringAsFixed(0)} '
              'rttMs=${stats.currentRoundTripTimeMs.toStringAsFixed(0)} '
              'audioLossDelta=$audioLossDelta videoLossDelta=$videoLossDelta',
        );
      }
      return;
    }

    _logVideoNetworkDiagnostic(
      stats: stats,
      outboundKbps: outboundKbps,
      profile: currentProfile,
      cause: 'stable',
      audioLossDelta: audioLossDelta,
      videoLossDelta: videoLossDelta,
      warning: false,
    );
    _state.videoQualityPoorPolls = 0;
    if (stats.selectedCandidatePairId == null ||
        stats.availableOutgoingBitrateKbps <= 0) {
      _state.videoQualityStablePolls = 0;
      return;
    }
    final enoughHeadroom =
        stats.availableOutgoingBitrateKbps >
        (currentProfile.maxBitrate / 1000) * 3.0;
    final actualWithinProfile =
        outboundKbps <= (currentProfile.maxBitrate / 1000) * 1.25;
    if (!enoughHeadroom ||
        !actualWithinProfile ||
        stats.currentRoundTripTimeMs > 220 ||
        stats.videoJitterMs > 45) {
      _state.videoQualityStablePolls = 0;
      return;
    }
    _state.videoQualityStablePolls += 1;
    if (_state.videoQualityStablePolls >= _stablePollsBeforeUpgrade &&
        currentIndex < _qualityProfiles.length - 1) {
      await _applyVideoQualityProfile(
        _qualityProfiles[currentIndex + 1],
        reason:
            'adaptive-up actualOutKbps=${outboundKbps.toStringAsFixed(0)} '
            'availableOutKbps=${stats.availableOutgoingBitrateKbps.toStringAsFixed(0)}',
      );
    }
  }

  int _currentQualityIndex() {
    final currentName = _state.localVideoQualityProfile;
    final index = _qualityProfiles.indexWhere(
      (profile) => profile.name == currentName,
    );
    return index < 0 ? _initialQualityIndex : index;
  }

  int _packetLossDelta(int current, int previous) {
    if (previous < 0 || current < previous) {
      return 0;
    }
    return current - previous;
  }

  String _videoNetworkCause({
    required bool overshooting,
    required AudioTrafficStats stats,
    required int audioLossDelta,
    required int videoLossDelta,
  }) {
    if (overshooting) {
      return 'outbound-overshoot';
    }
    if (stats.currentRoundTripTimeMs >= 450) {
      return 'high-rtt';
    }
    if (stats.videoJitterMs >= 90) {
      return 'high-video-jitter';
    }
    if (videoLossDelta >= 3) {
      return 'video-packet-loss';
    }
    if (audioLossDelta >= 4) {
      return 'audio-packet-loss';
    }
    return 'unknown';
  }

  void _logVideoNetworkDiagnostic({
    required AudioTrafficStats stats,
    required double outboundKbps,
    required _VideoQualityProfile profile,
    required String cause,
    required int audioLossDelta,
    required int videoLossDelta,
    required bool warning,
  }) {
    final now = DateTime.now();
    final lastLogAt = _state.lastVideoNetworkDiagnosticAt;
    if (!warning &&
        lastLogAt != null &&
        now.difference(lastLogAt) < _videoNetworkDiagnosticThrottle) {
      return;
    }
    if (warning &&
        lastLogAt != null &&
        now.difference(lastLogAt) < _videoNetworkDiagnosticThrottle &&
        _state.videoQualityPoorPolls > 1) {
      return;
    }
    _state.lastVideoNetworkDiagnosticAt = now;
    final prefix = warning
        ? 'diagnostic:warning video-network'
        : 'video:network';
    _log(
      '$prefix cause=$cause '
      'actualOutKbps=${outboundKbps.toStringAsFixed(0)} '
      'profile=${profile.name} '
      'profileMaxKbps=${(profile.maxBitrate / 1000).toStringAsFixed(0)} '
      'availableOutKbps=${stats.availableOutgoingBitrateKbps.toStringAsFixed(0)} '
      'rttMs=${stats.currentRoundTripTimeMs.toStringAsFixed(0)} '
      'audioLossDelta=$audioLossDelta videoLossDelta=$videoLossDelta '
      'videoJitterMs=${stats.videoJitterMs.toStringAsFixed(0)} '
      '${_videoChannelSnapshot()}',
    );
  }

  String _trackSnapshot(MediaStreamTrack? track) {
    if (track == null) {
      return 'null';
    }
    return '${track.kind}:${track.id}:enabled=${track.enabled}:muted=${track.muted}';
  }

  String _videoChannelSnapshot() {
    return 'sendSenderId=${_state.videoSendSender?.senderId} '
        'sendTrack=${_trackSnapshot(_state.videoSendSender?.track)} '
        'sendMid=${_state.videoSendTransceiver?.mid} '
        'recvMid=${_state.videoReceiveTransceiver?.mid} '
        'recvTrack=${_trackSnapshot(_state.videoReceiveTransceiver?.receiver.track)} '
        'expectedSendMid=${_state.expectedVideoSendMid} '
        'expectedRecvMid=${_state.expectedVideoReceiveMid} '
        'localAttached=${_getLocalVideoTrackAttached()} '
        'profile=${_state.localVideoQualityProfile}';
  }

  void cancelPendingVideoStateAck() {
    _state.videoStateAckTimer?.cancel();
    _state.videoStateAckTimer = null;
    _state.pendingVideoStateVersion = null;
    _state.pendingVideoStateEnabled = null;
    _state.pendingVideoStateAttempts = 0;
  }

  Future<void> syncLocalMediaTracks() async {
    _log(
      'video:sync begin media=${_getMediaType().name} '
      '${_videoChannelSnapshot()}',
    );
    await _mediaStreamController.syncLocalMediaTracks(
      mediaType: _getMediaType(),
      refreshVideoChannelHandles: refreshVideoChannelHandles,
      applyInitialVideoQualityProfile: applyInitialVideoQualityProfile,
      getVideoSendSender: () => _state.videoSendSender,
      getVideoSendTransceiver: () => _state.videoSendTransceiver,
      setVideoSendSender: (sender) => _state.videoSendSender = sender,
    );
    if (_getMediaType() == CallMediaType.audio) {
      cancelVideoQualityUpgrade();
    }
    _log(
      'video:sync done media=${_getMediaType().name} '
      '${_videoChannelSnapshot()}',
    );
  }

  Future<bool> ensureVideoTransceiversReady() async {
    final peer = _getPeer();
    if (peer == null) {
      _log('diagnostic:warning video:bootstrap skipped reason=peer-missing');
      return false;
    }
    await refreshVideoChannelHandles();
    if (_state.videoSendTransceiver != null &&
        _state.videoReceiveTransceiver != null) {
      return false;
    }
    try {
      _state.videoSendTransceiver ??= await peer.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
      );
      _state.videoReceiveTransceiver ??= _state.videoSendTransceiver;
      await refreshVideoChannelHandles();
      _log(
        'video:bootstrap created-on-demand '
        'shared=${identical(_state.videoSendTransceiver, _state.videoReceiveTransceiver)} '
        'sendMid=${_state.videoSendTransceiver?.mid} '
        'recvMid=${_state.videoReceiveTransceiver?.mid}',
      );
      return true;
    } catch (error) {
      _log('video:bootstrap on-demand failed error=$error');
      rethrow;
    }
  }

  Future<void> refreshVideoChannelHandles() async {
    final peer = _getPeer();
    if (peer == null) {
      _state.videoSendTransceiver = null;
      _state.videoReceiveTransceiver = null;
      _state.videoSendSender = null;
      _log('diagnostic:warning video:handles cleared reason=peer-missing');
      return;
    }
    try {
      final transceivers = List<RTCRtpTransceiver>.from(
        await peer.getTransceivers(),
      );
      final currentSendSenderId = _state.videoSendSender?.senderId;
      final expectedSendMid = _state.expectedVideoSendMid;
      final expectedReceiveMid = _state.expectedVideoReceiveMid;
      RTCRtpTransceiver? sendTransceiver;
      RTCRtpTransceiver? receiveTransceiver;
      final orderedVideoTransceivers = <RTCRtpTransceiver>[];
      var sendResolvedByExpectedMid = false;
      var receiveResolvedByExpectedMid = false;

      if (expectedSendMid != null || expectedReceiveMid != null) {
        for (final transceiver in transceivers) {
          if (expectedSendMid != null && transceiver.mid == expectedSendMid) {
            sendTransceiver ??= transceiver;
            sendResolvedByExpectedMid = true;
          }
          if (expectedReceiveMid != null &&
              transceiver.mid == expectedReceiveMid) {
            receiveTransceiver ??= transceiver;
            receiveResolvedByExpectedMid = true;
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
            transceiver.sender.senderId == currentSendSenderId &&
            !sendResolvedByExpectedMid) {
          sendTransceiver = transceiver;
          continue;
        }

        if (_isSendSideDirection(direction) ||
            _isSendSideDirection(currentDirection)) {
          if (!sendResolvedByExpectedMid) {
            sendTransceiver ??= transceiver;
          }
          continue;
        }
        if (_isReceiveSideDirection(direction) ||
            _isReceiveSideDirection(currentDirection)) {
          if (!receiveResolvedByExpectedMid) {
            receiveTransceiver ??= transceiver;
          }
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

      if (identical(sendTransceiver, receiveTransceiver)) {
        receiveTransceiver = orderedVideoTransceivers.firstWhere(
          (candidate) => !identical(candidate, sendTransceiver),
          orElse: () => receiveTransceiver!,
        );
      }

      _state.videoSendTransceiver = sendTransceiver;
      _state.videoReceiveTransceiver = receiveTransceiver;
      _state.videoSendSender = sendTransceiver?.sender;
      _log(
        'video:handles refreshed '
        'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
        'videoCount=${orderedVideoTransceivers.length} '
        '${_videoChannelSnapshot()}',
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
    if (mids.length == 1) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[0];
      _log('video:mids local-offer sharedMid=${_state.expectedVideoSendMid}');
      return;
    }
    if (mids.length >= 2) {
      final localMids = _localMidsFromOffer(sdp, fallbackMids: mids);
      _state.expectedVideoSendMid = localMids.$1;
      _state.expectedVideoReceiveMid = localMids.$2;
      _log(
        'video:mids local-offer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  void captureExpectedVideoMidsForRemoteOffer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length == 1) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[0];
      _log('video:mids remote-offer sharedMid=${_state.expectedVideoSendMid}');
      return;
    }
    if (mids.length >= 2) {
      final localMids = _localMidsFromRemoteOffer(sdp, fallbackMids: mids);
      _state.expectedVideoSendMid = localMids.$1;
      _state.expectedVideoReceiveMid = localMids.$2;
      _log(
        'video:mids remote-offer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  void captureExpectedVideoMidsForRemoteAnswer(String? sdp) {
    final mids = _extractVideoMids(sdp);
    if (mids.length == 1) {
      _state.expectedVideoSendMid = mids[0];
      _state.expectedVideoReceiveMid = mids[0];
      _log('video:mids remote-answer sharedMid=${_state.expectedVideoSendMid}');
      return;
    }
    if (mids.length >= 2) {
      final currentSendMid = _state.videoSendTransceiver?.mid;
      final currentReceiveMid = _state.videoReceiveTransceiver?.mid;
      final expectedSendMid = _state.expectedVideoSendMid;
      final expectedReceiveMid = _state.expectedVideoReceiveMid;

      if (currentSendMid != null &&
          currentReceiveMid != null &&
          mids.contains(currentSendMid) &&
          mids.contains(currentReceiveMid)) {
        _state.expectedVideoSendMid = currentSendMid;
        _state.expectedVideoReceiveMid = currentReceiveMid;
      } else if (expectedSendMid != null &&
          expectedReceiveMid != null &&
          mids.contains(expectedSendMid) &&
          mids.contains(expectedReceiveMid)) {
        _state.expectedVideoSendMid = expectedSendMid;
        _state.expectedVideoReceiveMid = expectedReceiveMid;
      } else {
        _state.expectedVideoSendMid = mids[0];
        _state.expectedVideoReceiveMid = mids[1];
      }
      _log(
        'video:mids remote-answer sendMid=${_state.expectedVideoSendMid} '
        'recvMid=${_state.expectedVideoReceiveMid}',
      );
    }
  }

  (String sendMid, String receiveMid) _localMidsFromOffer(
    String? sdp, {
    required List<String> fallbackMids,
  }) {
    final sections = _extractVideoSdpSections(sdp);
    final sendMid = _firstMidWithDirection(sections, const <String>{
      'sendonly',
      'sendrecv',
    });
    final receiveMid = _firstMidWithDirection(sections, const <String>{
      'recvonly',
      'sendrecv',
    }, exceptMid: sendMid);
    return (sendMid ?? fallbackMids[0], receiveMid ?? fallbackMids[1]);
  }

  (String sendMid, String receiveMid) _localMidsFromRemoteOffer(
    String? sdp, {
    required List<String> fallbackMids,
  }) {
    final sections = _extractVideoSdpSections(sdp);
    final sendMid = _firstMidWithDirection(sections, const <String>{
      'recvonly',
      'sendrecv',
    });
    final receiveMid = _firstMidWithDirection(sections, const <String>{
      'sendonly',
      'sendrecv',
    }, exceptMid: sendMid);
    return (sendMid ?? fallbackMids[1], receiveMid ?? fallbackMids[0]);
  }

  String? _firstMidWithDirection(
    List<_VideoSdpSection> sections,
    Set<String> directions, {
    String? exceptMid,
  }) {
    for (final section in sections) {
      if (section.mid == exceptMid) {
        continue;
      }
      if (directions.contains(section.direction)) {
        return section.mid;
      }
    }
    return null;
  }

  List<_VideoSdpSection> _extractVideoSdpSections(String? sdp) {
    if (sdp == null || sdp.isEmpty) {
      return const <_VideoSdpSection>[];
    }
    final sections = <_VideoSdpSection>[];
    final lines = sdp.split('\r\n');
    var inVideoSection = false;
    String? currentMid;
    var currentDirection = 'sendrecv';

    void flushSection() {
      final mid = currentMid;
      if (!inVideoSection || mid == null || mid.isEmpty) {
        return;
      }
      sections.add(_VideoSdpSection(mid: mid, direction: currentDirection));
    }

    for (final line in lines) {
      if (line.startsWith('m=')) {
        flushSection();
        inVideoSection = line.startsWith('m=video ');
        currentMid = null;
        currentDirection = 'sendrecv';
        continue;
      }
      if (!inVideoSection) {
        continue;
      }
      if (line.startsWith('a=mid:')) {
        currentMid = line.substring('a=mid:'.length);
        continue;
      }
      if (line == 'a=sendrecv' ||
          line == 'a=sendonly' ||
          line == 'a=recvonly' ||
          line == 'a=inactive') {
        currentDirection = line.substring('a='.length);
      }
    }
    flushSection();
    return sections;
  }

  Future<void> ensureVideoTransceiverDirectionsForRole() async {
    final sendTransceiver = _state.videoSendTransceiver;
    final receiveTransceiver = _state.videoReceiveTransceiver;
    if (sendTransceiver == null && receiveTransceiver == null) {
      return;
    }
    try {
      if (sendTransceiver != null &&
          receiveTransceiver != null &&
          identical(sendTransceiver, receiveTransceiver)) {
        await sendTransceiver.setDirection(TransceiverDirection.SendRecv);
        _log(
          'video:directions enforced shared=true '
          'role=${_getStartedAsOfferer() ? 'offerer' : 'answerer'} '
          'mid=${sendTransceiver.mid}',
        );
        return;
      }
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
