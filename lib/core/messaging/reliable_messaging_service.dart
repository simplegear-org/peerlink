import 'dart:async';
import 'dart:convert';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../overlay/message_cache.dart';
import '../relay/relay_client.dart';
import '../relay/relay_models.dart';
import '../security/session_manager.dart';

/// Envelope надежного уровня, доставляемый в chat-сервис.
class ReliableMessageEnvelope {
  final String id;
  final String fromPeerId;
  final int timestampMs;
  final Map<String, dynamic> payload;

  ReliableMessageEnvelope({
    required this.id,
    required this.fromPeerId,
    required this.timestampMs,
    required this.payload,
  });
}

typedef ReliableIncomingHandler =
    FutureOr<bool> Function(ReliableMessageEnvelope envelope);

enum MessagingTargetKind { direct, group }

enum RelayBlobScopeKind { direct, group }

enum _EnvelopeType {
  plainMessage,
  secureMessage,
  handshakeInit,
  handshakeResponse,
}

enum _ReplayDecision { deliver, acknowledgeDuplicate, defer }

class ReliableMessagingService {
  static const Duration _activePollInterval = Duration(seconds: 2);
  static const Duration _idlePollInterval = Duration(seconds: 5);

  final RelayClient _relay;
  final SessionManager _sessions;
  final String _selfId;
  final Duration _maxFutureClockSkew;
  final bool _encryptionEnabled;

  final MessageCache _replayCache = MessageCache();
  final Map<String, List<Map<String, dynamic>>> _pendingMessages = {};
  final Map<String, List<_PendingSecureInbound>> _pendingSecureInbound = {};
  final Map<String, List<_OutboxItem>> _outbox = {};
  Timer? _outboxTimer;
  final Set<String> _handshakeInFlight = {};
  final Map<String, int> _handshakeAttempts = {};
  final Map<String, Timer> _handshakeTimers = {};
  Timer? _pollTimer;
  String? _fetchCursor;
  int _logSeq = 0;
  int _emptyPollStreak = 0;
  bool _messageRelayEnabled = false;
  bool _pollInFlight = false;
  bool _disposed = false;

  final _incomingController =
      StreamController<ReliableMessageEnvelope>.broadcast();
  final _errorController = StreamController<Object>.broadcast();
  final _sendStatusController =
      StreamController<ReliableSendStatus>.broadcast();

  Stream<ReliableMessageEnvelope> get onMessage => _incomingController.stream;
  Stream<Object> get onError => _errorController.stream;
  Stream<ReliableSendStatus> get onSendStatus => _sendStatusController.stream;
  String get selfId => _selfId;
  ReliableIncomingHandler? _incomingHandler;

  void setIncomingHandler(ReliableIncomingHandler? handler) {
    _incomingHandler = handler;
  }

  void configureRelayServers(List<String> servers) {
    _relay.configureServers(servers);
    _messageRelayEnabled = servers.isNotEmpty;
    if (_messageRelayEnabled) {
      _resetPollBackoff();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _emptyPollStreak = 0;
    }
    _log(
      'relay configured enabled=$_messageRelayEnabled servers=${servers.length}',
    );
  }

  /// Подготавливает надежный messaging-пайплайн поверх relay transport.
  ReliableMessagingService(
    this._relay,
    this._sessions,
    this._selfId, {
    Duration maxClockSkew = const Duration(minutes: 2),
    bool enableEncryption = true,
  }) : _maxFutureClockSkew = maxClockSkew,
       _encryptionEnabled = enableEncryption;

  /// Унифицированная отправка payload:
  /// - `direct` использует session-based reliable messaging;
  /// - `group` использует relay group envelope с fanout по `recipients`.
  Future<void> sendPayload(
    String targetId,
    Map<String, dynamic> payload, {
    MessagingTargetKind targetKind = MessagingTargetKind.direct,
    List<String>? recipients,
    String? messageId,
    bool forcePlain = false,
  }) async {
    if (targetKind == MessagingTargetKind.group) {
      final normalizedRecipients =
          (recipients ?? const <String>[])
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList(growable: false)
            ..sort();
      return _sendGroupPayload(
        targetId,
        normalizedRecipients,
        payload,
        messageId: messageId,
      );
    }
    return _sendDirectPayload(
      targetId,
      payload,
      messageId: messageId,
      forcePlain: forcePlain,
    );
  }

