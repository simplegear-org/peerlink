import 'dart:typed_data';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

import '../runtime/secure_storage_wrapper.dart';
import 'identity_service.dart';
import 'session_crypto.dart';
import 'signature_service.dart';

/// Состояние криптосессии с конкретным peer.
class PeerSession {
  final String peerId;
  final SimplePublicKey signingPublicKey;
  final SimplePublicKey agreementPublicKey;

  SecretKey? sharedKey;

  bool established = false;

  PeerSession({
    required this.peerId,
    required this.signingPublicKey,
    required this.agreementPublicKey,
  });
}

abstract class PeerIdentityStore {
  Future<String?> read(String peerId);
  Future<void> write(String peerId, String value);
}

class SecurePeerIdentityStore implements PeerIdentityStore {
  const SecurePeerIdentityStore();

  static const String _prefix = 'peerlink.peer_identity.v1.';

  @override
  Future<String?> read(String peerId) {
    return SecureStorageWrapper.read('$_prefix$peerId');
  }

  @override
  Future<void> write(String peerId, String value) {
    return SecureStorageWrapper.write('$_prefix$peerId', value);
  }
}

class SessionManager {
  final IdentityService identity;
  final SessionCrypto crypto;
  final SignatureService signatures;
  final PeerIdentityStore _peerIdentityStore;

  final Map<String, PeerSession> _sessions = {};

  SessionManager({
    required this.identity,
    required this.crypto,
    required this.signatures,
    PeerIdentityStore? peerIdentityStore,
  }) : _peerIdentityStore =
           peerIdentityStore ?? const SecurePeerIdentityStore();

  /// Проверяет, установлена ли рабочая сессия с peer.
  bool hasSession(String peerId) {
    final s = _sessions[peerId];
    return s != null && s.established;
  }

  /// Возвращает текущую сессию по peerId.
  PeerSession? getSession(String peerId) {
    return _sessions[peerId];
  }

  Future<void> trustPeerIdentity({
    required String peerId,
    required SimplePublicKey signingPublicKey,
    required SimplePublicKey agreementPublicKey,
  }) async {
    final existing = _sessions[peerId];
    if (existing != null) {
      existing.sharedKey = null;
      existing.established = false;
    }
    await _persistPeerIdentity(
      peerId,
      signingPublicKey: signingPublicKey,
      agreementPublicKey: agreementPublicKey,
    );
  }

  Future<bool> ensureSession(String peerId) async {
    if (hasSession(peerId)) {
      return true;
    }
    return establishOfflineSession(peerId);
  }

  Future<bool> establishOfflineSession(String peerId) async {
    if (hasSession(peerId)) {
      return true;
    }
    final bundle = await _loadPeerIdentity(peerId);
    if (bundle == null) {
      return false;
    }
    final session = _sessions.putIfAbsent(
      peerId,
      () => PeerSession(
        peerId: peerId,
        signingPublicKey: bundle.signingPublicKey,
        agreementPublicKey: bundle.agreementPublicKey,
      ),
    );
    final shared = await crypto.deriveSharedKey(
      identity.agreementKeyPair,
      bundle.agreementPublicKey,
    );
    session.sharedKey = shared;
    session.established = true;
    return true;
  }

  /// Создает исходящий handshake payload (signing pub + agreement pub + signature).
  Future<Uint8List> initiateHandshake(String peerId) async {
    final signingPublic = identity.signingPublicKey;
    final agreementPublic = identity.agreementPublicKey;

    final signature = await signatures.sign(
      Uint8List.fromList(agreementPublic.bytes),
      identity.signingKeyPair,
    );

    final payload = Uint8List(
      signingPublic.bytes.length +
          agreementPublic.bytes.length +
          signature.length,
    );

    payload.setRange(0, signingPublic.bytes.length, signingPublic.bytes);
    payload.setRange(
      signingPublic.bytes.length,
      signingPublic.bytes.length + agreementPublic.bytes.length,
      agreementPublic.bytes,
    );

    payload.setRange(
      signingPublic.bytes.length + agreementPublic.bytes.length,
      payload.length,
      signature,
    );

    return payload;
  }

