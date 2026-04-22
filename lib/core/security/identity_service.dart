import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Абстракция хранилища ключей identity.
abstract class IdentityKeyStore {
  /// Читает сохраненное значение по ключу.
  Future<String?> read(String key);

  /// Записывает значение по ключу.
  Future<void> write(String key, String value);
}

/// Реализация хранилища ключей через flutter_secure_storage.
class SecureIdentityKeyStore implements IdentityKeyStore {
  const SecureIdentityKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }
}

class IdentityService {
  static const _signingKeyStorageKey = "peerlink.identity.signing.ed25519";
  static const _agreementKeyStorageKey = "peerlink.identity.agreement.x25519";
  static const _installIdStorageKey = "peerlink.identity.installation.id.v1";

  late final SimpleKeyPair _signingKeyPair;
  late final SimplePublicKey _signingPublicKey;
  late final SimpleKeyPair _agreementKeyPair;
  late final SimplePublicKey _agreementPublicKey;
  late final String nodeId;
  late final String legacyNodeId;
  late final String installationId;

  final IdentityKeyStore _keyStore;
  final _ed25519 = Ed25519();
  final _x25519 = X25519();
  final _sha256 = Sha256();
  String? _fcmTokenHash;
  String? _endpointId;
  bool _initialized = false;

  /// Создает сервис identity с возможностью подменить key-store (например, в тестах).
  IdentityService({IdentityKeyStore? keyStore})
      : _keyStore = keyStore ?? const SecureIdentityKeyStore();

  /// Инициализирует identity и загружает/генерирует ключевые пары.
  Future<void> initialize({String? fcmToken}) async {
    if (_initialized) {
      if (fcmToken != null) {
        await updateMessagingEndpoint(fcmToken);
      }
      return;
    }

    _signingKeyPair = await _loadOrCreateSigningKeyPair();
    _signingPublicKey = await _signingKeyPair.extractPublicKey();
    _agreementKeyPair = await _loadOrCreateAgreementKeyPair();
    _agreementPublicKey = await _agreementKeyPair.extractPublicKey();
    installationId = await _loadOrCreateInstallationId();
    legacyNodeId = await _deriveLegacyPeerId(_signingPublicKey);
    nodeId = await _deriveStablePeerId(
      _signingPublicKey,
      installationId,
    );
    if (fcmToken != null) {
      await updateMessagingEndpoint(fcmToken);
    }
    _initialized = true;
  }

  SimpleKeyPair get signingKeyPair => _signingKeyPair;

  SimplePublicKey get publicKey => _signingPublicKey;
  SimplePublicKey get signingPublicKey => _signingPublicKey;
  SimpleKeyPair get agreementKeyPair => _agreementKeyPair;
  SimplePublicKey get agreementPublicKey => _agreementPublicKey;
  String? get endpointId => _endpointId;
  String? get fcmTokenHash => _fcmTokenHash;

  Map<String, dynamic> identityProfileJson() {
    final signingPublicKeyBase64 = base64Encode(_signingPublicKey.bytes);
    final agreementPublicKeyBase64 = base64Encode(_agreementPublicKey.bytes);
    return <String, dynamic>{
      'schemaVersion': 2,
      'stableUserId': nodeId,
      'legacyUserId': legacyNodeId,
      'publicKey': signingPublicKeyBase64,
      'agreementPublicKey': agreementPublicKeyBase64,
      'deviceInstallIdHash': _sha256Hex(utf8.encode(installationId)),
      'endpoint': <String, dynamic>{
        'endpointId': _endpointId,
        'push': <String, dynamic>{
          'provider': 'fcm',
          'tokenHash': _fcmTokenHash,
        },
      },
    };
  }

  Future<void> updateMessagingEndpoint(String? fcmToken) async {
    final normalized = fcmToken?.trim();
    if (normalized == null || normalized.isEmpty) {
      _fcmTokenHash = null;
      _endpointId = null;
      return;
    }
    _fcmTokenHash = _sha256Hex(utf8.encode(normalized));
    final endpointSource = utf8.encode('endpoint:v2:$nodeId:$normalized');
    _endpointId = _sha256Base64Url(endpointSource).substring(0, 32);
  }

  /// Предыдущий формат peerId: SHA-256 от публичного signing-ключа.
  Future<String> _deriveLegacyPeerId(SimplePublicKey key) async {
    final hash = await _sha256.hash(key.bytes);
    return base64UrlEncode(hash.bytes).substring(0, 32);
  }

  /// Новый стабильный userId: SHA-256(publicKey + installationId).
  Future<String> _deriveStablePeerId(
    SimplePublicKey key,
    String installId,
  ) async {
    final signingKey = base64Encode(key.bytes);
    final payload = utf8.encode('uid:v2:$signingKey:$installId');
    final hash = await _sha256.hash(payload);
    return base64UrlEncode(hash.bytes).substring(0, 32);
  }

  Future<SimpleKeyPair> _loadOrCreateSigningKeyPair() async {
    final raw = await _keyStore.read(_signingKeyStorageKey);
    if (raw == null || raw.isEmpty) {
      final generated = await _ed25519.newKeyPair();
      await _persistKeyPair(_signingKeyStorageKey, generated);
      return generated;
    }

    return _restoreKeyPair(raw, KeyPairType.ed25519);
  }

  Future<SimpleKeyPair> _loadOrCreateAgreementKeyPair() async {
    final raw = await _keyStore.read(_agreementKeyStorageKey);
    if (raw == null || raw.isEmpty) {
      final generated = await _x25519.newKeyPair();
      await _persistKeyPair(_agreementKeyStorageKey, generated);
      return generated;
    }

    return _restoreKeyPair(raw, KeyPairType.x25519);
  }

  Future<String> _loadOrCreateInstallationId() async {
    final raw = await _keyStore.read(_installIdStorageKey);
    if (raw != null && raw.isNotEmpty) {
      return raw;
    }

    final generated = _generateInstallationId();
    await _keyStore.write(_installIdStorageKey, generated);
    return generated;
  }

  String _generateInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Сохраняет ключевую пару в JSON-представлении.
  Future<void> _persistKeyPair(String key, SimpleKeyPair keyPair) async {
    final data = await keyPair.extract();
    final payload = jsonEncode({
      "privateKey": base64Encode(data.bytes),
      "publicKey": base64Encode(data.publicKey.bytes),
    });

    await _keyStore.write(key, payload);
  }

  /// Восстанавливает ключевую пару из JSON-представления.
  SimpleKeyPair _restoreKeyPair(String raw, KeyPairType type) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException("Invalid keypair payload format");
    }

    final privateKey = decoded["privateKey"];
    final publicKey = decoded["publicKey"];

    if (privateKey is! String || publicKey is! String) {
      throw const FormatException("Invalid keypair payload fields");
    }

    return SimpleKeyPairData(
      base64Decode(privateKey),
      publicKey: SimplePublicKey(
        base64Decode(publicKey),
        type: type,
      ),
      type: type,
    );
  }

  String _sha256Hex(List<int> bytes) {
    final digest = sha256.convert(bytes).bytes;
    return digest.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
  }

  String _sha256Base64Url(List<int> bytes) {
    final digest = sha256.convert(bytes).bytes;
    return base64UrlEncode(digest);
  }
}
