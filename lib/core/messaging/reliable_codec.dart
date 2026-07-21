import 'dart:convert';
import 'dart:typed_data';

enum ReliableEnvelopeType {
  plainMessage,
  secureMessage,
  handshakeInit,
  handshakeResponse,
}

ReliableEnvelopeType parseReliableEnvelopeType(String rawType) {
  return ReliableEnvelopeType.values.firstWhere(
    (value) => value.name == rawType,
    orElse: () {
      throw FormatException('Unknown reliable envelope type: $rawType');
    },
  );
}

Uint8List buildReliableSignaturePayload({
  required String envelopeId,
  required String from,
  required String to,
  required int timestampMs,
  required int ttlSeconds,
  required Uint8List payload,
}) {
  final header = '$envelopeId|$from|$to|$timestampMs|$ttlSeconds|';
  final headerBytes = utf8.encode(header);
  final bytes = Uint8List(headerBytes.length + payload.length);
  bytes.setRange(0, headerBytes.length, headerBytes);
  bytes.setRange(headerBytes.length, bytes.length, payload);
  return bytes;
}

Uint8List buildReliableAckSignaturePayload({
  required String id,
  required String from,
  required String to,
  required int timestampMs,
}) {
  final header = '$id|$from|$to|$timestampMs';
  return Uint8List.fromList(utf8.encode(header));
}

String buildDirectBlobScopeId(String selfId, String peerId) {
  final peers = <String>[selfId.trim(), peerId.trim()]..sort();
  return 'dm:${peers.join('|')}';
}

Uint8List buildReliableGroupSignaturePayload({
  required String envelopeId,
  required String from,
  required String groupId,
  required List<String> recipients,
  required int timestampMs,
  required int ttlSeconds,
  required Uint8List payload,
}) {
  final recipientsPart = recipients.join(',');
  final header =
      '$envelopeId|$from|$groupId|$recipientsPart|$timestampMs|$ttlSeconds|';
  final headerBytes = utf8.encode(header);
  final bytes = Uint8List(headerBytes.length + payload.length);
  bytes.setRange(0, headerBytes.length, headerBytes);
  bytes.setRange(headerBytes.length, bytes.length, payload);
  return bytes;
}

Uint8List buildReliableBlobSignaturePayload({
  required String id,
  required String from,
  required String groupId,
  required String fileName,
  required String? mimeType,
  required int timestampMs,
  required int ttlSeconds,
  required Uint8List payload,
}) {
  final normalizedMime = (mimeType ?? '').trim();
  final header =
      '$id|$from|$groupId|$fileName|$normalizedMime|$timestampMs|$ttlSeconds|';
  final headerBytes = utf8.encode(header);
  final bytes = Uint8List(headerBytes.length + payload.length);
  bytes.setRange(0, headerBytes.length, headerBytes);
  bytes.setRange(headerBytes.length, bytes.length, payload);
  return bytes;
}

Uint8List buildReliableGroupMembersSignaturePayload({
  required String id,
  required String from,
  required String groupId,
  required String ownerPeerId,
  required List<String> memberPeerIds,
  required int timestampMs,
  required int ttlSeconds,
}) {
  final members = List<String>.from(memberPeerIds)..sort();
  final membersPart = members.join(',');
  final header =
      '$id|$from|$groupId|$ownerPeerId|$membersPart|$timestampMs|$ttlSeconds';
  return Uint8List.fromList(utf8.encode(header));
}