  /// Принимает входящий handshake, валидирует подпись и открывает сессию.
  Future<Uint8List> receiveHandshake(String peerId, Uint8List payload) async {
    final parsed = _parseHandshakePayload(payload);

    final verified = await signatures.verify(
      Uint8List.fromList(parsed.agreementPublic.bytes),
      parsed.signature,
      parsed.signingPublic,
    );

    if (!verified) {
      throw Exception("Invalid peer signature");
    }

    final session = PeerSession(
      peerId: peerId,
      signingPublicKey: parsed.signingPublic,
      agreementPublicKey: parsed.agreementPublic,
    );

    _sessions[peerId] = session;
    await _persistPeerIdentity(
      peerId,
      signingPublicKey: parsed.signingPublic,
      agreementPublicKey: parsed.agreementPublic,
    );

    final shared = await crypto.deriveSharedKey(
      identity.agreementKeyPair,
      parsed.agreementPublic,
    );

    session.sharedKey = shared;
    session.established = true;

    return initiateHandshake(peerId);
  }

  /// Завершает handshake на инициаторе после получения ответа от peer.
  Future<void> completeHandshake(String peerId, Uint8List payload) async {
    final parsed = _parseHandshakePayload(payload);

    final verified = await signatures.verify(
      Uint8List.fromList(parsed.agreementPublic.bytes),
      parsed.signature,
      parsed.signingPublic,
    );

    if (!verified) {
      throw Exception("Invalid peer signature");
    }

    final session = _sessions.putIfAbsent(
      peerId,
      () => PeerSession(
        peerId: peerId,
        signingPublicKey: parsed.signingPublic,
        agreementPublicKey: parsed.agreementPublic,
      ),
    );
    await _persistPeerIdentity(
      peerId,
      signingPublicKey: parsed.signingPublic,
      agreementPublicKey: parsed.agreementPublic,
    );

    final shared = await crypto.deriveSharedKey(
      identity.agreementKeyPair,
      parsed.agreementPublic,
    );

    session.sharedKey = shared;
    session.established = true;
  }

  /// Разбирает бинарный handshake payload на структурированные поля.
  _ParsedHandshake _parseHandshakePayload(Uint8List payload) {
    if (payload.length < 128) {
      throw const FormatException("Handshake payload is too short");
    }

    final signPub = payload.sublist(0, 32);
    final agreementPub = payload.sublist(32, 64);
    final signature = payload.sublist(64);

    final signingPublic = SimplePublicKey(signPub, type: KeyPairType.ed25519);

    final agreementPublic = SimplePublicKey(
      agreementPub,
      type: KeyPairType.x25519,
    );

    return _ParsedHandshake(
      signingPublic: signingPublic,
      agreementPublic: agreementPublic,
      signature: signature,
    );
  }

  /// Шифрует сообщение ключом активной сессии.
  Future<Uint8List> encrypt(String peerId, Uint8List message) async {
    final session = _sessions[peerId];

    if (session == null || !session.established) {
      throw Exception("Session not established");
    }

    return crypto.encrypt(message, session.sharedKey!);
  }

  /// Расшифровывает payload ключом активной сессии.
  Future<Uint8List> decrypt(String peerId, Uint8List payload) async {
    final session = _sessions[peerId];

    if (session == null || !session.established) {
      throw Exception("Session not established");
    }

    return crypto.decrypt(payload, session.sharedKey!);
  }

  Future<void> _persistPeerIdentity(
    String peerId, {
    required SimplePublicKey signingPublicKey,
    required SimplePublicKey agreementPublicKey,
  }) async {
    final payload = jsonEncode(<String, dynamic>{
      'signingPublicKey': base64Encode(signingPublicKey.bytes),
      'agreementPublicKey': base64Encode(agreementPublicKey.bytes),
    });
    await _peerIdentityStore.write(peerId, payload);
  }

  Future<_StoredPeerIdentity?> _loadPeerIdentity(String peerId) async {
    final raw = await _peerIdentityStore.read(peerId);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    final signingRaw = decoded['signingPublicKey'];
    final agreementRaw = decoded['agreementPublicKey'];
    if (signingRaw is! String || agreementRaw is! String) {
      return null;
    }
    return _StoredPeerIdentity(
      signingPublicKey: SimplePublicKey(
        base64Decode(signingRaw),
        type: KeyPairType.ed25519,
      ),
      agreementPublicKey: SimplePublicKey(
        base64Decode(agreementRaw),
        type: KeyPairType.x25519,
      ),
    );
  }
}

class _ParsedHandshake {
  final SimplePublicKey signingPublic;
  final SimplePublicKey agreementPublic;
  final Uint8List signature;

  _ParsedHandshake({
    required this.signingPublic,
    required this.agreementPublic,
    required this.signature,
  });
}

class _StoredPeerIdentity {
  final SimplePublicKey signingPublicKey;
  final SimplePublicKey agreementPublicKey;

  _StoredPeerIdentity({
    required this.signingPublicKey,
    required this.agreementPublicKey,
  });
}
