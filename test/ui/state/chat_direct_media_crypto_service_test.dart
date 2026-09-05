import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/chat/application/chat_direct_media_crypto_service.dart';

void main() {
  test(
    'encrypts direct media with frame and decrypts framed payload',
    () async {
      final service = ChatDirectMediaCryptoService(
        encryptBytes: (peerId, plainBytes) async =>
            Uint8List.fromList(plainBytes.reversed.toList(growable: false)),
        decryptBytes: (peerId, encryptedBytes) async =>
            Uint8List.fromList(encryptedBytes.reversed.toList(growable: false)),
      );

      final encrypted = await service.encryptForPeer(
        peerId: 'peer-a',
        plainBytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(encrypted, isNot(equals(<int>[1, 2, 3])));

      final decrypted = await service.decryptFromPeer(
        peerId: 'peer-a',
        payload: encrypted,
      );
      expect(decrypted, equals(<int>[1, 2, 3]));
    },
  );

  test('keeps legacy unframed direct media payload unchanged', () async {
    final service = ChatDirectMediaCryptoService(
      encryptBytes: (_, plainBytes) async => plainBytes,
      decryptBytes: (_, encryptedBytes) async {
        throw StateError('decrypt should not be called');
      },
    );

    final payload = Uint8List.fromList(<int>[7, 8, 9]);
    final decoded = await service.decryptFromPeer(
      peerId: 'peer-a',
      payload: payload,
    );
    expect(decoded, same(payload));
  });
}
