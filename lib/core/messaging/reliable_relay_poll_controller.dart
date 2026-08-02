import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../relay/relay_client.dart';
import '../relay/relay_models.dart';
import '../security/session_manager.dart';

typedef ReliableRelaySignaturePayloadBuilder =
    Uint8List Function({
      required String envelopeId,
      required String from,
      required String to,
      required int timestampMs,
      required int ttlSeconds,
      required Uint8List payload,
    });

typedef ReliableRelayAckPayloadBuilder =
    Uint8List Function({
      required String id,
      required String from,
      required String to,
      required int timestampMs,
    });

typedef ReliableRelayEnvelopeHandler =
    Future<bool> Function({
      required String envelopeId,
      required String fromPeerId,
      String? groupId,
      required int timestampMs,
      required Uint8List bytes,
    });

class ReliableRelayPollController {
  final RelayClient _relay;
  final SessionManager _sessions;
  final String _selfId;
  final Duration _activePollInterval;
  final Duration _idlePollInterval;
  final bool Function() _isDisposed;
  final bool Function() _isRelayEnabled;
  final bool Function() _isInboundReady;
  final ReliableRelaySignaturePayloadBuilder _buildSignaturePayload;
  final ReliableRelayAckPayloadBuilder _buildAckSignaturePayload;
  final ReliableRelayEnvelopeHandler _handleReliableEnvelope;
  final void Function(String message) _log;

  Timer? _pollTimer;
  String? _fetchCursor;
  int _emptyPollStreak = 0;
  bool _pollInFlight = false;
  bool _hasDeferredReplayPending = false;

  ReliableRelayPollController({
    required RelayClient relay,
    required SessionManager sessions,
    required String selfId,
    required Duration activePollInterval,
    required Duration idlePollInterval,
    required bool Function() isDisposed,
    required bool Function() isRelayEnabled,
    required bool Function() isInboundReady,
    required ReliableRelaySignaturePayloadBuilder buildSignaturePayload,
    required ReliableRelayAckPayloadBuilder buildAckSignaturePayload,
    required ReliableRelayEnvelopeHandler handleReliableEnvelope,
    required void Function(String message) log,
  }) : _relay = relay,
       _sessions = sessions,
       _selfId = selfId,
       _activePollInterval = activePollInterval,
       _idlePollInterval = idlePollInterval,
       _isDisposed = isDisposed,
       _isRelayEnabled = isRelayEnabled,
       _isInboundReady = isInboundReady,
       _buildSignaturePayload = buildSignaturePayload,
       _buildAckSignaturePayload = buildAckSignaturePayload,
       _handleReliableEnvelope = handleReliableEnvelope,
       _log = log;

  Future<void> poll({List<String>? relayServers}) async {
    if (_isDisposed()) {
      return;
    }
    if (!_isRelayEnabled()) {
      _log('messageRelay:poll skip reason=not enabled');
      return;
    }
    if (!_isInboundReady()) {
      _log('messageRelay:poll skip reason=inbound-not-ready');
      return;
    }
    if (_pollInFlight) {
      _log('messageRelay:poll skip reason=in-flight');
      return;
    }

    final normalizedRelayServers =
        (relayServers ?? const <String>[])
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();

    _pollInFlight = true;
    final shouldLogEmptyPoll =
        _emptyPollStreak == 0 || _emptyPollStreak % 10 == 0;
    try {
      if (shouldLogEmptyPoll) {
        _log(
          'messageRelay:poll start selfId=$_selfId cursor=$_fetchCursor '
          'emptyStreak=$_emptyPollStreak relayHint=${normalizedRelayServers.length}',
        );
      }
      final result = normalizedRelayServers.isEmpty
          ? await _relay.fetch(
              _selfId,
              cursor: _fetchCursor,
              limit: 50,
            )
          : await _relay.fetchFromServers(
              _selfId,
              servers: normalizedRelayServers,
              cursor: _fetchCursor,
              limit: 50,
            );

      final hasMessages = result.messages.isNotEmpty;
      if (result.allServersUnavailable) {
        _log('messageRelay:poll unavailable selfId=$_selfId');
      }
      if (hasMessages || shouldLogEmptyPoll) {
        _log(
          'messageRelay:poll received messages=${result.messages.length} cursor=${result.cursor}',
        );
      }

      int processedCount = 0;
      var allMessagesAcked = true;
      for (final envelope in result.messages) {
        _log(
          'messageRelay:poll processing envelope id=${envelope.id} from=${envelope.from} to=${envelope.to}',
        );
        final acked = await _handleRelayEnvelope(envelope);
        if (!acked) {
          allMessagesAcked = false;
        }
        processedCount++;
      }

      if (allMessagesAcked) {
        if (_hasDeferredReplayPending && !hasMessages) {
          _log(
            'messageRelay:poll cursor retained previous=$_fetchCursor '
            'emptyCursor=${result.cursor} reason=deferred-replay-pending',
          );
        } else {
          _fetchCursor = result.cursor;
          _hasDeferredReplayPending = false;
        }
      } else {
        _hasDeferredReplayPending = true;
        _log(
          'messageRelay:poll cursor retained previous=$_fetchCursor deferredCursor=${result.cursor}',
        );
      }

      if (result.allServersUnavailable) {
        _retunePollTimer();
        return;
      }
      if (hasMessages) {
        _emptyPollStreak = 0;
      } else {
        _emptyPollStreak += 1;
      }
      if (hasMessages || shouldLogEmptyPoll) {
        _log(
          'messageRelay:poll complete processed=$processedCount emptyStreak=$_emptyPollStreak',
        );
      }
      _retunePollTimer();
    } catch (error, stack) {
      _log('messageRelay:poll error=$error stack=$stack');
    } finally {
      _pollInFlight = false;
    }
  }

