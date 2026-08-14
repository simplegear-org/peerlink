// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

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
  final Map<String, int> _prekeyMissingUntilMs = <String, int>{};
  final Map<String, Future<bool>> _prekeyFetchInFlight =
      <String, Future<bool>>{};
  static const int _maxHandshakeAttempts = 3;
  static const Duration _prekeyMissingCooldown = Duration(seconds: 30);

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
    final attempt = (_handshakeAttempts[peerId] ?? 0) + 1;
    if (attempt > _maxHandshakeAttempts) {
      stopHandshakeRetry(peerId, reason: 'max-attempts-before-send');
      return;
    }
    _handshakeAttempts[peerId] = attempt;
    final handshakePayload = await _sessions.initiateHandshake(peerId);
    await _sendControlEnvelope(
      peerId: peerId,
      type: ReliableEnvelopeType.handshakeInit,
      payload: handshakePayload,
    );
    _log(
      'handshake:sent peer=$peerId attempt=$attempt '
      'max=$_maxHandshakeAttempts',
    );
    if (attempt >= _maxHandshakeAttempts) {
      stopHandshakeRetry(peerId, reason: 'max-attempts');
      return;
    }
    _scheduleHandshakeRetry(peerId);
  }

  void _scheduleHandshakeRetry(String peerId) {
    if (_isDisposed()) {
      return;
    }
    _handshakeTimers.remove(peerId)?.cancel();
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

  void stopHandshakeRetry(String peerId, {String reason = 'stopped'}) {
    _handshakeTimers.remove(peerId)?.cancel();
    _handshakeInFlight.remove(peerId);
    _log('handshake:giveup reason=$reason peer=$peerId');
  }

  Future<bool> ensureSessionForPeer(String peerId) async {
    if (await _sessions.ensureSession(peerId)) {
      return true;
    }
    if (!_isRelayEnabled()) {
      return false;
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final missingUntilMs = _prekeyMissingUntilMs[peerId] ?? 0;
    if (missingUntilMs > nowMs) {
      return false;
    }
    final inFlight = _prekeyFetchInFlight[peerId];
    if (inFlight != null) {
      return inFlight;
    }
    final fetch = _fetchAndEstablishPrekeySession(peerId);
    _prekeyFetchInFlight[peerId] = fetch;
    try {
      return await fetch;
    } finally {
      _prekeyFetchInFlight.remove(peerId);
    }
  }

  Future<bool> _fetchAndEstablishPrekeySession(String peerId) async {
    try {
      final bundle = await _relay.fetchBlob(_prekeyBundleId(peerId));
      if (bundle.isNotFound) {
        _log('prekey:fetch missing peer=$peerId');
        _prekeyMissingUntilMs[peerId] =
            DateTime.now().millisecondsSinceEpoch +
            _prekeyMissingCooldown.inMilliseconds;
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
      final signaturePayload = buildReliablePrekeyBundleSignaturePayload(
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
      if (established) {
        _prekeyMissingUntilMs.remove(peerId);
      }
      return established;
    } catch (error) {
      _log('prekey:fetch error peer=$peerId error=$error');
      _prekeyMissingUntilMs[peerId] =
          DateTime.now().millisecondsSinceEpoch +
          _prekeyMissingCooldown.inMilliseconds;
      return false;
    }
  }

  Future<void> dispose() async {
    for (final timer in _handshakeTimers.values.toList(growable: false)) {
      timer.cancel();
    }
    _handshakeTimers.clear();
    _handshakeInFlight.clear();
    _handshakeAttempts.clear();
    _prekeyMissingUntilMs.clear();
    _prekeyFetchInFlight.clear();
  }

  String _prekeyBundleId(String peerId) => 'prekey:$peerId';
}
