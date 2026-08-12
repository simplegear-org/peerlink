import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class SessionCrypto {

  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();

  Future<SecretKey> deriveSharedKey(
    SimpleKeyPair myKey,
    SimplePublicKey peerKey,
  ) async {

    final shared = await _x25519.sharedSecretKey(
      keyPair: myKey,
      remotePublicKey: peerKey,
    );

    return shared;
  }

  Future<Uint8List> encrypt(
    Uint8List message,
    SecretKey key,
  ) async {

    final nonce = _aes.newNonce();

    final encrypted = await _aes.encrypt(
      message,
      secretKey: key,
      nonce: nonce,
    );

    final result = Uint8List(
      nonce.length + encrypted.cipherText.length + encrypted.mac.bytes.length,
    );

    result.setRange(0, nonce.length, nonce);
    result.setRange(
      nonce.length,
      nonce.length + encrypted.cipherText.length,
      encrypted.cipherText,
    );
    result.setRange(
      nonce.length + encrypted.cipherText.length,
      result.length,
      encrypted.mac.bytes,
    );

    return result;
  }

  Future<Uint8List> decrypt(
    Uint8List data,
    SecretKey key,
  ) async {

    final nonce = data.sublist(0, 12);
    final mac = data.sublist(data.length - 16);

    final cipher = data.sublist(
      12,
      data.length - 16,
    );

    final box = SecretBox(
      cipher,
      nonce: nonce,
      mac: Mac(mac),
    );

    final decrypted = await _aes.decrypt(
      box,
      secretKey: key,
    );

    return Uint8List.fromList(decrypted);
  }
}