  void resetBackoff() {
    _emptyPollStreak = 0;
    if (_isDisposed()) {
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_activePollInterval, (_) => unawaited(poll()));
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _emptyPollStreak = 0;
  }

  Future<bool> _handleRelayEnvelope(RelayEnvelope envelope) async {
    final signaturePayload = _buildSignaturePayload(
      envelopeId: envelope.id,
      from: envelope.from,
      to: envelope.to,
      timestampMs: envelope.timestampMs,
      ttlSeconds: envelope.ttlSeconds,
      payload: envelope.payload,
    );

    final senderSigningKey = SimplePublicKey(
      envelope.senderSigningPublicKey,
      type: KeyPairType.ed25519,
    );

    final verified = await _sessions.signatures.verify(
      signaturePayload,
      envelope.signature,
      senderSigningKey,
    );

    if (!verified) {
      if ((envelope.groupId ?? '').isNotEmpty) {
        _log(
          'messageRelay:group envelope signature mismatch id=${envelope.id} group=${envelope.groupId} '
          'accepting because group signature format differs from p2p envelope format',
        );
      } else {
        _log('messageRelay:drop invalid signature id=${envelope.id}');
        return false;
      }
    }

    final shouldAck = await _handleReliableEnvelope(
      envelopeId: envelope.id,
      fromPeerId: envelope.from,
      groupId: envelope.groupId,
      timestampMs: envelope.timestampMs,
      bytes: envelope.payload,
    );

    if (!shouldAck) {
      _log('messageRelay:ack deferred id=${envelope.id}');
      return false;
    }

    final ackTimestamp = DateTime.now().millisecondsSinceEpoch;
    final ackPayload = _buildAckSignaturePayload(
      id: envelope.id,
      from: _selfId,
      to: _selfId,
      timestampMs: ackTimestamp,
    );
    final ackSig = await _sessions.signatures.sign(
      ackPayload,
      _sessions.identity.signingKeyPair,
    );
    final ackSigningPub = Uint8List.fromList(
      _sessions.identity.signingPublicKey.bytes,
    );
    await _relay.ack(
      RelayAck(
        id: envelope.id,
        from: _selfId,
        to: _selfId,
        timestampMs: ackTimestamp,
        signature: ackSig,
        senderSigningPublicKey: ackSigningPub,
      ),
    );
    return true;
  }

  void _retunePollTimer() {
    if (_isDisposed()) {
      return;
    }
    final nextInterval = _emptyPollStreak >= 5
        ? _idlePollInterval
        : _activePollInterval;
    final currentTimer = _pollTimer;
    if (currentTimer == null || !currentTimer.isActive) {
      _pollTimer = Timer.periodic(nextInterval, (_) => unawaited(poll()));
      return;
    }
    final shouldBeIdle = nextInterval == _idlePollInterval;
    final shouldRetune =
        shouldBeIdle == (_emptyPollStreak == 5) ||
        (!shouldBeIdle && _emptyPollStreak == 0);
    if (!shouldRetune) {
      return;
    }
    currentTimer.cancel();
    _pollTimer = Timer.periodic(nextInterval, (_) => unawaited(poll()));
  }
}
