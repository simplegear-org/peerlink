part of 'audio_call_peer.dart';

_AudioTrafficStats _extractAudioTrafficStatsImpl(List<StatsReport> reports) {
  var sentBytes = 0;
  var receivedBytes = 0;
  var packetsReceived = 0;
  var audioLevel = 0.0;
  var totalAudioEnergy = 0.0;
  var totalSamplesDuration = 0.0;
  var videoBytesReceived = 0;
  var videoFramesDecoded = 0;

  for (final report in reports) {
    final values = report.values;
    final kind = (values['kind'] ?? values['mediaType'] ?? '').toString();
    if (report.type == 'outbound-rtp') {
      sentBytes += _toIntImpl(values['bytesSent']);
      continue;
    }
    if (report.type != 'inbound-rtp') {
      continue;
    }
    receivedBytes += _toIntImpl(values['bytesReceived']);
    if (kind == 'video') {
      videoBytesReceived += _toIntImpl(values['bytesReceived']);
      videoFramesDecoded += _toIntImpl(values['framesDecoded']);
      continue;
    }
    if (kind.isNotEmpty && kind != 'audio') {
      continue;
    }
    packetsReceived += _toIntImpl(values['packetsReceived']);
    audioLevel = _maxDoubleImpl(audioLevel, _toDoubleImpl(values['audioLevel']));
    totalAudioEnergy += _toDoubleImpl(values['totalAudioEnergy']);
    totalSamplesDuration += _toDoubleImpl(values['totalSamplesDuration']);
  }
  return _AudioTrafficStats(
    sentBytes: sentBytes,
    receivedBytes: receivedBytes,
    packetsReceived: packetsReceived,
    audioLevel: audioLevel,
    totalAudioEnergy: totalAudioEnergy,
    totalSamplesDuration: totalSamplesDuration,
    videoBytesReceived: videoBytesReceived,
    videoFramesDecoded: videoFramesDecoded,
  );
}

bool _detectInboundAudioFlowImpl(AudioCallPeer peer, _AudioTrafficStats stats) {
  if (stats.receivedBytes <= 0 && stats.packetsReceived <= 0) {
    return false;
  }
  if (peer._lastInboundBytes >= 0 || peer._lastInboundPackets >= 0) {
    final bytesAdvanced = stats.receivedBytes > peer._lastInboundBytes ||
        stats.packetsReceived > peer._lastInboundPackets;
    final audioEnergyAdvanced =
        peer._lastInboundAudioEnergy >= 0 &&
        stats.totalAudioEnergy > peer._lastInboundAudioEnergy &&
        stats.totalSamplesDuration > peer._lastInboundSamplesDuration;
    final audioLevelPresent = stats.audioLevel > 0.0001;
    peer._lastInboundBytes = stats.receivedBytes;
    peer._lastInboundPackets = stats.packetsReceived;
    peer._lastInboundAudioEnergy = stats.totalAudioEnergy;
    peer._lastInboundSamplesDuration = stats.totalSamplesDuration;
    return bytesAdvanced && (audioEnergyAdvanced || audioLevelPresent);
  }
  peer._lastInboundBytes = stats.receivedBytes;
  peer._lastInboundPackets = stats.packetsReceived;
  peer._lastInboundAudioEnergy = stats.totalAudioEnergy;
  peer._lastInboundSamplesDuration = stats.totalSamplesDuration;
  return false;
}

bool _detectInboundVideoFlowImpl(AudioCallPeer peer, _AudioTrafficStats stats) {
  if (stats.videoBytesReceived <= 0 && stats.videoFramesDecoded <= 0) {
    return false;
  }
  if (peer._lastInboundVideoBytes >= 0 || peer._lastInboundVideoFramesDecoded >= 0) {
    final bytesAdvanced = stats.videoBytesReceived > peer._lastInboundVideoBytes;
    final framesAdvanced = stats.videoFramesDecoded > peer._lastInboundVideoFramesDecoded;
    peer._lastInboundVideoBytes = stats.videoBytesReceived;
    peer._lastInboundVideoFramesDecoded = stats.videoFramesDecoded;
    return bytesAdvanced || framesAdvanced;
  }
  peer._lastInboundVideoBytes = stats.videoBytesReceived;
  peer._lastInboundVideoFramesDecoded = stats.videoFramesDecoded;
  return false;
}

int _toIntImpl(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _toDoubleImpl(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double _maxDoubleImpl(double left, double right) {
  return left >= right ? left : right;
}
