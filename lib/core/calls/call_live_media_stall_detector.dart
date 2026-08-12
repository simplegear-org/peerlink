import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_media_diagnostics_formatter.dart';
import 'call_media_stats_utils.dart';

class CallLiveMediaStallDetector {
  static const Duration _stallWarningThrottle = Duration(seconds: 5);
  static const int _liveMediaStallThresholdPolls = 12;
  static const int _stallSuspectThresholdPolls = 3;
  static const int _localAudioOutboundStallThresholdPolls = 5;
  static const Duration _liveMediaStallCooldown = Duration(seconds: 12);
  static const Duration _localAudioOutboundStallCooldown = Duration(
    seconds: 12,
  );

  CallLiveMediaStallDetector({
    required void Function(String message) log,
    required bool Function() getMediaFlowNotified,
    required bool Function() getIceConnected,
    required bool Function() getIceRecoveryInProgress,
    required RTCPeerConnection? Function() getPeer,
    required bool Function() getRemoteAudioTrackSeen,
    required bool Function() getRemoteAudioMuted,
    required bool Function() getLocalAudioMuted,
    required bool Function() getRemoteVideoEnabled,
    required bool Function() getRemoteVideoTrackSeen,
    required bool Function() getRemoteVideoFlowSeen,
    required Future<void> Function(String reason) onLiveMediaFlowStalled,
    Future<void> Function(String reason)? onLocalAudioOutboundStalled,
  }) : _log = log,
       _getMediaFlowNotified = getMediaFlowNotified,
       _getIceConnected = getIceConnected,
       _getIceRecoveryInProgress = getIceRecoveryInProgress,
       _getPeer = getPeer,
       _getRemoteAudioTrackSeen = getRemoteAudioTrackSeen,
       _getRemoteAudioMuted = getRemoteAudioMuted,
       _getLocalAudioMuted = getLocalAudioMuted,
       _getRemoteVideoEnabled = getRemoteVideoEnabled,
       _getRemoteVideoTrackSeen = getRemoteVideoTrackSeen,
       _getRemoteVideoFlowSeen = getRemoteVideoFlowSeen,
       _onLiveMediaFlowStalled = onLiveMediaFlowStalled,
       _onLocalAudioOutboundStalled = onLocalAudioOutboundStalled;

  final void Function(String message) _log;
  final bool Function() _getMediaFlowNotified;
  final bool Function() _getIceConnected;
  final bool Function() _getIceRecoveryInProgress;
  final RTCPeerConnection? Function() _getPeer;
  final bool Function() _getRemoteAudioTrackSeen;
  final bool Function() _getRemoteAudioMuted;
  final bool Function() _getLocalAudioMuted;
  final bool Function() _getRemoteVideoEnabled;
  final bool Function() _getRemoteVideoTrackSeen;
  final bool Function() _getRemoteVideoFlowSeen;
  final Future<void> Function(String reason) _onLiveMediaFlowStalled;
  final Future<void> Function(String reason)? _onLocalAudioOutboundStalled;

  int _lastLiveInboundBytes = -1;
  int _lastLiveInboundPackets = -1;
  int _lastLiveOutboundBytes = -1;
  int _lastLiveInboundVideoBytes = -1;
  int _lastLiveInboundVideoFramesDecoded = -1;
  int _consecutiveInboundStallPolls = 0;
  int _consecutiveOutboundStallPolls = 0;
  int _consecutiveVideoInboundStallPolls = 0;
  DateTime? _lastLiveMediaStallAt;
  DateTime? _lastLocalAudioOutboundStallAt;
  DateTime? _lastInboundStallWarningAt;
  DateTime? _lastVideoInboundStallWarningAt;
  DateTime? _lastExpectedAudioSilenceLogAt;
  DateTime? _lastExpectedVideoSilenceLogAt;

  void reset() {
    resetBaseline();
    _consecutiveInboundStallPolls = 0;
    _consecutiveOutboundStallPolls = 0;
    _consecutiveVideoInboundStallPolls = 0;
    _lastLiveMediaStallAt = null;
    _lastLocalAudioOutboundStallAt = null;
    _lastInboundStallWarningAt = null;
    _lastVideoInboundStallWarningAt = null;
    _lastExpectedAudioSilenceLogAt = null;
    _lastExpectedVideoSilenceLogAt = null;
  }

