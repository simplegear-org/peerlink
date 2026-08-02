import 'dart:convert';
import 'dart:typed_data';

class BootstrapPendingSignal {
  final String peerId;
  final String type;
  final Map<String, dynamic> data;
  int attempts = 0;
  DateTime? nextAttempt;

  BootstrapPendingSignal({
    required this.peerId,
    required this.type,
    required this.data,
  });

  bool samePayloadAs(BootstrapPendingSignal other) {
    return type == other.type && jsonEncode(data) == jsonEncode(other.data);
  }
}

class BootstrapReadyTimeout {
  const BootstrapReadyTimeout();
}

class BootstrapRegisterProof {
  final String scheme;
  final String peerId;
  final int timestampMs;
  final String nonce;
  final Uint8List signingPublicKey;
  final Uint8List signature;
  final Map<String, dynamic>? identityProfile;

  const BootstrapRegisterProof({
    required this.scheme,
    required this.peerId,
    required this.timestampMs,
    required this.nonce,
    required this.signingPublicKey,
    required this.signature,
    this.identityProfile,
  });

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'scheme': scheme,
      'peerId': peerId,
      'timestampMs': timestampMs,
      'nonce': nonce,
      'signingPublicKey': base64Encode(signingPublicKey),
      'signature': base64Encode(signature),
    };
    if (identityProfile != null && identityProfile!.isNotEmpty) {
      payload['identityProfile'] = identityProfile;
    }
    return payload;
  }
}