  Future<void> _sendDirectPayload(
    String peerId,
    Map<String, dynamic> payload, {
    String? messageId,
    bool forcePlain = false,
  }) async {
    _log(
      'send target=peer:$peerId encryption=${_encryptionEnabled ? "on" : "off"} relayEnabled=$_messageRelayEnabled',
    );

    if (!_messageRelayEnabled) {
      _log('send failed target=peer:$peerId reason=relay not configured');
      throw StateError('No message relay server configured');
    }
    _resetPollBackoff();

    if (!_encryptionEnabled || forcePlain) {
      final plainPayload = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      await _sendControlEnvelope(
        peerId: peerId,
        type: _EnvelopeType.plainMessage,
        payload: plainPayload,
        id: messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      );
      return;
    }

    if (!await _ensureSessionForPeer(peerId)) {
      _pendingMessages
          .putIfAbsent(peerId, () => [])
          .add(Map<String, dynamic>.from(payload));

      if (_handshakeInFlight.add(peerId)) {
        try {
          await _sendHandshakeInit(peerId);
        } catch (_) {
          _handshakeInFlight.remove(peerId);
          rethrow;
        }
      }

      return;
    }

    final plainPayload = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final encrypted = await _sessions.encrypt(peerId, plainPayload);

    await _sendControlEnvelope(
      peerId: peerId,
      type: _EnvelopeType.secureMessage,
      payload: encrypted,
      id: messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    );
  }