  void resetBaseline() {
    _lastLiveInboundBytes = -1;
    _lastLiveInboundPackets = -1;
    _lastLiveOutboundBytes = -1;
    _lastLiveInboundVideoBytes = -1;
    _lastLiveInboundVideoFramesDecoded = -1;
  }

  void resetVideoStallPolls() {
    _consecutiveVideoInboundStallPolls = 0;
  }

  void evaluate(AudioTrafficStats stats) {
    if (!_getMediaFlowNotified() ||
        !_getIceConnected() ||
        _getIceRecoveryInProgress() ||
        _getPeer() == null ||
        !_getRemoteAudioTrackSeen()) {
      _consecutiveInboundStallPolls = 0;
      _consecutiveOutboundStallPolls = 0;
      _consecutiveVideoInboundStallPolls = 0;
      resetBaseline();
      return;
    }
    final previousLiveInboundBytes = _lastLiveInboundBytes;
    final previousLiveInboundPackets = _lastLiveInboundPackets;
    final previousLiveOutboundBytes = _lastLiveOutboundBytes;
    final previousLiveInboundVideoBytes = _lastLiveInboundVideoBytes;
    final previousLiveInboundVideoFrames = _lastLiveInboundVideoFramesDecoded;
    final remoteAudioMuted = _getRemoteAudioMuted();
    final bytesAdvanced = previousLiveInboundBytes >= 0
        ? stats.receivedBytes > previousLiveInboundBytes
        : true;
    final packetsAdvanced = previousLiveInboundPackets >= 0
        ? stats.packetsReceived > previousLiveInboundPackets
        : true;
    final outboundAdvanced = previousLiveOutboundBytes >= 0
        ? stats.audioSentBytes > previousLiveOutboundBytes
        : true;
    final remoteVideoEnabled = _getRemoteVideoEnabled();
    final videoExpected =
        remoteVideoEnabled &&
        (_getRemoteVideoTrackSeen() || _getRemoteVideoFlowSeen());
    final videoAdvanced =
        !videoExpected ||
        previousLiveInboundVideoBytes < 0 ||
        previousLiveInboundVideoFrames < 0 ||
        stats.videoBytesReceived > previousLiveInboundVideoBytes ||
        stats.videoFramesDecoded > previousLiveInboundVideoFrames;
    _updateBaseline(stats);
    if (remoteAudioMuted && !bytesAdvanced && !packetsAdvanced) {
      _logExpectedAudioSilence(source: 'remote-muted', stats: stats);
    }
    if (!remoteVideoEnabled &&
        (previousLiveInboundVideoBytes > 0 ||
            previousLiveInboundVideoFrames > 0) &&
        stats.videoBytesReceived <= previousLiveInboundVideoBytes &&
        stats.videoFramesDecoded <= previousLiveInboundVideoFrames) {
      _logExpectedVideoSilence(source: 'remote-disabled', stats: stats);
    }
    final audioOrTransportAdvanced =
        remoteAudioMuted || bytesAdvanced || packetsAdvanced;
    _evaluateLocalAudioOutboundStall(
      stats: stats,
      inboundAdvanced: audioOrTransportAdvanced,
      outboundAdvanced: outboundAdvanced,
      previousLiveOutboundBytes: previousLiveOutboundBytes,
    );
    _evaluateVideoInboundStall(
      stats: stats,
      audioOrTransportAdvanced: audioOrTransportAdvanced,
      videoExpected: videoExpected,
      videoAdvanced: videoAdvanced,
      previousLiveInboundVideoBytes: previousLiveInboundVideoBytes,
      previousLiveInboundVideoFrames: previousLiveInboundVideoFrames,
    );
    if (audioOrTransportAdvanced || (videoExpected && videoAdvanced)) {
      _consecutiveInboundStallPolls = 0;
      return;
    }
    _consecutiveInboundStallPolls += 1;
    if (_consecutiveInboundStallPolls < _liveMediaStallThresholdPolls) {
      if (_consecutiveInboundStallPolls >= _stallSuspectThresholdPolls) {
        _logInboundStallWarning(
          stats: stats,
          previousLiveInboundBytes: previousLiveInboundBytes,
          previousLiveInboundPackets: previousLiveInboundPackets,
          previousLiveOutboundBytes: previousLiveOutboundBytes,
          outboundAdvanced: outboundAdvanced,
        );
      }
      return;
    }
    final now = DateTime.now();
    final lastStallAt = _lastLiveMediaStallAt;
    if (lastStallAt != null &&
        now.difference(lastStallAt) < _liveMediaStallCooldown) {
      return;
    }
    _lastLiveMediaStallAt = now;
    _consecutiveInboundStallPolls = 0;
    if (outboundAdvanced) {
      _log(
        'diagnostic:warning freeze cause=inbound-only-stall '
        'action=no-ice-restart inboundStallPolls=$_liveMediaStallThresholdPolls '
        '${CallMediaDiagnosticsFormatter.format(stats)} '
        'audioDelta=${CallMediaDiagnosticsFormatter.delta(stats.receivedBytes, previousLiveInboundBytes)} '
        'packetDelta=${CallMediaDiagnosticsFormatter.delta(stats.packetsReceived, previousLiveInboundPackets)} '
        'audioOutDelta=${CallMediaDiagnosticsFormatter.delta(stats.audioSentBytes, previousLiveOutboundBytes)}',
      );
      return;
    }
    _log(
      'diagnostic:warning freeze cause=full-media-stall action=diagnostic-only '
      'stallPolls=$_liveMediaStallThresholdPolls '
      '${CallMediaDiagnosticsFormatter.format(stats)} '
      'audioDelta=${CallMediaDiagnosticsFormatter.delta(stats.receivedBytes, previousLiveInboundBytes)} '
      'packetDelta=${CallMediaDiagnosticsFormatter.delta(stats.packetsReceived, previousLiveInboundPackets)} '
      'audioOutDelta=${CallMediaDiagnosticsFormatter.delta(stats.audioSentBytes, previousLiveOutboundBytes)} '
      'videoDelta=${CallMediaDiagnosticsFormatter.delta(stats.videoBytesReceived, previousLiveInboundVideoBytes)} '
      'frameDelta=${CallMediaDiagnosticsFormatter.delta(stats.videoFramesDecoded, previousLiveInboundVideoFrames)}',
    );
    unawaited(
      _onLiveMediaFlowStalled(
        'Live media stalled while ICE remained connected',
      ),
    );
  }

