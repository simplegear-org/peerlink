import 'call_media_stats_utils.dart';

String classifyCallRecoveryIssue({
  required String trigger,
  required bool iceConnected,
  required bool remoteTrackSeen,
  required bool remoteAudioTrackSeen,
  required bool remoteAudioFlowSeen,
  required bool remoteVideoEnabled,
  required bool remoteVideoTrackSeen,
  required bool remoteVideoFlowSeen,
  AudioTrafficStats? stats,
}) {
  final pairMissing = stats?.selectedCandidatePairId == null;
  if ((trigger == 'recovery-answer-sent' ||
          trigger == 'recovery-answer-applied' ||
          trigger == 'post-ice-recovery-timeout') &&
      pairMissing) {
    return 'signaling-recovered-transport-not-recovered';
  }
  if (iceConnected && pairMissing) {
    return 'candidate-pair-disappeared-after-recovery';
  }
  if (iceConnected && remoteAudioTrackSeen && !remoteAudioFlowSeen) {
    return 'transport-recovered-audio-flow-dead';
  }
  if (iceConnected &&
      remoteVideoEnabled &&
      remoteVideoTrackSeen &&
      !remoteVideoFlowSeen) {
    return 'transport-recovered-video-flow-dead';
  }
  if (remoteTrackSeen) {
    return 'track-present-bytes-frozen';
  }
  return 'transport-degraded';
}
