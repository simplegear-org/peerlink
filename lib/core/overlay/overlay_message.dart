import 'dart:convert';
import 'dart:typed_data';

class OverlayMessage {
  final String messageId;
  final String from;
  final String to;
  final Uint8List payload;
  final int ttl;

  OverlayMessage({
    required this.messageId,
    required this.from,
    required this.to,
    required this.payload,
    this.ttl = 8,
  });

  Uint8List encode() {
    final json = jsonEncode({
      'messageId': messageId,
      'from': from,
      'to': to,
      'payload': base64Encode(payload),
      'ttl': ttl,
    });

    return Uint8List.fromList(utf8.encode(json));
  }

  static OverlayMessage decode(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

    return OverlayMessage(
      messageId: decoded['messageId'] as String,
      from: decoded['from'] as String,
      to: decoded['to'] as String,
      payload: Uint8List.fromList(
        base64Decode(decoded['payload'] as String),
      ),
      ttl: decoded['ttl'] as int? ?? 8,
    );
  }

  OverlayMessage copyWith({
    String? messageId,
    String? from,
    String? to,
    Uint8List? payload,
    int? ttl,
  }) {
    return OverlayMessage(
      messageId: messageId ?? this.messageId,
      from: from ?? this.from,
      to: to ?? this.to,
      payload: payload ?? this.payload,
      ttl: ttl ?? this.ttl,
    );
  }
}
