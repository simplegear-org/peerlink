import 'dart:convert';
import 'dart:typed_data';

class RelayEnvelope {
  final String id;
  final String from;
  final String to;
  final String? groupId;
  final List<String>? recipients;
  final int timestampMs;
  final int ttlSeconds;
  final Uint8List payload;
  final Uint8List signature;
  final Uint8List senderSigningPublicKey;

  RelayEnvelope({
    required this.id,
    required this.from,
    required this.to,
    this.groupId,
    this.recipients,
    required this.timestampMs,
    required this.ttlSeconds,
    required this.payload,
    required this.signature,
    required this.senderSigningPublicKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'ts': timestampMs,
        'ttl': ttlSeconds,
        'payload': base64Encode(payload),
        'sig': base64Encode(signature),
        'signingPub': base64Encode(senderSigningPublicKey),
      };

  factory RelayEnvelope.fromJson(Map<String, dynamic> json) {
    return RelayEnvelope(
      id: json['id'] as String,
      from: json['from'] as String,
      to: json['to'] as String,
      groupId: json['groupId'] as String?,
      recipients: json['recipients'] is List
          ? (json['recipients'] as List)
              .whereType<String>()
              .toList(growable: false)
          : null,
      timestampMs: json['ts'] as int,
      ttlSeconds: json['ttl'] as int,
      payload: base64Decode(json['payload'] as String),
      signature: base64Decode(json['sig'] as String),
      senderSigningPublicKey: base64Decode(json['signingPub'] as String),
    );
  }
}

class RelayGroupEnvelope {
  final String id;
  final String from;
  final String groupId;
  final List<String> recipientIds;
  final int timestampMs;
  final int ttlSeconds;
  final Uint8List payload;
  final Uint8List signature;
  final Uint8List senderSigningPublicKey;

  RelayGroupEnvelope({
    required this.id,
    required this.from,
    required this.groupId,
    required this.recipientIds,
    required this.timestampMs,
    required this.ttlSeconds,
    required this.payload,
    required this.signature,
    required this.senderSigningPublicKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'groupId': groupId,
        'recipients': recipientIds,
        'ts': timestampMs,
        'ttl': ttlSeconds,
        'payload': base64Encode(payload),
        'sig': base64Encode(signature),
        'signingPub': base64Encode(senderSigningPublicKey),
      };
}

class RelayAck {
  final String id;
  final String from;
  final String to;
  final int timestampMs;
  final Uint8List signature;
  final Uint8List senderSigningPublicKey;

  RelayAck({
    required this.id,
    required this.from,
    required this.to,
    required this.timestampMs,
    required this.signature,
    required this.senderSigningPublicKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'ts': timestampMs,
        'sig': base64Encode(signature),
        'signingPub': base64Encode(senderSigningPublicKey),
      };
}

class RelayFetchResult {
  final List<RelayEnvelope> messages;
  final String? cursor;

  RelayFetchResult({
    required this.messages,
    required this.cursor,
  });
}

class RelayBlobUploadEnvelope {
  final String id;
  final String from;
  final String groupId;
  final String fileName;
  final String? mimeType;
  final int timestampMs;
  final int ttlSeconds;
  final Uint8List payload;
  final Uint8List signature;
  final Uint8List senderSigningPublicKey;

  RelayBlobUploadEnvelope({
    required this.id,
    required this.from,
    required this.groupId,
    required this.fileName,
    required this.mimeType,
    required this.timestampMs,
    required this.ttlSeconds,
    required this.payload,
    required this.signature,
    required this.senderSigningPublicKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'groupId': groupId,
        'fileName': fileName,
        'mimeType': mimeType,
        'ts': timestampMs,
        'ttl': ttlSeconds,
        'payload': base64Encode(payload),
        'sig': base64Encode(signature),
        'signingPub': base64Encode(senderSigningPublicKey),
      };
}

class RelayBlobDownload {
  final String id;
  final String fileName;
  final String? mimeType;
  final int sizeBytes;
  final Uint8List payload;

  RelayBlobDownload({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.payload,
  });
}

class RelayGroupMembersUpdateEnvelope {
  final String id;
  final String from;
  final String groupId;
  final String ownerPeerId;
  final List<String> memberPeerIds;
  final int timestampMs;
  final int ttlSeconds;
  final Uint8List signature;
  final Uint8List senderSigningPublicKey;

  RelayGroupMembersUpdateEnvelope({
    required this.id,
    required this.from,
    required this.groupId,
    required this.ownerPeerId,
    required this.memberPeerIds,
    required this.timestampMs,
    required this.ttlSeconds,
    required this.signature,
    required this.senderSigningPublicKey,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'groupId': groupId,
        'ownerPeerId': ownerPeerId,
        'memberPeerIds': memberPeerIds,
        'ts': timestampMs,
        'ttl': ttlSeconds,
        'sig': base64Encode(signature),
        'signingPub': base64Encode(senderSigningPublicKey),
      };
}
