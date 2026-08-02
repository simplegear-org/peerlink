import 'package:flutter_webrtc/flutter_webrtc.dart';

class AudioTrafficStats {
  final int sentBytes;
  final int audioSentBytes;
  final int receivedBytes;
  final int packetsReceived;
  final double audioLevel;
  final double totalAudioEnergy;
  final double totalSamplesDuration;
  final int videoBytesReceived;
  final int videoFramesDecoded;
  final String? selectedCandidatePairId;
  final String? localCandidateType;
  final String? remoteCandidateType;
  final String? candidateProtocol;
  final String? localCandidateAddress;
  final String? remoteCandidateAddress;
  final double currentRoundTripTimeMs;
  final double availableOutgoingBitrateKbps;
  final double availableIncomingBitrateKbps;
  final double audioJitterMs;
  final double videoJitterMs;
  final int audioPacketsLost;
  final int videoPacketsLost;

  const AudioTrafficStats({
    required this.sentBytes,
    required this.audioSentBytes,
    required this.receivedBytes,
    required this.packetsReceived,
    required this.audioLevel,
    required this.totalAudioEnergy,
    required this.totalSamplesDuration,
    required this.videoBytesReceived,
    required this.videoFramesDecoded,
    required this.selectedCandidatePairId,
    required this.localCandidateType,
    required this.remoteCandidateType,
    required this.candidateProtocol,
    required this.localCandidateAddress,
    required this.remoteCandidateAddress,
    required this.currentRoundTripTimeMs,
    required this.availableOutgoingBitrateKbps,
    required this.availableIncomingBitrateKbps,
    required this.audioJitterMs,
    required this.videoJitterMs,
    required this.audioPacketsLost,
    required this.videoPacketsLost,
  });
}

String buildMediaDiagnosticsMessage(AudioTrafficStats stats) {
  return 'pair=${stats.selectedCandidatePairId ?? "none"} '
      'route=${stats.candidateProtocol ?? "na"} '
      '${stats.localCandidateType ?? "na"}:${stats.localCandidateAddress ?? "na"} '
      '-> ${stats.remoteCandidateType ?? "na"}:${stats.remoteCandidateAddress ?? "na"} '
      'rttMs=${stats.currentRoundTripTimeMs.toStringAsFixed(0)} '
      'outKbps=${stats.availableOutgoingBitrateKbps.toStringAsFixed(0)} '
      'inKbps=${stats.availableIncomingBitrateKbps.toStringAsFixed(0)} '
      'audioLoss=${stats.audioPacketsLost} '
      'videoLoss=${stats.videoPacketsLost} '
      'audioJitterMs=${stats.audioJitterMs.toStringAsFixed(0)} '
      'videoJitterMs=${stats.videoJitterMs.toStringAsFixed(0)} '
      'bytesIn=${stats.receivedBytes} bytesOut=${stats.sentBytes} '
      'audioBytesOut=${stats.audioSentBytes} '
      'videoBytes=${stats.videoBytesReceived} videoFrames=${stats.videoFramesDecoded}';
}

