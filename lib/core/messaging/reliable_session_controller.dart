import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'reliable_codec.dart';
import '../relay/relay_client.dart';
import '../security/session_manager.dart';

typedef ReliableSessionSendControlEnvelope =
    Future<void> Function({
      required String peerId,
      required ReliableEnvelopeType type,
      required Uint8List payload,
    });

class ReliableSessionController {
  final RelayClient _relay;
  final SessionManager _sessions;
  final bool Function() _isDisposed;
  final bool Function() _isRelayEnabled;
  final Future<void> Function(String peerId) _flushPendingMessages;
  final Future<void> Function(String peerId) _flushPendingSecureInbound;
  final ReliableSessionSendControlEnvelope _sendControlEnvelope;
  final void Function(String message) _log;
  final Set<String> _handshakeInFlight = <String>{};
  final Map<String, int> _handshakeAttempts = <String, int>{};
  final Map<String, Timer> _handshakeTimers = <String, Timer>{};

  ReliableSessionController({
    required RelayClient relay,
    required SessionManager sessions,
    required bool Function() isDisposed,
    required bool Function() isRelayEnabled,
    required Future<void> Function(String peerId) flushPendingMessages,
    required Future<void> Function(String peerId) flushPendingSecureInbound,
    required ReliableSessionSendControlEnvelope sendControlEnvelope,
    required void Function(String message) log,
  }) : _relay = relay,
       _sessions = sessions,
       _isDisposed = isDisposed,
       _isRelayEnabled = isRelayEnabled,
       _flushPendingMessages = flushPendingMessages,
       _flushPendingSecureInbound = flushPendingSecureInbound,
       _sendControlEnvelope = sendControlEnvelope,
       _log = log;

  bool hasSession(String peerId) => _sessions.hasSession(peerId);

  bool markHandshakeInFlight(String peerId) => _handshakeInFlight.add(peerId);

  void clearHandshakeInFlight(String peerId) {
    _handshakeInFlight.remove(peerId);
  }

  Future<void> handleHandshakeInit(String fromPeerId, Uint8List payload) async {
    final response = await _sessions.receiveHandshake(fromPeerId, payload);

    await _sendControlEnvelope(
      peerId: fromPeerId,
      type: ReliableEnvelopeType.handshakeResponse,
      payload: response,
    );

    await _flushPendingMessages(fromPeerId);
    await _flushPendingSecureInbound(fromPeerId);
  }

  Future<void> handleHandshakeResponse(
    String fromPeerId,
    Uint8List payload,
  ) async {
    await _sessions.completeHandshake(fromPeerId, payload);
    _handshakeInFlight.remove(fromPeerId);
    cancelHandshakeRetry(fromPeerId);
    await _flushPendingMessages(fromPeerId);
    await _flushPendingSecureInbound(fromPeerId);
  }

  Future<void> sendHandshakeInit(String peerId) async {
    final handshakePayload = await _sessions.initiateHandshake(peerId);
    await _sendControlEnvelope(
      peerId: peerId,
      type: ReliableEnvelopeType.handshakeInit,
      payload: handshakePayload,
    );
    scheduleHandshakeRetry(peerId);
  }

  void scheduleHandshakeRetry(String peerId) {
    if (_isDisposed()) {
      return;
    }
    cancelHandshakeRetry(peerId);
    _handshakeAttempts[peerId] = (_handshakeAttempts[peerId] ?? 0) + 1;
    if (_handshakeAttempts[peerId]! > 5) {
      _handshakeInFlight.remove(peerId);
      return;
    }
    _handshakeTimers[peerId] = Timer(const Duration(seconds: 4), () async {
      if (_isDisposed()) {
        return;
      }
      if (_sessions.hasSession(peerId)) {
        cancelHandshakeRetry(peerId);
        return;
      }
      await sendHandshakeInit(peerId);
    });
  }

  void cancelHandshakeRetry(String peerId) {
    _handshakeTimers.remove(peerId)?.cancel();
    _handshakeAttempts.remove(peerId);
  }

  Future<bool> ensureSessionForPeer(String peerId) async {
    if (await _sessions.ensureSession(peerId)) {
      return true;
    }
    if (!_isRelayEnabled()) {
      return false;
    }
    try {
      final bundle = await _relay.fetchBlob(_prekeyBundleId(peerId));
      if (bundle.isNotFound) {
        _log('prekey:fetch missing peer=$peerId');
        return false;
      }
      final payload = jsonDecode(utf8.decode(bundle.payload));
      if (payload is! Map<String, dynamic>) {
        _log('prekey:fetch invalid payload peer=$peerId');
        return false;
      }
      final bundlePeerId = payload['peerId'] as String?;
      final timestampMs = payload['timestampMs'] as int?;
      final signingRaw = payload['signingPublicKey'] as String?;
      final agreementRaw = payload['agreementPublicKey'] as String?;
      final signatureRaw = payload['signature'] as String?;
      if (bundlePeerId == null ||
          timestampMs == null ||
          signingRaw == null ||
          agreementRaw == null ||
          signatureRaw == null ||
          bundlePeerId != peerId) {
        _log('prekey:fetch invalid fields peer=$peerId');
        return false;
      }
      final signingPublicKeyBytes = base64Decode(signingRaw);
      final agreementPublicKeyBytes = base64Decode(agreementRaw);
      final signature = base64Decode(signatureRaw);
      final signingPublicKey = SimplePublicKey(
        signingPublicKeyBytes,
        type: KeyPairType.ed25519,
      );
      final agreementPublicKey = SimplePublicKey(
        agreementPublicKeyBytes,
        type: KeyPairType.x25519,
      );
      final signaturePayload = _buildPrekeyBundleSignaturePayload(
        peerId: bundlePeerId,
        timestampMs: timestampMs,
        signingPublicKey: Uint8List.fromList(signingPublicKeyBytes),
        agreementPublicKey: Uint8List.fromList(agreementPublicKeyBytes),
      );
      final verified = await _sessions.signatures.verify(
        signaturePayload,
        signature,
        signingPublicKey,
      );
      if (!verified) {
        _log('prekey:fetch signature mismatch peer=$peerId');
        return false;
      }
      await _sessions.trustPeerIdentity(
        peerId: peerId,
        signingPublicKey: signingPublicKey,
        agreementPublicKey: agreementPublicKey,
      );
      final established = await _sessions.establishOfflineSession(peerId);
      _log('prekey:fetch peer=$peerId established=$established');
      return established;
    } catch (error) {
      _log('prekey:fetch error peer=$peerId error=$error');
      return false;
    }
  }

  Future<void> dispose() async {
    for (final timer in _handshakeTimers.values.toList(growable: false)) {
      timer.cancel();
    }
    _handshakeTimers.clear();
    _handshakeInFlight.clear();
  }

  String _prekeyBundleId(String peerId) => 'prekey:$peerId';

  Uint8List _buildPrekeyBundleSignaturePayload({
    required String peerId,
    required int timestampMs,
    required Uint8List signingPublicKey,
    required Uint8List agreementPublicKey,
  }) {
    final header =
        '$peerId|$timestampMs|${base64Encode(signingPublicKey)}|${base64Encode(agreementPublicKey)}';
    return Uint8List.fromList(utf8.encode(header));
  }
}
