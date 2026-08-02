import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../overlay/message_cache.dart';
import 'reliable_messaging_service.dart';

enum ReliableInboundEnvelopeType {
  plainMessage,
  secureMessage,
  handshakeInit,
  handshakeResponse,
}

enum ReliableInboundReplayDecision { deliver, acknowledgeDuplicate, defer }

typedef ReliableEnvelopeDelivery =
    Future<bool> Function(ReliableMessageEnvelope envelope);

class ReliableInboundProcessor {
  final MessageCache _replayCache;
  final Duration _maxFutureClockSkew;
  final Future<void> Function(String fromPeerId, Uint8List payload)
  _handleHandshakeInit;
  final Future<void> Function(String fromPeerId, Uint8List payload)
  _handleHandshakeResponse;
  final Future<bool> Function(String peerId) _ensureSessionForPeer;
  final bool Function(String peerId) _hasSession;
  final Future<void> Function(String peerId) _sendHandshakeInit;
  final bool Function(String peerId) _markHandshakeInFlight;
  final void Function(String peerId) _clearHandshakeInFlight;
  final Future<Uint8List> Function(String peerId, Uint8List encryptedPayload)
  _decrypt;
  final ReliableEnvelopeDelivery _deliverIncomingEnvelope;
  final void Function(String message) _log;
  final Map<String, List<_PendingSecureInbound>> _pendingSecureInbound = {};

  ReliableInboundProcessor({
    required MessageCache replayCache,
    required Duration maxFutureClockSkew,
    required Future<void> Function(String fromPeerId, Uint8List payload)
    handleHandshakeInit,
    required Future<void> Function(String fromPeerId, Uint8List payload)
    handleHandshakeResponse,
    required Future<bool> Function(String peerId) ensureSessionForPeer,
    required bool Function(String peerId) hasSession,
    required Future<void> Function(String peerId) sendHandshakeInit,
    required bool Function(String peerId) markHandshakeInFlight,
    required void Function(String peerId) clearHandshakeInFlight,
    required Future<Uint8List> Function(
      String peerId,
      Uint8List encryptedPayload,
    )
    decrypt,
    required ReliableEnvelopeDelivery deliverIncomingEnvelope,
    required void Function(String message) log,
  }) : _replayCache = replayCache,
       _maxFutureClockSkew = maxFutureClockSkew,
       _handleHandshakeInit = handleHandshakeInit,
       _handleHandshakeResponse = handleHandshakeResponse,
       _ensureSessionForPeer = ensureSessionForPeer,
       _hasSession = hasSession,
       _sendHandshakeInit = sendHandshakeInit,
       _markHandshakeInFlight = markHandshakeInFlight,
       _clearHandshakeInFlight = clearHandshakeInFlight,
       _decrypt = decrypt,
       _deliverIncomingEnvelope = deliverIncomingEnvelope,
       _log = log;

  Future<bool> handleReliableEnvelope({
    required String envelopeId,
    required String fromPeerId,
    String? groupId,
    required int timestampMs,
    required Uint8List bytes,
  }) async {
    final decoded = jsonDecode(utf8.decode(bytes));

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Reliable envelope must be a JSON object');
    }

    final id = decoded['id'];
    final typeRaw = decoded['type'];
    final ts = decoded['ts'];
    final payloadBase64 = decoded['payload'];

    if (id is! String ||
        typeRaw is! String ||
        ts is! int ||
        payloadBase64 is! String) {
      throw const FormatException(
        'Reliable envelope has invalid required fields',
      );
    }

    final type = _parseType(typeRaw);
    _log('recv:envelope type=${type.name} from=$fromPeerId id=$id');
    final payloadBytes = Uint8List.fromList(base64Decode(payloadBase64));

