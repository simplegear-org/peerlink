import 'dart:async';

import 'call_media_stats_utils.dart' as stats_utils;

class CallMediaFlowStatsTracker {
  int _lastInboundBytes = -1;
  int _lastInboundPackets = -1;
  double _lastInboundAudioEnergy = -1;
  double _lastInboundSamplesDuration = -1;
  int _lastInboundVideoBytes = -1;
  int _lastInboundVideoFramesDecoded = -1;
  int _reportedSentBytes = 0;
  int _reportedReceivedBytes = 0;
  int _lastVideoNetworkSentBytes = -1;
  DateTime? _lastVideoNetworkStatsAt;

  int get lastInboundVideoBytes => _lastInboundVideoBytes;
  int get lastInboundVideoFramesDecoded => _lastInboundVideoFramesDecoded;

  void reset() {
    _lastInboundBytes = -1;
    _lastInboundPackets = -1;
    _lastInboundAudioEnergy = -1;
    _lastInboundSamplesDuration = -1;
    _lastInboundVideoBytes = -1;
    _lastInboundVideoFramesDecoded = -1;
    _reportedSentBytes = 0;
    _reportedReceivedBytes = 0;
    _lastVideoNetworkSentBytes = -1;
    _lastVideoNetworkStatsAt = null;
  }

  void resetFlowBaselines() {
    _lastInboundBytes = -1;
    _lastInboundPackets = -1;
    _lastInboundAudioEnergy = -1;
    _lastInboundSamplesDuration = -1;
    _lastInboundVideoBytes = -1;
    _lastInboundVideoFramesDecoded = -1;
  }

  bool detectInboundAudioFlow(stats_utils.AudioTrafficStats stats) {
    final detected = stats_utils.detectInboundAudioFlow(
      stats: stats,
      lastInboundBytes: _lastInboundBytes,
      lastInboundPackets: _lastInboundPackets,
      lastInboundAudioEnergy: _lastInboundAudioEnergy,
      lastInboundSamplesDuration: _lastInboundSamplesDuration,
    );
    _lastInboundBytes = stats.receivedBytes;
    _lastInboundPackets = stats.packetsReceived;
    _lastInboundAudioEnergy = stats.totalAudioEnergy;
    _lastInboundSamplesDuration = stats.totalSamplesDuration;
    return detected;
  }

  bool detectInboundVideoFlow(stats_utils.AudioTrafficStats stats) {
    final detected = stats_utils.detectInboundVideoFlow(
      stats: stats,
      lastInboundVideoBytes: _lastInboundVideoBytes,
      lastInboundVideoFramesDecoded: _lastInboundVideoFramesDecoded,
    );
    _lastInboundVideoBytes = stats.videoBytesReceived;
    _lastInboundVideoFramesDecoded = stats.videoFramesDecoded;
    return detected;
  }

  ({int sentBytes, int receivedBytes})? reportableStatsDelta(
    stats_utils.AudioTrafficStats stats,
  ) {
    if (stats.sentBytes == _reportedSentBytes &&
        stats.receivedBytes == _reportedReceivedBytes) {
      return null;
    }
    _reportedSentBytes = stats.sentBytes;
    _reportedReceivedBytes = stats.receivedBytes;
    return (sentBytes: stats.sentBytes, receivedBytes: stats.receivedBytes);
  }

  void reportVideoNetworkStats({
    required stats_utils.AudioTrafficStats stats,
    required Duration fallbackInterval,
    required Future<void> Function({
      required stats_utils.AudioTrafficStats stats,
      required double outboundKbps,
    })?
    handler,
  }) {
    if (handler == null) {
      return;
    }
    final now = DateTime.now();
    final previousSentBytes = _lastVideoNetworkSentBytes;
    final previousAt = _lastVideoNetworkStatsAt;
    _lastVideoNetworkSentBytes = stats.sentBytes;
    _lastVideoNetworkStatsAt = now;
    if (previousSentBytes < 0 || previousAt == null) {
      return;
    }
    final sentDeltaBytes = stats.sentBytes - previousSentBytes;
    if (sentDeltaBytes <= 0) {
      unawaited(handler(stats: stats, outboundKbps: 0));
      return;
    }
    final elapsedMs = now.difference(previousAt).inMilliseconds;
    final safeElapsedMs = elapsedMs <= 0
        ? fallbackInterval.inMilliseconds
        : elapsedMs;
    final outboundKbps = sentDeltaBytes * 8 / safeElapsedMs;
    unawaited(handler(stats: stats, outboundKbps: outboundKbps));
  }
}
