// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

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
  String? _committedFetchCursor;
  int _emptyPollStreak = 0;
  bool _pollInFlight = false;
  bool _hasDeferredReplayPending = false;
  final Map<String, _PendingRelayAck> _pendingAcks =
      <String, _PendingRelayAck>{};

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

  Future<int> poll({List<String>? relayServers}) async {
    if (_isDisposed()) {
      return 0;
    }
    if (!_isRelayEnabled()) {
      _log('messageRelay:poll skip reason=not enabled');
      return 0;
    }
    if (!_isInboundReady()) {
      _log('messageRelay:poll skip reason=inbound-not-ready');
      return 0;
    }
    if (_pollInFlight) {
      _log('messageRelay:poll skip reason=in-flight');
      return 0;
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
      await _retryPendingAcks();
      if (shouldLogEmptyPoll) {
        _log(
          'messageRelay:poll start selfId=$_selfId '
          'committedCursor=$_committedFetchCursor '
          'emptyStreak=$_emptyPollStreak relayHint=${normalizedRelayServers.length}',
        );
      }
      final result = normalizedRelayServers.isEmpty
          ? await _relay.fetch(
              _selfId,
              cursor: _committedFetchCursor,
              limit: 50,
            )
          : await _relay.fetchFromServers(
              _selfId,
              servers: normalizedRelayServers,
              cursor: _committedFetchCursor,
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
      for (final fetchedEnvelope in result.fetchedMessages) {
        final envelope = fetchedEnvelope.envelope;
        _log(
          'messageRelay:poll processing envelope id=${envelope.id} '
          'from=${envelope.from} to=${envelope.to} '
          'group=${envelope.groupId ?? ""} recipients=${envelope.recipients?.length ?? 0}',
        );
        final acked = await _handleRelayEnvelope(fetchedEnvelope);
        if (!acked) {
          allMessagesAcked = false;
        }
        processedCount++;
      }

      final candidateCursor = result.cursor;
      if (allMessagesAcked) {
        if (_hasDeferredReplayPending && !hasMessages) {
          _log(
            'messageRelay:poll cursor retained '
            'committed=$_committedFetchCursor '
            'candidate=$candidateCursor reason=deferred-replay-pending',
          );
        } else {
          _committedFetchCursor = candidateCursor;
          _hasDeferredReplayPending = false;
        }
      } else {
        _hasDeferredReplayPending = true;
        _log(
          'messageRelay:poll cursor retained '
          'committed=$_committedFetchCursor candidate=$candidateCursor',
        );
      }

      if (result.allServersUnavailable) {
        _retunePollTimer();
        return processedCount;
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
      return processedCount;
    } catch (error, stack) {
      _log('messageRelay:poll error=$error stack=$stack');
      return 0;
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

  Future<bool> _handleRelayEnvelope(
    RelayFetchedEnvelope fetchedEnvelope,
  ) async {
    final envelope = fetchedEnvelope.envelope;
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
      _log(
        'messageRelay:ack deferred id=${envelope.id} '
        'group=${envelope.groupId ?? ""}',
      );
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
    final ack = RelayAck(
      id: envelope.id,
      from: _selfId,
      to: _selfId,
      timestampMs: ackTimestamp,
      signature: ackSig,
      senderSigningPublicKey: ackSigningPub,
    );
    try {
      final receipt = await _relay.ack(
        ack,
        relayServers: fetchedEnvelope.relayServers,
      );
      _retainFailedAckReplicas(ack, receipt.failedServerUrls);
      if (receipt.failedServerUrls.isNotEmpty) {
        _log(
          'messageRelay:ack partial id=${envelope.id} '
          'failed=${receipt.failedServerUrls.join(',')}',
        );
      }
    } catch (error, stack) {
      _retainFailedAckReplicas(ack, fetchedEnvelope.relayServers);
      _log(
        'messageRelay:ack deferred id=${envelope.id} error=$error stack=$stack',
      );
    }
    _log(
      'messageRelay:ack ok id=${envelope.id} group=${envelope.groupId ?? ""}',
    );
    return true;
  }

  Future<void> _retryPendingAcks() async {
    if (_pendingAcks.isEmpty) {
      return;
    }
    for (final pending in List<_PendingRelayAck>.from(_pendingAcks.values)) {
      try {
        final receipt = await _relay.ack(
          pending.ack,
          relayServers: pending.relayServers,
        );
        _retainFailedAckReplicas(pending.ack, receipt.failedServerUrls);
      } catch (error, stack) {
        _log(
          'messageRelay:ack retry deferred id=${pending.ack.id} '
          'error=$error stack=$stack',
        );
      }
    }
  }

  void _retainFailedAckReplicas(RelayAck ack, Iterable<String> relayServers) {
    final failedServers =
        relayServers
            .map((server) => server.trim())
            .where((server) => server.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (failedServers.isEmpty) {
      _pendingAcks.remove(ack.id);
      return;
    }
    _pendingAcks[ack.id] = _PendingRelayAck(
      ack: ack,
      relayServers: failedServers,
    );
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

class _PendingRelayAck {
  const _PendingRelayAck({required this.ack, required this.relayServers});

  final RelayAck ack;
  final List<String> relayServers;
}