  Future<void> _sendGroupPayload(
    String groupId,
    List<String> recipients,
    Map<String, dynamic> payload, {
    String? messageId,
  }) async {
    _log(
      'send target=group:$groupId encryption=group-key relayEnabled=$_messageRelayEnabled recipients=${recipients.length}',
    );
    if (!_messageRelayEnabled) {
      _log('send failed target=group:$groupId reason=relay not configured');
      throw StateError('No message relay server configured');
    }
    _resetPollBackoff();

    final envelopeId =
        messageId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final normalizedRecipients =
        recipients
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (normalizedRecipients.isEmpty) {
      throw ArgumentError('recipients must not be empty');
    }

    final plainPayload = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final envelope = {
      "id": envelopeId,
      "type": _EnvelopeType.plainMessage.name,
      "ts": timestampMs,
      "payload": base64Encode(plainPayload),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    final signaturePayload = _buildGroupSignaturePayload(
      envelopeId: envelopeId,
      from: _selfId,
      groupId: groupId,
      recipients: normalizedRecipients,
      timestampMs: timestampMs,
      ttlSeconds: 86400,
      payload: bytes,
    );
    final signature = await _sessions.signatures.sign(
      signaturePayload,
      _sessions.identity.signingKeyPair,
    );
    final signingPub = Uint8List.fromList(
      _sessions.identity.signingPublicKey.bytes,
    );

    final relayEnvelope = RelayGroupEnvelope(
      id: envelopeId,
      from: _selfId,
      groupId: groupId,
      recipientIds: normalizedRecipients,
      timestampMs: timestampMs,
      ttlSeconds: 86400,
      payload: bytes,
      signature: signature,
      senderSigningPublicKey: signingPub,
    );

    await _relay.storeGroup(relayEnvelope);
  }

  Future<void> updateGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
    int ttlSeconds = 86400,
  }) async {
    if (!_messageRelayEnabled) {
      _log('updateGroupMembers failed: message relay is not configured');
      throw StateError('No message relay server configured');
    }
    final normalizedMembers =
        memberPeerIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (normalizedMembers.isEmpty) {
      throw ArgumentError('memberPeerIds must not be empty');
    }

    final envelopeId =
        'members:$groupId:${DateTime.now().microsecondsSinceEpoch}';
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = _buildGroupMembersSignaturePayload(
      id: envelopeId,
      from: _selfId,
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: normalizedMembers,
      timestampMs: timestampMs,
      ttlSeconds: ttlSeconds,
    );
    final signature = await _sessions.signatures.sign(
      signaturePayload,
      _sessions.identity.signingKeyPair,
    );
    final signingPub = Uint8List.fromList(
      _sessions.identity.signingPublicKey.bytes,
    );
    final envelope = RelayGroupMembersUpdateEnvelope(
      id: envelopeId,
      from: _selfId,
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: normalizedMembers,
      timestampMs: timestampMs,
      ttlSeconds: ttlSeconds,
      signature: signature,
      senderSigningPublicKey: signingPub,
    );
    await _relay.updateGroupMembers(envelope);
  }

  Future<String> storeBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) async {
    if (!_messageRelayEnabled) {
      _log(
        'blob store failed scope=$scopeKind target=$targetId reason=relay not configured',
      );
      throw StateError('No message relay server configured');
    }

    final scopeId = switch (scopeKind) {
      RelayBlobScopeKind.group => targetId,
      RelayBlobScopeKind.direct => _buildDirectBlobScopeId(_selfId, targetId),
    };
    final envelopeId =
        blobId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = _buildBlobSignaturePayload(
      id: envelopeId,
      from: _selfId,
      groupId: scopeId,
      fileName: fileName,
      mimeType: mimeType,
      timestampMs: timestampMs,
      ttlSeconds: 86400,
      payload: bytes,
    );
    final signature = await _sessions.signatures.sign(
      signaturePayload,
      _sessions.identity.signingKeyPair,
    );
    final signingPub = Uint8List.fromList(
      _sessions.identity.signingPublicKey.bytes,
    );

    final envelope = RelayBlobUploadEnvelope(
      id: envelopeId,
      from: _selfId,
      groupId: scopeId,
      fileName: fileName,
      mimeType: mimeType,
      timestampMs: timestampMs,
      ttlSeconds: 86400,
      payload: bytes,
      signature: signature,
      senderSigningPublicKey: signingPub,
    );
    await _relay.storeBlob(envelope, onProgress: onProgress);
    return envelopeId;
  }

  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    if (!_messageRelayEnabled) {
      _log('blob fetch failed blobId=$blobId reason=relay not configured');
      throw StateError('No message relay server configured');
    }
    return _relay.fetchBlob(blobId, onProgress: onProgress);
  }

  /// Отправляет direct control/data envelope (handshake/plain/secure) через relay.
  Future<void> _sendControlEnvelope({
    required String peerId,
    required _EnvelopeType type,
    required Uint8List payload,
    String? id,
  }) async {
    final envelopeId = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    _log('send:envelope type=${type.name} to=$peerId id=$envelopeId');
    final envelope = {
      "id": envelopeId,
      "type": type.name,
      "ts": timestampMs,
      "payload": base64Encode(payload),
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    final signaturePayload = _buildSignaturePayload(
      envelopeId: envelopeId,
      from: _selfId,
      to: peerId,
      timestampMs: timestampMs,
      ttlSeconds: 86400,
      payload: bytes,
    );
    final signature = await _sessions.signatures.sign(
      signaturePayload,
      _sessions.identity.signingKeyPair,
    );
    final signingPub = Uint8List.fromList(
      _sessions.identity.signingPublicKey.bytes,
    );
    final relayEnvelope = RelayEnvelope(
      id: envelopeId,
      from: _selfId,
      to: peerId,
      timestampMs: timestampMs,
      ttlSeconds: 86400,
      payload: bytes,
      signature: signature,
      senderSigningPublicKey: signingPub,
    );

    try {
      await _relay.store(relayEnvelope);
      _sendStatusController.add(
        ReliableSendStatus(
          peerId: peerId,
          messageId: envelopeId,
          status: ReliableSendState.sent,
        ),
      );
    } catch (e) {
      _enqueueOutbox(
        _OutboxItem(
          peerId: peerId,
          id: envelopeId,
          relayEnvelope: relayEnvelope,
        ),
      );
      _sendStatusController.add(
        ReliableSendStatus(
          peerId: peerId,
          messageId: envelopeId,
          status: ReliableSendState.undelivered,
        ),
      );
      _log(
        'send:envelope queued for retry type=${type.name} to=$peerId id=$envelopeId error=$e',
      );
      return;
    }
  }

  Future<void> pollRelay() async {
    await _pollRelay();
  }

  Future<void> _pollRelay() async {
    if (_disposed) {
      return;
    }
    if (!_messageRelayEnabled) {
      _log('messageRelay:poll skip reason=not enabled');
      return;
    }
    if (_pollInFlight) {
      _log('messageRelay:poll skip reason=in-flight');
      return;
    }

    _pollInFlight = true;
    final shouldLogEmptyPoll =
        _emptyPollStreak == 0 || _emptyPollStreak % 10 == 0;
    try {
      if (shouldLogEmptyPoll) {
        _log(
          'messageRelay:poll start selfId=$_selfId cursor=$_fetchCursor emptyStreak=$_emptyPollStreak',
        );
      }
      final result = await _relay.fetch(
        _selfId,
        cursor: _fetchCursor,
        limit: 50,
      );

      final hasMessages = result.messages.isNotEmpty;
      if (hasMessages || shouldLogEmptyPoll) {
        _log(
          'messageRelay:poll received messages=${result.messages.length} cursor=${result.cursor}',
        );
      }
      _fetchCursor = result.cursor;

      int processedCount = 0;
      for (final envelope in result.messages) {
        _log(
          'messageRelay:poll processing envelope id=${envelope.id} from=${envelope.from} to=${envelope.to}',
        );
        await _handleRelayEnvelope(envelope);
        processedCount++;
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
    } catch (e, stack) {
      _log('messageRelay:poll error=$e stack=$stack');
    } finally {
      _pollInFlight = false;
    }
  }

  void _retunePollTimer() {
    if (_disposed) {
      return;
    }
    final nextInterval = _emptyPollStreak >= 5
        ? _idlePollInterval
        : _activePollInterval;
    final currentTimer = _pollTimer;
    if (currentTimer == null || !currentTimer.isActive) {
      _pollTimer = Timer.periodic(nextInterval, (_) => _pollRelay());
      return;
    }
    final targetInterval = _emptyPollStreak >= 5
        ? _idlePollInterval
        : _activePollInterval;
    final shouldBeIdle = targetInterval == _idlePollInterval;
    final shouldRetune =
        shouldBeIdle == (_emptyPollStreak == 5) ||
        (!shouldBeIdle && _emptyPollStreak == 0);
    if (!shouldRetune) {
      return;
    }
    currentTimer.cancel();
    _pollTimer = Timer.periodic(targetInterval, (_) => _pollRelay());
  }

  void _resetPollBackoff() {
    _emptyPollStreak = 0;
    if (_disposed) {
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_activePollInterval, (_) => _pollRelay());
  }

  Future<void> _handleRelayEnvelope(RelayEnvelope envelope) async {
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
        return;
      }
    }

    final shouldAck = await _handleReliableEnvelope(
      envelopeId: envelope.id,
      fromPeerId: envelope.from,
      timestampMs: envelope.timestampMs,
      bytes: envelope.payload,
    );

    if (!shouldAck) {
      _log('messageRelay:ack deferred id=${envelope.id}');
      return;
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
  }

  Future<bool> _handleReliableEnvelope({
    required String envelopeId,
    required String fromPeerId,
    required int timestampMs,
    required Uint8List bytes,
  }) async {
    final decoded = jsonDecode(utf8.decode(bytes));

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Reliable envelope must be a JSON object');
    }

    final id = decoded["id"];
    final typeRaw = decoded["type"];
    final ts = decoded["ts"];
    final payloadBase64 = decoded["payload"];

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
      case _EnvelopeType.plainMessage:
        final replayDecision = _validateReplayWindow(id, ts);
        if (replayDecision == _ReplayDecision.acknowledgeDuplicate) {
          return true;
        }
        if (replayDecision == _ReplayDecision.defer) {
          return false;
        }
        return _handlePlainMessage(
          id: id,
          fromPeerId: fromPeerId,
          timestampMs: ts,
          plainPayload: payloadBytes,
        );
      case _EnvelopeType.handshakeInit:
        await _handleHandshakeInit(fromPeerId, payloadBytes);
        return true;
      case _EnvelopeType.handshakeResponse:
        await _sessions.completeHandshake(fromPeerId, payloadBytes);
        _handshakeInFlight.remove(fromPeerId);
        _cancelHandshakeRetry(fromPeerId);
        await _flushPending(fromPeerId);
        await _flushPendingSecureInbound(fromPeerId);
        return true;
      case _EnvelopeType.secureMessage:
        final replayDecision = _validateReplayWindow(id, ts);
        if (replayDecision == _ReplayDecision.acknowledgeDuplicate) {
          return true;
        }
        if (replayDecision == _ReplayDecision.defer) {
          return false;
        }
        return _handleSecureMessage(
          id: id,
          fromPeerId: fromPeerId,
          timestampMs: ts,
          encryptedPayload: payloadBytes,
        );
    }
  }

  /// Преобразует строковый тип envelope в enum.
  _EnvelopeType _parseType(String rawType) {
    return _EnvelopeType.values.firstWhere(
      (value) => value.name == rawType,
      orElse: () {
        throw FormatException('Unknown reliable envelope type: $rawType');
      },
    );
  }

  /// Обрабатывает входящий handshake init и отправляет handshake response.
  Future<void> _handleHandshakeInit(
    String fromPeerId,
    Uint8List payload,
  ) async {
    final response = await _sessions.receiveHandshake(fromPeerId, payload);

    await _sendControlEnvelope(
      peerId: fromPeerId,
      type: _EnvelopeType.handshakeResponse,
      payload: response,
    );

    await _flushPending(fromPeerId);
    await _flushPendingSecureInbound(fromPeerId);
  }

  Future<void> _sendHandshakeInit(String peerId) async {
    final handshakePayload = await _sessions.initiateHandshake(peerId);
    await _sendControlEnvelope(
      peerId: peerId,
      type: _EnvelopeType.handshakeInit,
      payload: handshakePayload,
    );
    _scheduleHandshakeRetry(peerId);
  }

  void _scheduleHandshakeRetry(String peerId) {
    if (_disposed) {
      return;
    }
    _cancelHandshakeRetry(peerId);
    _handshakeAttempts[peerId] = (_handshakeAttempts[peerId] ?? 0) + 1;
    if (_handshakeAttempts[peerId]! > 5) {
      _handshakeInFlight.remove(peerId);
      return;
    }
    _handshakeTimers[peerId] = Timer(const Duration(seconds: 4), () async {
      if (_disposed) {
        return;
      }
      if (_sessions.hasSession(peerId)) {
        _cancelHandshakeRetry(peerId);
        return;
      }
      await _sendHandshakeInit(peerId);
    });
  }

  void _cancelHandshakeRetry(String peerId) {
    _handshakeTimers.remove(peerId)?.cancel();
    _handshakeAttempts.remove(peerId);
  }

  /// Расшифровывает secure payload и публикует его во входящий поток.
  Future<bool> _handleSecureMessage({
    required String id,
    required String fromPeerId,
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
      if (_handshakeInFlight.add(fromPeerId)) {
        try {
          await _sendHandshakeInit(fromPeerId);
        } catch (e) {
          _handshakeInFlight.remove(fromPeerId);
          _log('recv:secure handshake init failed peer=$fromPeerId error=$e');
        }
      }
      return false;
    }

    final decrypted = await _sessions.decrypt(fromPeerId, encryptedPayload);
    final decodedPayload = jsonDecode(utf8.decode(decrypted));

    if (decodedPayload is! Map<String, dynamic>) {
      throw const FormatException(
        'Secure message payload must be a JSON object',
      );
    }

    final envelope = ReliableMessageEnvelope(
      id: id,
      fromPeerId: fromPeerId,
      timestampMs: timestampMs,
      payload: decodedPayload,
    );

    final delivered = await _deliverIncomingEnvelope(envelope);
    if (delivered) {
      _replayCache.store(id);
    }
    return delivered;
  }

  Future<void> _flushPendingSecureInbound(String peerId) async {
    if (!_sessions.hasSession(peerId)) {
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
      } catch (e) {
        _log('recv:secure pending drop id=${item.id} peer=$peerId error=$e');
      }
    }
  }

  Future<bool> _handlePlainMessage({
    required String id,
    required String fromPeerId,
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
      timestampMs: timestampMs,
      payload: decodedPayload,
    );

    final delivered = await _deliverIncomingEnvelope(envelope);
    if (delivered) {
      _replayCache.store(id);
    }
    return delivered;
  }

  /// Проверяет окно времени и защиту от replay по id сообщения.
  _ReplayDecision _validateReplayWindow(String id, int timestampMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final futureDelta = timestampMs - now;

    if (futureDelta > _maxFutureClockSkew.inMilliseconds) {
      _log('recv:drop timestamp too far in future id=$id deltaMs=$futureDelta');
      return _ReplayDecision.defer;
    }

    if (_replayCache.contains(id)) {
      _log('recv:drop replay detected id=$id');
      return _ReplayDecision.acknowledgeDuplicate;
    }

    return _ReplayDecision.deliver;
  }

  Future<bool> _deliverIncomingEnvelope(
    ReliableMessageEnvelope envelope,
  ) async {
    _incomingController.add(envelope);
    final handler = _incomingHandler;
    if (handler == null) {
      return true;
    }

    try {
      return await handler(envelope);
    } catch (error, stack) {
      _log(
        'recv:delivery handler failed id=${envelope.id} '
        'peer=${envelope.fromPeerId} error=$error stack=$stack',
      );
      return false;
    }
  }

  /// Отправляет накопленные сообщения после успешного установления сессии.
  Future<void> _flushPending(String peerId) async {
    if (!await _ensureSessionForPeer(peerId)) {
      return;
    }

    final queue = _pendingMessages.remove(peerId);
    if (queue == null || queue.isEmpty) {
      return;
    }

    for (final pendingPayload in queue) {
      await sendPayload(peerId, pendingPayload);
    }
  }

  void _enqueueOutbox(_OutboxItem item) {
    if (_disposed) {
      return;
    }
    final queue = _outbox.putIfAbsent(item.peerId, () => <_OutboxItem>[]);
    final existingIndex = queue.indexWhere((entry) => entry.id == item.id);
    if (existingIndex != -1) {
      queue[existingIndex] = item;
    } else {
      queue.add(item);
    }
    _scheduleOutboxRetry();
  }

  void _scheduleOutboxRetry() {
    if (_disposed) {
      return;
    }
    _outboxTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      await _retryOutbox();
      if (_outbox.values.every((queue) => queue.isEmpty)) {
        _outboxTimer?.cancel();
        _outboxTimer = null;
      }
    });
  }

  Future<void> _retryOutbox() async {
    if (_disposed) {
      return;
    }
    if (!_messageRelayEnabled) {
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final entries = List<MapEntry<String, List<_OutboxItem>>>.from(
      _outbox.entries,
    );
    for (final entry in entries) {
      final peerId = entry.key;
      final queue = _outbox[peerId];
      if (queue == null) continue;
      if (queue.isEmpty) continue;

      for (final item in List<_OutboxItem>.from(queue)) {
        if (item.nextAttemptMs > nowMs) continue;
        try {
          await _relay.store(item.relayEnvelope);
          queue.remove(item);
          _sendStatusController.add(
            ReliableSendStatus(
              peerId: peerId,
              messageId: item.id,
              status: ReliableSendState.sent,
            ),
          );
        } catch (e) {
          item.registerFailure();
          _log('outbox:retry failed peer=$peerId id=${item.id} error=$e');
        }
      }
      if (queue.isEmpty) {
        _outbox.remove(peerId);
      }
    }
  }

  /// Освобождает ресурсы и подписки надежного messaging-слоя.
  Future<void> dispose() async {
    _disposed = true;
    for (final timer in _handshakeTimers.values.toList(growable: false)) {
      timer.cancel();
    }
    _handshakeTimers.clear();
    _handshakeInFlight.clear();
    await _incomingController.close();
    await _errorController.close();
    await _sendStatusController.close();
    _outboxTimer?.cancel();
    _pollTimer?.cancel();
  }

  void _log(String message) {
    AppFileLogger.log('[reliable][$_selfId][${_logSeq++}] $message');
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

  Future<bool> _ensureSessionForPeer(String peerId) async {
    if (await _sessions.ensureSession(peerId)) {
      return true;
    }
    if (!_messageRelayEnabled) {
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
    } catch (e) {
      _log('prekey:fetch error peer=$peerId error=$e');
      return false;
    }
  }
}

enum ReliableSendState { sent, undelivered }

class ReliableSendStatus {
  final String peerId;
  final String messageId;
  final ReliableSendState status;

  ReliableSendStatus({
    required this.peerId,
    required this.messageId,
    required this.status,
  });
}

class _OutboxItem {
  final String peerId;
  final String id;
  final RelayEnvelope relayEnvelope;
  int attempts = 0;
  int nextAttemptMs = 0;

  _OutboxItem({
    required this.peerId,
    required this.id,
    required this.relayEnvelope,
  }) {
    registerFailure();
  }

  void registerFailure() {
    attempts += 1;
    final backoffSeconds = attempts < 6 ? 2 << (attempts - 1) : 60;
    final delayMs = backoffSeconds * 1000;
    nextAttemptMs = DateTime.now().millisecondsSinceEpoch + delayMs;
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

Uint8List _buildSignaturePayload({
  required String envelopeId,
  required String from,
  required String to,
  required int timestampMs,
  required int ttlSeconds,
  required Uint8List payload,
}) {
  final header = '$envelopeId|$from|$to|$timestampMs|$ttlSeconds|';
  final headerBytes = utf8.encode(header);
  final bytes = Uint8List(headerBytes.length + payload.length);
  bytes.setRange(0, headerBytes.length, headerBytes);
  bytes.setRange(headerBytes.length, bytes.length, payload);
  return bytes;
}

Uint8List _buildAckSignaturePayload({
  required String id,
  required String from,
  required String to,
  required int timestampMs,
}) {
  final header = '$id|$from|$to|$timestampMs';
  return Uint8List.fromList(utf8.encode(header));
}

String _buildDirectBlobScopeId(String selfId, String peerId) {
  final peers = <String>[selfId.trim(), peerId.trim()]..sort();
  return 'dm:${peers.join('|')}';
}

Uint8List _buildGroupSignaturePayload({
  required String envelopeId,
  required String from,
  required String groupId,
  required List<String> recipients,
  required int timestampMs,
  required int ttlSeconds,
  required Uint8List payload,
}) {
  final recipientsPart = recipients.join(',');
  final header =
      '$envelopeId|$from|$groupId|$recipientsPart|$timestampMs|$ttlSeconds|';
  final headerBytes = utf8.encode(header);
  final bytes = Uint8List(headerBytes.length + payload.length);
  bytes.setRange(0, headerBytes.length, headerBytes);
  bytes.setRange(headerBytes.length, bytes.length, payload);
  return bytes;
}

Uint8List _buildBlobSignaturePayload({
  required String id,
  required String from,
  required String groupId,
  required String fileName,
  required String? mimeType,
  required int timestampMs,
  required int ttlSeconds,
  required Uint8List payload,
}) {
  final normalizedMime = (mimeType ?? '').trim();
  final header =
      '$id|$from|$groupId|$fileName|$normalizedMime|$timestampMs|$ttlSeconds|';
  final headerBytes = utf8.encode(header);
  final bytes = Uint8List(headerBytes.length + payload.length);
  bytes.setRange(0, headerBytes.length, headerBytes);
  bytes.setRange(headerBytes.length, bytes.length, payload);
  return bytes;
}

Uint8List _buildGroupMembersSignaturePayload({
  required String id,
  required String from,
  required String groupId,
  required String ownerPeerId,
  required List<String> memberPeerIds,
  required int timestampMs,
  required int ttlSeconds,
}) {
  final members = List<String>.from(memberPeerIds)..sort();
  final membersPart = members.join(',');
  final header =
      '$id|$from|$groupId|$ownerPeerId|$membersPart|$timestampMs|$ttlSeconds';
  return Uint8List.fromList(utf8.encode(header));
}
