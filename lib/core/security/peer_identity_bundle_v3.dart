import 'dart:convert';
import 'dart:typed_data';

class PeerIdentityBundleV3 {
  static const String type = 'peerlink_identity_bundle';
  static const int version = 3;

  final String peerId;
  final String signingPublicKey;
  final String agreementPublicKey;
  final String signature;

  const PeerIdentityBundleV3({
    required this.peerId,
    required this.signingPublicKey,
    required this.agreementPublicKey,
    required this.signature,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'version': version,
    'peerId': peerId,
    'signingPublicKey': signingPublicKey,
    'agreementPublicKey': agreementPublicKey,
    'signature': signature,
  };

  static PeerIdentityBundleV3? fromJson(Map<String, dynamic> json) {
    if (json['type'] != type || json['version'] != version) {
      return null;
    }
    final peerId = json['peerId'];
    final signingPublicKey = json['signingPublicKey'];
    final agreementPublicKey = json['agreementPublicKey'];
    final signature = json['signature'];
    if (peerId is! String ||
        signingPublicKey is! String ||
        agreementPublicKey is! String ||
        signature is! String ||
        peerId.trim().isEmpty ||
        signingPublicKey.trim().isEmpty ||
        agreementPublicKey.trim().isEmpty ||
        signature.trim().isEmpty) {
      return null;
    }
    return PeerIdentityBundleV3(
      peerId: peerId.trim(),
      signingPublicKey: signingPublicKey.trim(),
      agreementPublicKey: agreementPublicKey.trim(),
      signature: signature.trim(),
    );
  }

  static Uint8List signaturePayload({
    required String peerId,
    required String signingPublicKey,
    required String agreementPublicKey,
  }) {
    final payload = <String, dynamic>{
      'type': type,
      'version': version,
      'peerId': peerId.trim(),
      'signingPublicKey': signingPublicKey.trim(),
      'agreementPublicKey': agreementPublicKey.trim(),
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
  }
}