  void _evaluateLocalAudioOutboundStall({
    required AudioTrafficStats stats,
    required bool inboundAdvanced,
    required bool outboundAdvanced,
    required int previousLiveOutboundBytes,
  }) {
    final handler = _onLocalAudioOutboundStalled;
    if (handler == null) {
      return;
    }
    if (_getLocalAudioMuted()) {
      if (!outboundAdvanced &&
          inboundAdvanced &&
          previousLiveOutboundBytes >= 0) {
        _logExpectedAudioSilence(source: 'local-muted', stats: stats);
      }
      _consecutiveOutboundStallPolls = 0;
      return;
    }
    if (outboundAdvanced || !inboundAdvanced || previousLiveOutboundBytes < 0) {
      _consecutiveOutboundStallPolls = 0;
      return;
    }
    _consecutiveOutboundStallPolls += 1;
    if (_consecutiveOutboundStallPolls <
        _localAudioOutboundStallThresholdPolls) {
      return;
    }
    final now = DateTime.now();
    final lastStallAt = _lastLocalAudioOutboundStallAt;
    if (lastStallAt != null &&
        now.difference(lastStallAt) < _localAudioOutboundStallCooldown) {
      return;
    }
    _lastLocalAudioOutboundStallAt = now;
    _consecutiveOutboundStallPolls = 0;
    _log(
      'diagnostic:warning freeze cause=local-audio-outbound-stall '
      'action=refresh-audio-sender outboundStallPolls=$_localAudioOutboundStallThresholdPolls '
      '${CallMediaDiagnosticsFormatter.format(stats)} '
      'audioOutDelta=${CallMediaDiagnosticsFormatter.delta(stats.audioSentBytes, previousLiveOutboundBytes)}',
    );
    unawaited(
      handler('Local audio outbound stalled while inbound media continued'),
    );
  }