AudioTrafficStats extractAudioTrafficStats(List<StatsReport> reports) {
  var sentBytes = 0;
  var audioSentBytes = 0;
  var receivedBytes = 0;
  var packetsReceived = 0;
  var audioLevel = 0.0;
  var totalAudioEnergy = 0.0;
  var totalSamplesDuration = 0.0;
  var videoBytesReceived = 0;
  var videoFramesDecoded = 0;
  var audioJitterMs = 0.0;
  var videoJitterMs = 0.0;
  var audioPacketsLost = 0;
  var videoPacketsLost = 0;
  final candidatePairs = <String, Map<dynamic, dynamic>>{};
  final localCandidates = <String, Map<dynamic, dynamic>>{};
  final remoteCandidates = <String, Map<dynamic, dynamic>>{};
  final transports = <Map<dynamic, dynamic>>[];

  for (final report in reports) {
    final values = report.values;
    final kind = (values['kind'] ?? values['mediaType'] ?? '').toString();
    switch (report.type) {
      case 'candidate-pair':
        candidatePairs[report.id] = values;
        continue;
      case 'local-candidate':
        localCandidates[report.id] = values;
        continue;
      case 'remote-candidate':
        remoteCandidates[report.id] = values;
        continue;
      case 'transport':
        transports.add(values);
        continue;
    }
    if (report.type == 'outbound-rtp') {
      final outboundBytes = _toInt(values['bytesSent']);
      sentBytes += outboundBytes;
      if (kind.isEmpty || kind == 'audio') {
        audioSentBytes += outboundBytes;
      }
      continue;
    }
    if (report.type != 'inbound-rtp') {
      continue;
    }
    receivedBytes += _toInt(values['bytesReceived']);
    if (kind == 'video') {
      videoBytesReceived += _toInt(values['bytesReceived']);
      videoFramesDecoded += _toInt(values['framesDecoded']);
      videoJitterMs = _maxDouble(videoJitterMs, _secondsToMs(values['jitter']));
      videoPacketsLost += _toInt(values['packetsLost']);
      continue;
    }
    if (kind.isNotEmpty && kind != 'audio') {
      continue;
    }
    packetsReceived += _toInt(values['packetsReceived']);
    audioLevel = _maxDouble(audioLevel, _toDouble(values['audioLevel']));
    totalAudioEnergy += _toDouble(values['totalAudioEnergy']);
    totalSamplesDuration += _toDouble(values['totalSamplesDuration']);
    audioJitterMs = _maxDouble(audioJitterMs, _secondsToMs(values['jitter']));
    audioPacketsLost += _toInt(values['packetsLost']);
  }
  final selectedPairId = _selectCandidatePairId(
    candidatePairs: candidatePairs,
    transports: transports,
  );
  final selectedPair = selectedPairId == null
      ? null
      : candidatePairs[selectedPairId];
  final localCandidateId = selectedPair == null
      ? null
      : selectedPair['localCandidateId'];
  final remoteCandidateId = selectedPair == null
      ? null
      : selectedPair['remoteCandidateId'];
  final localCandidate = localCandidateId == null
      ? null
      : localCandidates[localCandidateId.toString()];
  final remoteCandidate = remoteCandidateId == null
      ? null
      : remoteCandidates[remoteCandidateId.toString()];
  return AudioTrafficStats(
    sentBytes: sentBytes,
    audioSentBytes: audioSentBytes,
    receivedBytes: receivedBytes,
    packetsReceived: packetsReceived,
    audioLevel: audioLevel,
    totalAudioEnergy: totalAudioEnergy,
    totalSamplesDuration: totalSamplesDuration,
    videoBytesReceived: videoBytesReceived,
    videoFramesDecoded: videoFramesDecoded,
    selectedCandidatePairId: selectedPairId,
    localCandidateType: _readString(localCandidate, 'candidateType'),
    remoteCandidateType: _readString(remoteCandidate, 'candidateType'),
    candidateProtocol:
        _readString(localCandidate, 'protocol') ??
        _readString(remoteCandidate, 'protocol'),
    localCandidateAddress: _candidateAddress(localCandidate),
    remoteCandidateAddress: _candidateAddress(remoteCandidate),
    currentRoundTripTimeMs: _secondsToMs(
      selectedPair == null ? null : selectedPair['currentRoundTripTime'],
    ),
    availableOutgoingBitrateKbps: _bitsToKbps(
      selectedPair == null ? null : selectedPair['availableOutgoingBitrate'],
    ),
    availableIncomingBitrateKbps: _bitsToKbps(
      selectedPair == null ? null : selectedPair['availableIncomingBitrate'],
    ),
    audioJitterMs: audioJitterMs,
    videoJitterMs: videoJitterMs,
    audioPacketsLost: audioPacketsLost,
    videoPacketsLost: videoPacketsLost,
  );
}

