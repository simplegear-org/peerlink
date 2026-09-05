// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:isolate';
import 'dart:typed_data';

class ChatDirectMediaCryptoService {
  static const List<int> _magic = <int>[0x50, 0x4c, 0x44, 0x4d, 0x31];
  static const int _isolateThresholdBytes = 256 * 1024;

  const ChatDirectMediaCryptoService({
    required Future<Uint8List> Function(String peerId, Uint8List plainBytes)
    encryptBytes,
    required Future<Uint8List> Function(String peerId, Uint8List encryptedBytes)
    decryptBytes,
  }) : _encryptBytes = encryptBytes,
       _decryptBytes = decryptBytes;

  final Future<Uint8List> Function(String peerId, Uint8List plainBytes)
  _encryptBytes;
  final Future<Uint8List> Function(String peerId, Uint8List encryptedBytes)
  _decryptBytes;

  Future<Uint8List> encryptForPeer({
    required String peerId,
    required Uint8List plainBytes,
  }) async {
    final encrypted = await _encryptBytes(peerId, plainBytes);
    if (encrypted.length >= _isolateThresholdBytes) {
      return _frameEncryptedPayloadInIsolate(encrypted);
    }
    return _frameEncryptedPayload(encrypted);
  }

  Future<Uint8List> decryptFromPeer({
    required String peerId,
    required Uint8List payload,
  }) async {
    if (!_hasMagic(payload)) {
      return payload;
    }
    return _decryptBytes(peerId, Uint8List.sublistView(payload, _magic.length));
  }

  static bool _hasMagic(Uint8List payload) {
    if (payload.length < _magic.length) {
      return false;
    }
    for (var i = 0; i < _magic.length; i++) {
      if (payload[i] != _magic[i]) {
        return false;
      }
    }
    return true;
  }
}

Future<Uint8List> _frameEncryptedPayloadInIsolate(Uint8List encrypted) async {
  final encryptedData = TransferableTypedData.fromList(<Uint8List>[encrypted]);
  final framedData = await Isolate.run(() {
    final encryptedBytes = encryptedData.materialize().asUint8List();
    return TransferableTypedData.fromList(<Uint8List>[
      _frameEncryptedPayload(encryptedBytes),
    ]);
  });
  return framedData.materialize().asUint8List();
}

Uint8List _frameEncryptedPayload(Uint8List encrypted) {
  final framed =
      Uint8List(ChatDirectMediaCryptoService._magic.length + encrypted.length)
        ..setRange(
          0,
          ChatDirectMediaCryptoService._magic.length,
          ChatDirectMediaCryptoService._magic,
        )
        ..setRange(
          ChatDirectMediaCryptoService._magic.length,
          ChatDirectMediaCryptoService._magic.length + encrypted.length,
          encrypted,
        );
  return framed;
}
