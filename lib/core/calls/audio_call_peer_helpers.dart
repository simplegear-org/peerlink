part of 'audio_call_peer.dart';

String _preferVideoCodecsInSdp(String sdp, List<String> preferredCodecs) {
  final lines = sdp.split('\r\n');
  final codecOrder = preferredCodecs.map((codec) => codec.toLowerCase()).toList();

  final mediaLineIndex = lines.indexWhere((line) => line.startsWith('m=video '));
  if (mediaLineIndex == -1) {
    return sdp;
  }

  final payloadToCodec = <String, String>{};
  for (final line in lines) {
    if (!line.startsWith('a=rtpmap:')) {
      continue;
    }
    final match = RegExp(r'^a=rtpmap:(\d+)\s+([^/]+)').firstMatch(line);
    if (match == null) {
      continue;
    }
    payloadToCodec[match.group(1)!] = match.group(2)!.toLowerCase();
  }

  final mediaParts = lines[mediaLineIndex].split(' ');
  if (mediaParts.length <= 3) {
    return sdp;
  }
  final payloads = mediaParts.sublist(3);
  payloads.sort((a, b) {
    final aIndex = codecOrder.indexOf(payloadToCodec[a] ?? '');
    final bIndex = codecOrder.indexOf(payloadToCodec[b] ?? '');
    final aRank = aIndex == -1 ? codecOrder.length : aIndex;
    final bRank = bIndex == -1 ? codecOrder.length : bIndex;
    return aRank.compareTo(bRank);
  });
  lines[mediaLineIndex] = [...mediaParts.take(3), ...payloads].join(' ');
  return lines.join('\r\n');
}

String? _extractPreferredVideoCodec(String? sdp) {
  if (sdp == null || sdp.isEmpty) {
    return null;
  }
  final lines = sdp.split('\r\n');
  final mediaLine = lines.where((line) => line.startsWith('m=video ')).cast<String?>().firstWhere((line) => line != null, orElse: () => null);
  if (mediaLine == null) {
    return null;
  }
  final mediaParts = mediaLine.split(' ');
  if (mediaParts.length <= 3) {
    return null;
  }
  final preferredPayload = mediaParts[3];
  for (final line in lines) {
    final match = RegExp(r'^a=rtpmap:' + RegExp.escape(preferredPayload) + r'\s+([^/]+)').firstMatch(line);
    if (match != null) {
      return match.group(1)?.toUpperCase();
    }
  }
  return null;
}

List<String> _extractVideoMids(String? sdp) {
  if (sdp == null || sdp.isEmpty) {
    return const <String>[];
  }
  final lines = sdp.split('\r\n');
  final mids = <String>[];
  var inVideoSection = false;
  for (final line in lines) {
    if (line.startsWith('m=')) {
      inVideoSection = line.startsWith('m=video ');
      continue;
    }
    if (inVideoSection && line.startsWith('a=mid:')) {
      mids.add(line.substring('a=mid:'.length));
    }
  }
  return mids;
}

String _candidateType(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return 'unknown';
  }
  final match = RegExp(r'typ\s+([a-zA-Z0-9]+)').firstMatch(candidate);
  return match?.group(1) ?? 'unknown';
}

String _candidateProtocol(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return 'unknown';
  }
  final match = RegExp(r'^candidate:\S+\s+\d+\s+(\S+)').firstMatch(candidate);
  return match?.group(1)?.toLowerCase() ?? 'unknown';
}

String _candidateAddress(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return 'unknown';
  }
  final match = RegExp(
    r'^candidate:\S+\s+\d+\s+\S+\s+\d+\s+(\S+)\s+(\d+)',
  ).firstMatch(candidate);
  if (match == null) {
    return 'unknown';
  }
  return '${match.group(1)}:${match.group(2)}';
}

class _AudioTrafficStats {
  final int sentBytes;
  final int receivedBytes;
  final int packetsReceived;
  final double audioLevel;
  final double totalAudioEnergy;
  final double totalSamplesDuration;
  final int videoBytesReceived;
  final int videoFramesDecoded;

  const _AudioTrafficStats({
    required this.sentBytes,
    required this.receivedBytes,
    required this.packetsReceived,
    required this.audioLevel,
    required this.totalAudioEnergy,
    required this.totalSamplesDuration,
    required this.videoBytesReceived,
    required this.videoFramesDecoded,
  });
}
