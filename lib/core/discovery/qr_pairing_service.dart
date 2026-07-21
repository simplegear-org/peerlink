import 'dart:convert';

class QrPairingService {

  String encodePeer({
    required String peerId,
    required String address,
  }) {
    final data = {
      "peerId": peerId,
      "address": address
    };

    return jsonEncode(data);
  }

  Map<String, dynamic> decode(String qr) {
    return jsonDecode(qr);
  }
}