bool detectInboundAudioFlow({
  required AudioTrafficStats stats,
  required int lastInboundBytes,
  required int lastInboundPackets,
  required double lastInboundAudioEnergy,
  required double lastInboundSamplesDuration,
}) {
  if (stats.receivedBytes <= 0 && stats.packetsReceived <= 0) {
    return false;
  }
  if (lastInboundBytes >= 0 || lastInboundPackets >= 0) {
    final bytesAdvanced =
        stats.receivedBytes > lastInboundBytes ||
        stats.packetsReceived > lastInboundPackets;
    final audioEnergyAdvanced =
        lastInboundAudioEnergy >= 0 &&
        stats.totalAudioEnergy > lastInboundAudioEnergy &&
        stats.totalSamplesDuration > lastInboundSamplesDuration;
    final audioLevelPresent = stats.audioLevel > 0.0001;
    return bytesAdvanced && (audioEnergyAdvanced || audioLevelPresent);
  }
  return false;
}

bool detectInboundVideoFlow({
  required AudioTrafficStats stats,
  required int lastInboundVideoBytes,
  required int lastInboundVideoFramesDecoded,
}) {
  if (stats.videoBytesReceived <= 0 && stats.videoFramesDecoded <= 0) {
    return false;
  }
  if (lastInboundVideoBytes >= 0 || lastInboundVideoFramesDecoded >= 0) {
    final bytesAdvanced = stats.videoBytesReceived > lastInboundVideoBytes;
    final framesAdvanced =
        stats.videoFramesDecoded > lastInboundVideoFramesDecoded;
    return bytesAdvanced || framesAdvanced;
  }
  return false;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _toDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double _maxDouble(double left, double right) {
  return left >= right ? left : right;
}

String? _selectCandidatePairId({
  required Map<String, Map<dynamic, dynamic>> candidatePairs,
  required List<Map<dynamic, dynamic>> transports,
}) {
  for (final transport in transports) {
    final selectedPairId = transport['selectedCandidatePairId'];
    if (selectedPairId != null) {
      final normalized = selectedPairId.toString();
      if (candidatePairs.containsKey(normalized)) {
        return normalized;
      }
    }
  }
  for (final entry in candidatePairs.entries) {
    final values = entry.value;
    if (_toBool(values['selected']) &&
        (values['state']?.toString() == 'succeeded' ||
            !_hasValue(values['state']))) {
      return entry.key;
    }
  }
  for (final entry in candidatePairs.entries) {
    final values = entry.value;
    if (_toBool(values['nominated']) &&
        values['state']?.toString() == 'succeeded') {
      return entry.key;
    }
  }
  for (final entry in candidatePairs.entries) {
    if (entry.value['state']?.toString() == 'succeeded') {
      return entry.key;
    }
  }
  return null;
}

String? _readString(Map<dynamic, dynamic>? values, String key) {
  if (values == null) {
    return null;
  }
  final value = values[key];
  final normalized = value?.toString().trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

String? _candidateAddress(Map<dynamic, dynamic>? values) {
  if (values == null) {
    return null;
  }
  final address =
      _readString(values, 'address') ??
      _readString(values, 'ip') ??
      _readString(values, 'ipAddress');
  final port = _readString(values, 'port');
  if (address == null) {
    return null;
  }
  if (port == null) {
    return address;
  }
  return '$address:$port';
}

double _secondsToMs(dynamic value) {
  return _toDouble(value) * 1000;
}

double _bitsToKbps(dynamic value) {
  return _toDouble(value) / 1000;
}

bool _toBool(dynamic value) {
  if (value is bool) return value;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

bool _hasValue(dynamic value) {
  final normalized = value?.toString().trim() ?? '';
  return normalized.isNotEmpty;
}