    switch (type) {
      case ReliableInboundEnvelopeType.plainMessage:
        final replayDecision = _validateReplayWindow(id, ts);
        if (replayDecision ==
            ReliableInboundReplayDecision.acknowledgeDuplicate) {
          return true;
        }
        if (replayDecision == ReliableInboundReplayDecision.defer) {
          return false;
        }
        return _handlePlainMessage(
          id: id,
          fromPeerId: fromPeerId,
          groupId: groupId,
          timestampMs: ts,
          plainPayload: payloadBytes,
        );
      case ReliableInboundEnvelopeType.handshakeInit:
        await _handleHandshakeInit(fromPeerId, payloadBytes);
        return true;
      case ReliableInboundEnvelopeType.handshakeResponse:
        await _handleHandshakeResponse(fromPeerId, payloadBytes);
        return true;
      case ReliableInboundEnvelopeType.secureMessage:
        final replayDecision = _validateReplayWindow(id, ts);
        if (replayDecision ==
            ReliableInboundReplayDecision.acknowledgeDuplicate) {
          return true;
        }
        if (replayDecision == ReliableInboundReplayDecision.defer) {
          return false;
        }
        return _handleSecureMessage(
          id: id,
          fromPeerId: fromPeerId,
          groupId: groupId,
          timestampMs: ts,
          encryptedPayload: payloadBytes,
        );
    }
  }

  Future<void> flushPendingSecureInbound(String peerId) async {
    if (!_hasSession(peerId)) {
      return;
    }
    final queue = _pendingSecureInbound.remove(peerId);
    if (queue == null || queue.isEmpty) {
      return;
    }
    _log('recv:secure flush pending peer=$peerId count=${queue.length}');
    for (final item in queue) {
      try {
        await _handleSecureMessage(
          id: item.id,
          fromPeerId: peerId,
          timestampMs: item.timestampMs,
          encryptedPayload: item.encryptedPayload,
        );
      } catch (error) {
        _log(
          'recv:secure pending drop id=${item.id} peer=$peerId error=$error',
        );
      }
    }
  }

  ReliableInboundEnvelopeType _parseType(String rawType) {
    return ReliableInboundEnvelopeType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () {
        throw FormatException('Unknown reliable envelope type: $rawType');
      },
    );
  }

  Future<bool> _handleSecureMessage({
    required String id,
    required String fromPeerId,
    String? groupId,
    required int timestampMs,
    required Uint8List encryptedPayload,
  }) async {
    if (!await _ensureSessionForPeer(fromPeerId)) {
      final queue = _pendingSecureInbound.putIfAbsent(
        fromPeerId,
        () => <_PendingSecureInbound>[],
      );
      if (!queue.any((item) => item.id == id)) {
        queue.add(
          _PendingSecureInbound(
            id: id,
            timestampMs: timestampMs,
            encryptedPayload: Uint8List.fromList(encryptedPayload),
          ),
        );
        if (queue.length > 200) {
          queue.removeAt(0);
          _log('recv:secure pending queue trim peer=$fromPeerId');
        }
      }
      _log(
        'recv:secure queued id=$id peer=$fromPeerId reason=session not established',
      );
      if (_markHandshakeInFlight(fromPeerId)) {
        try {
          await _sendHandshakeInit(fromPeerId);
        } catch (error) {
          _clearHandshakeInFlight(fromPeerId);
          _log(
            'recv:secure handshake init failed peer=$fromPeerId error=$error',
          );
        }
      }
      return false;
    }

    final decrypted = await _decrypt(fromPeerId, encryptedPayload);
    final decodedPayload = jsonDecode(utf8.decode(decrypted));

    if (decodedPayload is! Map<String, dynamic>) {
      throw const FormatException(
        'Secure message payload must be a JSON object',
      );
    }

    final envelope = ReliableMessageEnvelope(
      id: id,
      fromPeerId: fromPeerId,
      groupId: groupId,
      timestampMs: timestampMs,
      payload: decodedPayload,
    );

    final delivered = await _deliverIncomingEnvelope(envelope);
    if (delivered) {
      _replayCache.store(id);
    }
    return delivered;
  }

  Future<bool> _handlePlainMessage({
    required String id,
    required String fromPeerId,
    String? groupId,
    required int timestampMs,
    required Uint8List plainPayload,
  }) async {
    final decodedPayload = jsonDecode(utf8.decode(plainPayload));

    if (decodedPayload is! Map<String, dynamic>) {
      throw const FormatException(
        'Plain message payload must be a JSON object',
      );
    }

    final envelope = ReliableMessageEnvelope(
      id: id,
      fromPeerId: fromPeerId,
      groupId: groupId,
      timestampMs: timestampMs,
      payload: decodedPayload,
    );

    final delivered = await _deliverIncomingEnvelope(envelope);
    if (delivered) {
      _replayCache.store(id);
    }
    return delivered;
  }

  ReliableInboundReplayDecision _validateReplayWindow(
    String id,
    int timestampMs,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final futureDelta = timestampMs - now;

    if (futureDelta > _maxFutureClockSkew.inMilliseconds) {
      _log('recv:drop timestamp too far in future id=$id deltaMs=$futureDelta');
      return ReliableInboundReplayDecision.defer;
    }

    if (_replayCache.contains(id)) {
      _log('recv:drop replay detected id=$id');
      return ReliableInboundReplayDecision.acknowledgeDuplicate;
    }

    return ReliableInboundReplayDecision.deliver;
  }
}

class _PendingSecureInbound {
  final String id;
  final int timestampMs;
  final Uint8List encryptedPayload;

  _PendingSecureInbound({
    required this.id,
    required this.timestampMs,
    required this.encryptedPayload,
  });
}
