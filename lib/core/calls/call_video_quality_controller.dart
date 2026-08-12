import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_epoch_timer.dart';
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

class CallVideoQualityController {
  const CallVideoQualityController({
    required CallVideoState state,
    required void Function(String message) log,
    required int Function() getSessionEpoch,
    required CallMediaType Function() getMediaType,
    required bool Function() getLocalVideoTrackAttached,
    required String Function() videoChannelSnapshot,
  }) : _state = state,
       _log = log,
       _getSessionEpoch = getSessionEpoch,
       _getMediaType = getMediaType,
       _getLocalVideoTrackAttached = getLocalVideoTrackAttached,
       _videoChannelSnapshot = videoChannelSnapshot;

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

  final CallVideoState _state;
  final void Function(String message) _log;
  final int Function() _getSessionEpoch;
  final CallMediaType Function() _getMediaType;
  final bool Function() _getLocalVideoTrackAttached;
  final String Function() _videoChannelSnapshot;

  Future<void> applyInitialVideoQualityProfile() async {
    await _applyVideoQualityProfile(
      _qualityProfiles[_initialQualityIndex],
      reason: 'initial',
    );
  }

  void scheduleVideoQualityUpgrade() {
    cancelVideoQualityUpgrade();
    final expectedEpoch = _getSessionEpoch();
    _state.videoQualityUpgradeTimer = CallEpochTimer.arm(
      duration: _flowAckUpgradeDelay,
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: _getSessionEpoch,
      onStale: cancelVideoQualityUpgrade,
      onCurrent: applyUpgradedVideoQualityProfile,
    );
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
}