  void _logExpectedAudioSilence({
    required String source,
    required AudioTrafficStats stats,
  }) {
    final now = DateTime.now();
    final lastLogAt = _lastExpectedAudioSilenceLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < _stallWarningThrottle) {
      return;
    }
    _lastExpectedAudioSilenceLogAt = now;
    _log(
      'diagnostic:audio expected-silence source=$source '
      '${CallMediaDiagnosticsFormatter.format(stats)}',
    );
  }

  void _logExpectedVideoSilence({
    required String source,
    required AudioTrafficStats stats,
  }) {
    final now = DateTime.now();
    final lastLogAt = _lastExpectedVideoSilenceLogAt;
    if (lastLogAt != null &&
        now.difference(lastLogAt) < _stallWarningThrottle) {
      return;
    }
    _lastExpectedVideoSilenceLogAt = now;
    _log(
      'diagnostic:video expected-silence source=$source '
      '${CallMediaDiagnosticsFormatter.format(stats)}',
    );
  }

  void _evaluateVideoInboundStall({
    required AudioTrafficStats stats,
    required bool audioOrTransportAdvanced,
    required bool videoExpected,
    required bool videoAdvanced,
    required int previousLiveInboundVideoBytes,
    required int previousLiveInboundVideoFrames,
  }) {
    if (!videoExpected || videoAdvanced) {
      _consecutiveVideoInboundStallPolls = 0;
      return;
    }
    _consecutiveVideoInboundStallPolls += 1;
    if (!audioOrTransportAdvanced ||
        _consecutiveVideoInboundStallPolls < _stallSuspectThresholdPolls) {
      return;
    }
    final now = DateTime.now();
    final lastWarningAt = _lastVideoInboundStallWarningAt;
    if (lastWarningAt != null &&
        now.difference(lastWarningAt) < _stallWarningThrottle) {
      return;
    }
    _lastVideoInboundStallWarningAt = now;
    _log(
      'diagnostic:warning freeze-suspect cause=video-inbound-stall '
      'action=keep-audio-live videoStallPolls=$_consecutiveVideoInboundStallPolls '
      '${CallMediaDiagnosticsFormatter.format(stats)} '
      'videoDelta=${CallMediaDiagnosticsFormatter.delta(stats.videoBytesReceived, previousLiveInboundVideoBytes)} '
      'frameDelta=${CallMediaDiagnosticsFormatter.delta(stats.videoFramesDecoded, previousLiveInboundVideoFrames)}',
    );
  }

  void _logInboundStallWarning({
    required AudioTrafficStats stats,
    required int previousLiveInboundBytes,
    required int previousLiveInboundPackets,
    required int previousLiveOutboundBytes,
    required bool outboundAdvanced,
  }) {
    final now = DateTime.now();
    final lastWarningAt = _lastInboundStallWarningAt;
    if (lastWarningAt != null &&
        now.difference(lastWarningAt) < _stallWarningThrottle) {
      return;
    }
    _lastInboundStallWarningAt = now;
    _log(
      'diagnostic:warning freeze-suspect cause=inbound-audio-stall '
      'outboundAdvanced=$outboundAdvanced '
      'inboundStallPolls=$_consecutiveInboundStallPolls '
      '${CallMediaDiagnosticsFormatter.format(stats)} '
      'audioDelta=${CallMediaDiagnosticsFormatter.delta(stats.receivedBytes, previousLiveInboundBytes)} '
      'packetDelta=${CallMediaDiagnosticsFormatter.delta(stats.packetsReceived, previousLiveInboundPackets)} '
      'audioOutDelta=${CallMediaDiagnosticsFormatter.delta(stats.audioSentBytes, previousLiveOutboundBytes)}',
    );
  }

  void _updateBaseline(AudioTrafficStats stats) {
    _lastLiveInboundBytes = stats.receivedBytes;
    _lastLiveInboundPackets = stats.packetsReceived;
    _lastLiveOutboundBytes = stats.audioSentBytes;
    _lastLiveInboundVideoBytes = stats.videoBytesReceived;
    _lastLiveInboundVideoFramesDecoded = stats.videoFramesDecoded;
  }
}
