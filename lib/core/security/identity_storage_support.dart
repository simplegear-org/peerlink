import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'account_identity.dart';
import 'identity_key_store.dart';

class IdentityStorageSupport {
  final IdentityKeyStore _keyStore;
  final Ed25519 _ed25519;
  final X25519 _x25519;
  final String signingKeyStorageKey;
  final String agreementKeyStorageKey;
  final String installIdStorageKey;

  const IdentityStorageSupport({
    required IdentityKeyStore keyStore,
    required Ed25519 ed25519,
    required X25519 x25519,
    required this.signingKeyStorageKey,
    required this.agreementKeyStorageKey,
    required this.installIdStorageKey,
  }) : _keyStore = keyStore,
       _ed25519 = ed25519,
       _x25519 = x25519;

  Future<AccountIdentity?> readStoredAccountIdentity(String storageKey) async {
    final raw = await _keyStore.read(storageKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return AccountIdentity.fromJson(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> writeAccountIdentity(
    String storageKey,
    AccountIdentity identity,
  ) {
    return _keyStore.write(storageKey, jsonEncode(identity.toJson()));
  }

  Future<SimpleKeyPair> loadOrCreateSigningKeyPair() async {
    final raw = await _keyStore.read(signingKeyStorageKey);
    if (raw == null || raw.isEmpty) {
      final generated = await _ed25519.newKeyPair();
      await persistKeyPair(signingKeyStorageKey, generated);
      return generated;
    }
    return restoreKeyPair(raw, KeyPairType.ed25519);
  }

  Future<SimpleKeyPair> loadOrCreateAgreementKeyPair() async {
    final raw = await _keyStore.read(agreementKeyStorageKey);
    if (raw == null || raw.isEmpty) {
      final generated = await _x25519.newKeyPair();
      await persistKeyPair(agreementKeyStorageKey, generated);
      return generated;
    }
    return restoreKeyPair(raw, KeyPairType.x25519);
  }

  Future<String> loadOrCreateInstallationId() async {
    final raw = await _keyStore.read(installIdStorageKey);
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }
    final generated = generateInstallationId();
    await _keyStore.write(installIdStorageKey, generated);
    return generated;
  }

  String generateInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  String generateAccountId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> persistKeyPair(String key, SimpleKeyPair keyPair) async {
    final data = await keyPair.extract();
    final payload = jsonEncode({
      'privateKey': base64Encode(data.bytes),
      'publicKey': base64Encode(data.publicKey.bytes),
    });
    await _keyStore.write(key, payload);
  }

  SimpleKeyPair restoreKeyPair(String raw, KeyPairType type) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid keypair payload format');
    }

    final privateKey = decoded['privateKey'];
    final publicKey = decoded['publicKey'];
    if (privateKey is! String || publicKey is! String) {
      throw const FormatException('Invalid keypair payload fields');
    }

    return SimpleKeyPairData(
      base64Decode(privateKey),
      publicKey: SimplePublicKey(base64Decode(publicKey), type: type),
      type: type,
    );
  }
}
