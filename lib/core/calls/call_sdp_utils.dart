String preferVideoCodecsInSdp(String sdp, List<String> preferredCodecs) {
  final lines = sdp.split('\r\n');
  final codecOrder = preferredCodecs
      .map((codec) => codec.toLowerCase())
      .toList();

  final mediaLineIndex = lines.indexWhere(
    (line) => line.startsWith('m=video '),
  );
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

String? extractPreferredVideoCodec(String? sdp) {
  if (sdp == null || sdp.isEmpty) {
    return null;
  }
  final lines = sdp.split('\r\n');
  final mediaLine = lines
      .where((line) => line.startsWith('m=video '))
      .cast<String?>()
      .firstWhere((line) => line != null, orElse: () => null);
  if (mediaLine == null) {
    return null;
  }
  final mediaParts = mediaLine.split(' ');
  if (mediaParts.length <= 3) {
    return null;
  }
  final preferredPayload = mediaParts[3];
  for (final line in lines) {
    final match = RegExp(
      r'^a=rtpmap:' + RegExp.escape(preferredPayload) + r'\s+([^/]+)',
    ).firstMatch(line);
    if (match != null) {
      return match.group(1)?.toUpperCase();
    }
  }
  return null;
}

List<String> extractVideoMids(String? sdp) {
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

String sdpMediaSummary(String? sdp) {
  if (sdp == null || sdp.isEmpty) {
    return 'sdp=empty';
  }
  final lines = sdp.split('\r\n');
  var audioCount = 0;
  var videoCount = 0;
  final sections = <String>[];
  String? currentKind;
  String? currentMid;
  String currentDirection = 'none';

  void flushSection() {
    final kind = currentKind;
    if (kind == null) {
      return;
    }
    if (kind == 'audio') {
      audioCount += 1;
    } else if (kind == 'video') {
      videoCount += 1;
    }
    sections.add('$kind:mid=${currentMid ?? "na"}:$currentDirection');
  }

  for (final line in lines) {
    if (line.startsWith('m=')) {
      flushSection();
      final parts = line.split(' ');
      currentKind = parts.first.substring(2);
      currentMid = null;
      currentDirection = 'none';
      continue;
    }
    if (currentKind == null) {
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
  return 'audioM=$audioCount videoM=$videoCount sections=[${sections.join(",")}]';
}

String candidateType(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return 'unknown';
  }
  final match = RegExp(r'typ\s+([a-zA-Z0-9]+)').firstMatch(candidate);
  return match?.group(1) ?? 'unknown';
}

String candidateProtocol(String? candidate) {
  if (candidate == null || candidate.isEmpty) {
    return 'unknown';
  }
  final match = RegExp(r'^candidate:\S+\s+\d+\s+(\S+)').firstMatch(candidate);
  return match?.group(1)?.toLowerCase() ?? 'unknown';
}

String candidateAddress(String? candidate) {
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
