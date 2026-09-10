// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'dart:typed_data';

import 'reliable_codec.dart';
import 'reliable_inbound_processor.dart';
import 'reliable_operation_id.dart';
import 'reliable_pending_operation_store.dart';
import 'reliable_relay_poll_controller.dart';
import 'reliable_retry_scheduler.dart';
import 'reliable_session_controller.dart';
import '../overlay/message_cache.dart';
import '../relay/relay_client.dart';
import '../relay/relay_models.dart';
import '../relay/peer_relay_directory.dart';
import '../runtime/storage_service.dart';
import '../security/session_manager.dart';

/// Envelope надежного уровня, доставляемый в chat-сервис.
class ReliableMessageEnvelope {
  final String id;
  final String fromPeerId;
  final String? groupId;
  final int timestampMs;
  final Map<String, dynamic> payload;

  ReliableMessageEnvelope({
    required this.id,
    required this.fromPeerId,
    this.groupId,
    required this.timestampMs,
    required this.payload,
  });
}

typedef ReliableIncomingHandler =
    FutureOr<bool> Function(ReliableMessageEnvelope envelope);

enum MessagingTargetKind { direct, group }

enum RelayBlobScopeKind { direct, group }

enum _SendAttemptResult { sent, deferred }

class ReliableSendReceipt {
  final bool sent;
  final List<String> relayServers;

  const ReliableSendReceipt({required this.sent, required this.relayServers});

  static const empty = ReliableSendReceipt(
    sent: false,
    relayServers: <String>[],
  );
}

class _SendAttempt {
  final _SendAttemptResult result;
  final ReliableSendReceipt receipt;

  const _SendAttempt._({required this.result, required this.receipt});

  factory _SendAttempt.sent(ReliableSendReceipt receipt) {
    return _SendAttempt._(result: _SendAttemptResult.sent, receipt: receipt);
  }

  factory _SendAttempt.deferred() {
    return const _SendAttempt._(
      result: _SendAttemptResult.deferred,
      receipt: ReliableSendReceipt.empty,
    );
  }
}

class ReliableMessagingService {
  static const Duration _activePollInterval = Duration(seconds: 2);
  static const Duration _idlePollInterval = Duration(seconds: 5);
  static const Duration _prekeyPublishTtl = Duration(days: 30);
  static const String _pendingOperationsStateKey =
      'reliable.pending_operations.v1';

  final RelayClient _relay;
  final PeerRelayDirectory? _peerRelayDirectory;
  final SessionManager _sessions;
  final String _selfId;
  final Duration _maxFutureClockSkew;
  final bool _encryptionEnabled;
  final SecureStorageBox? _stateBox;

  final MessageCache _replayCache = MessageCache();
  final Map<String, List<Map<String, dynamic>>> _pendingMessages = {};
  late final ReliableInboundProcessor _inboundProcessor;
  late final ReliablePendingOperationStore _pendingOperationStore;
  late final ReliableRelayPollController _relayPollController;
  late final ReliableRetryScheduler _pendingOperationRetryScheduler;
  late final ReliableSessionController _sessionController;
  int _logSeq = 0;
  bool _messageRelayEnabled = false;
  bool _disposed = false;
  Future<void>? _prekeyPublishInFlight;

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
  bool Function()? _inboundReadyProvider;

  void setIncomingHandler(ReliableIncomingHandler? handler) {
    _incomingHandler = handler;
  }

  void setInboundReadyProvider(bool Function()? provider) {
    _inboundReadyProvider = provider;
  }

  Future<Uint8List> encryptForPeer(String peerId, Uint8List plainBytes) async {
    if (!_encryptionEnabled) {
      return plainBytes;
    }
    if (!await _sessionController.ensureSessionForPeer(peerId)) {
      throw Exception('Session not established');
    }
    return _sessions.encrypt(peerId, plainBytes);
  }

  Future<Uint8List> decryptFromPeer(
    String peerId,
    Uint8List encryptedBytes,
  ) async {
    if (!_encryptionEnabled) {
      return encryptedBytes;
    }
    if (!await _sessionController.ensureSessionForPeer(peerId)) {
      throw Exception('Session not established');
    }
    return _sessions.decrypt(peerId, encryptedBytes);
  }

  void configureRelayServers(List<String> servers) {
    _relay.configureServers(servers);
    _messageRelayEnabled = servers.isNotEmpty;
    if (_messageRelayEnabled) {
      _relayPollController.resetBackoff();
      unawaited(_publishPrekeyBundle());
      if (!_pendingOperationStore.isEmpty) {
        _pendingOperationRetryScheduler.schedule();
      }
    } else {
      _relayPollController.stop();
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
    SecureStorageBox? stateBox,
    PeerRelayDirectory? peerRelayDirectory,
  }) : _maxFutureClockSkew = maxClockSkew,
       _encryptionEnabled = enableEncryption,
       _stateBox = stateBox,
       _peerRelayDirectory = peerRelayDirectory {
    _sessionController = ReliableSessionController(
      relay: _relay,
      sessions: _sessions,
      isDisposed: () => _disposed,
      isRelayEnabled: () => _messageRelayEnabled,
      flushPendingMessages: _flushPending,
      flushPendingSecureInbound: _flushPendingSecureInbound,
      sendControlEnvelope:
          ({
            required String peerId,
            required ReliableEnvelopeType type,
            required Uint8List payload,
          }) {
            return _sendControlEnvelope(
              peerId: peerId,
              type: type,
              payload: payload,
            );
          },
      log: _log,
    );
    _inboundProcessor = ReliableInboundProcessor(
      replayCache: _replayCache,
      maxFutureClockSkew: _maxFutureClockSkew,
      handleHandshakeInit: _sessionController.handleHandshakeInit,
      handleHandshakeResponse: _sessionController.handleHandshakeResponse,
      ensureSessionForPeer: _sessionController.ensureSessionForPeer,
      hasSession: _sessionController.hasSession,
      sendHandshakeInit: _sessionController.sendHandshakeInit,
      markHandshakeInFlight: _sessionController.markHandshakeInFlight,
      clearHandshakeInFlight: _sessionController.clearHandshakeInFlight,
      decrypt: _sessions.decrypt,
      handlePeerIdentityBundle: (peerId, bundle) {
        return _sessions.trustPeerIdentityBundleV3(
          bundle,
          expectedPeerId: peerId,
        );
      },
      deliverIncomingEnvelope: _deliverIncomingEnvelope,
      log: _log,
    );
    _pendingOperationStore = ReliablePendingOperationStore(
      stateBox: _stateBox,
      stateKey: _pendingOperationsStateKey,
      log: _log,
    );
    _relayPollController = ReliableRelayPollController(
      relay: _relay,
      sessions: _sessions,
      selfId: _selfId,
      activePollInterval: _activePollInterval,
      idlePollInterval: _idlePollInterval,
      isDisposed: () => _disposed,
      isRelayEnabled: () => _messageRelayEnabled,
      isInboundReady: () => _inboundReadyProvider?.call() ?? true,
      buildSignaturePayload: buildReliableSignaturePayload,
      buildAckSignaturePayload: buildReliableAckSignaturePayload,
      handleReliableEnvelope: _handleReliableEnvelope,
      log: _log,
    );
    _pendingOperationRetryScheduler = ReliableRetryScheduler(
      isDisposed: () => _disposed,
      isRelayEnabled: () => _messageRelayEnabled,
      hasPendingOperations: () => !_pendingOperationStore.isEmpty,
      pendingOperations: _pendingOperationStore.snapshot,
      removeOperation: _pendingOperationStore.remove,
      persistOperations: _pendingOperationStore.persist,
      retryOperation: _retryPendingOperation,
      onError: (operation, error) {
        _log(
          'pending:retry failed op=${operation.kind.name} '
          'id=${operation.operationId} error=$error',
        );
      },
      onGiveUp: _handlePendingOperationGiveUp,
      log: _log,
    );
  }

  Future<void> initialize() async {
    await _pendingOperationStore.restore();
    if (_messageRelayEnabled) {
      unawaited(_publishPrekeyBundle());
    }
    if (!_pendingOperationStore.isEmpty) {
      _pendingOperationRetryScheduler.schedule();
    }
  }

  /// Унифицированная отправка payload:
  /// - `direct` использует session-based reliable messaging;
  /// - `group` использует relay group envelope с fanout по `recipients`.
  Future<ReliableSendReceipt> sendPayload(
    String targetId,
    Map<String, dynamic> payload, {
    MessagingTargetKind targetKind = MessagingTargetKind.direct,
    List<String>? recipients,
    String? messageId,
    bool forcePlain = false,
    bool persistIfNeeded = true,
  }) async {
    final operationId = ReliableOperationId.pendingMessage(
      isGroup: targetKind == MessagingTargetKind.group,
      targetId: targetId,
      messageId: messageId,
    );
    if (persistIfNeeded) {
      await _pendingOperationStore.upsert(
        ReliablePendingOperation.directOrGroupPayload(
          operationId: operationId,
          targetId: targetId,
          payload: payload,
          operationKind: targetKind == MessagingTargetKind.group
              ? ReliablePendingOperationKind.groupPayload
              : ReliablePendingOperationKind.directPayload,
          recipients: recipients,
          messageId: messageId,
          forcePlain: forcePlain,
        ),
      );
      _pendingOperationRetryScheduler.schedule();
    }

    try {
      if (targetKind == MessagingTargetKind.group) {
        final normalizedRecipients =
            (recipients ?? const <String>[])
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList(growable: false)
              ..sort();
        final attempt = await _sendGroupPayload(
          targetId,
          normalizedRecipients,
          payload,
          messageId: messageId,
        );
        if (attempt.result == _SendAttemptResult.sent) {
          await _pendingOperationStore.remove(operationId);
          return attempt.receipt;
        } else {
          _sendStatusController.add(
            ReliableSendStatus(
              peerId: targetId,
              messageId: messageId ?? operationId,
              status: ReliableSendState.undelivered,
            ),
          );
          _pendingOperationRetryScheduler.schedule();
          return ReliableSendReceipt.empty;
        }
      }
      final attempt = await _sendDirectPayload(
        targetId,
        payload,
        messageId: messageId,
        forcePlain: forcePlain,
        queuePendingOnMissingSession: persistIfNeeded,
      );
      if (attempt.result == _SendAttemptResult.sent) {
        await _pendingOperationStore.remove(operationId);
        return attempt.receipt;
      } else {
        _sendStatusController.add(
          ReliableSendStatus(
            peerId: targetId,
            messageId: messageId ?? operationId,
            status: ReliableSendState.undelivered,
          ),
        );
        _pendingOperationRetryScheduler.schedule();
        return ReliableSendReceipt.empty;
      }
    } on RelayUnavailableException catch (error) {
      _log('send deferred target=$targetId reason=$error');
      _sendStatusController.add(
        ReliableSendStatus(
          peerId: targetId,
          messageId: messageId ?? operationId,
          status: ReliableSendState.undelivered,
        ),
      );
      _pendingOperationRetryScheduler.schedule();
      return ReliableSendReceipt.empty;
    } catch (_) {
      _sendStatusController.add(
        ReliableSendStatus(
          peerId: targetId,
          messageId: messageId ?? operationId,
          status: ReliableSendState.undelivered,
        ),
      );
      _pendingOperationRetryScheduler.schedule();
      rethrow;
    }
  }

  Future<void> discardPendingPayload({
    required MessagingTargetKind targetKind,
    required String targetId,
    required String messageId,
  }) async {
    final normalizedMessageId = messageId.trim();
    if (normalizedMessageId.isEmpty) {
      return;
    }
    final operationId = ReliableOperationId.pendingMessage(
      isGroup: targetKind == MessagingTargetKind.group,
      targetId: targetId,
      messageId: normalizedMessageId,
    );
    await _pendingOperationStore.remove(operationId);
  }

  Future<_SendAttempt> _sendDirectPayload(
    String peerId,
    Map<String, dynamic> payload, {
    String? messageId,
    bool forcePlain = false,
    bool queuePendingOnMissingSession = true,
  }) async {
    _log(
      'send target=peer:$peerId encryption=${_encryptionEnabled ? "on" : "off"} relayEnabled=$_messageRelayEnabled',
    );

    if (!_messageRelayEnabled) {
      _log('send failed target=peer:$peerId reason=relay not configured');
      return _SendAttempt.deferred();
    }
    _relayPollController.resetBackoff();

    if (!_encryptionEnabled || forcePlain) {
      final plainPayload = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      final receipt = await _sendControlEnvelope(
        peerId: peerId,
        type: ReliableEnvelopeType.plainMessage,
        payload: plainPayload,
        id: messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      );
      return _SendAttempt.sent(receipt);
    }

    if (!await _sessionController.ensureSessionForPeer(peerId)) {
      if (queuePendingOnMissingSession) {
        _pendingMessages
            .putIfAbsent(peerId, () => [])
            .add(Map<String, dynamic>.from(payload));
      }

      if (_sessionController.markHandshakeInFlight(peerId)) {
        try {
          await _sessionController.sendHandshakeInit(peerId);
        } catch (_) {
          _sessionController.clearHandshakeInFlight(peerId);
          rethrow;
        }
      }

      return _SendAttempt.deferred();
    }

    final plainPayload = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    final encrypted = await _sessions.encrypt(peerId, plainPayload);

    final receipt = await _sendControlEnvelope(
      peerId: peerId,
      type: ReliableEnvelopeType.secureMessage,
      payload: encrypted,
      id: messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
    );
    return _SendAttempt.sent(receipt);
  }

  Future<_SendAttempt> _sendGroupPayload(
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
      return _SendAttempt.deferred();
    }
    _relayPollController.resetBackoff();

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
      "type": ReliableEnvelopeType.plainMessage.name,
      "ts": timestampMs,
      "payload": base64Encode(plainPayload),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    final signaturePayload = buildReliableGroupSignaturePayload(
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

    final receipt = await _relay.storeGroup(relayEnvelope);
    final sendReceipt = ReliableSendReceipt(
      sent: true,
      relayServers: receipt.serverUrls,
    );
    _log(
      'group-store ok group=$groupId message=$envelopeId '
      'recipients=${normalizedRecipients.length} relayServers=${receipt.serverUrls.length}',
    );
    return _SendAttempt.sent(sendReceipt);
  }

  Future<void> updateGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
    int ttlSeconds = 86400,
  }) async {
    if (!_messageRelayEnabled) {
      _log('updateGroupMembers failed: message relay is not configured');
      throw RelayUnavailableException(
        details: 'no message relay server configured',
      );
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
    await _pendingOperationStore.upsert(
      ReliablePendingOperation.groupMembers(
        operationId: envelopeId,
        groupId: groupId,
        ownerPeerId: ownerPeerId,
        memberPeerIds: normalizedMembers,
        ttlSeconds: ttlSeconds,
      ),
    );
    _pendingOperationRetryScheduler.schedule();
    try {
      await _sendGroupMembersUpdate(
        operationId: envelopeId,
        groupId: groupId,
        ownerPeerId: ownerPeerId,
        memberPeerIds: normalizedMembers,
        ttlSeconds: ttlSeconds,
      );
    } on RelayUnavailableException catch (error) {
      _log('updateGroupMembers deferred groupId=$groupId reason=$error');
      _pendingOperationRetryScheduler.schedule();
      return;
    } catch (error) {
      if (_isTerminalGroupMembersOwnerMismatch(error)) {
        await _pendingOperationStore.remove(envelopeId);
        _log(
          'updateGroupMembers terminal groupId=$groupId reason=owner-mismatch',
        );
        return;
      }
      rethrow;
    }
  }

  Future<void> _sendGroupMembersUpdate({
    required String operationId,
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
    required int ttlSeconds,
  }) async {
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = buildReliableGroupMembersSignaturePayload(
      id: operationId,
      from: _selfId,
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
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
      id: operationId,
      from: _selfId,
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
      timestampMs: timestampMs,
      ttlSeconds: ttlSeconds,
      signature: signature,
      senderSigningPublicKey: signingPub,
    );
    await _relay.updateGroupMembers(envelope);
    await _pendingOperationStore.remove(operationId);
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
  }) async => (await storeBlobWithReceipt(
    scopeKind: scopeKind,
    targetId: targetId,
    fileName: fileName,
    mimeType: mimeType,
    bytes: bytes,
    blobId: blobId,
    onProgress: onProgress,
  )).blobId;

  Future<RelayBlobStoreReceipt> storeBlobWithReceipt({
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
      throw RelayUnavailableException(
        details: 'no message relay server configured',
      );
    }

    final scopeId = switch (scopeKind) {
      RelayBlobScopeKind.group => targetId,
      RelayBlobScopeKind.direct => buildDirectBlobScopeId(_selfId, targetId),
    };
    final envelopeId =
        blobId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final signaturePayload = buildReliableBlobSignaturePayload(
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
    return _relay.storeBlobWithReceipt(envelope, onProgress: onProgress);
  }

  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    List<String>? relayServers,
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    if (!_messageRelayEnabled) {
      _log('blob fetch failed blobId=$blobId reason=relay not configured');
      throw RelayUnavailableException(
        details: 'no message relay server configured',
      );
    }
    return _relay.fetchBlob(
      blobId,
      relayServers: relayServers,
      onProgress: onProgress,
    );
  }

  Future<void> _publishPrekeyBundle() {
    final current = _prekeyPublishInFlight;
    if (current != null) {
      return current;
    }
    final future = _doPublishPrekeyBundle();
    _prekeyPublishInFlight = future;
    future.whenComplete(() {
      if (identical(_prekeyPublishInFlight, future)) {
        _prekeyPublishInFlight = null;
      }
    });
    return future;
  }

  Future<void> _doPublishPrekeyBundle() async {
    if (_disposed || !_messageRelayEnabled) {
      return;
    }
    final timestampMs = DateTime.now().millisecondsSinceEpoch;
    final signingPublicKey = Uint8List.fromList(
      _sessions.identity.signingPublicKey.bytes,
    );
    final agreementPublicKey = Uint8List.fromList(
      _sessions.identity.agreementPublicKey.bytes,
    );
    final prekeySignaturePayload = buildReliablePrekeyBundleSignaturePayload(
      peerId: _selfId,
      timestampMs: timestampMs,
      signingPublicKey: signingPublicKey,
      agreementPublicKey: agreementPublicKey,
    );
    final prekeySignature = await _sessions.signatures.sign(
      prekeySignaturePayload,
      _sessions.identity.signingKeyPair,
    );
    final bundle = <String, dynamic>{
      'peerId': _selfId,
      'timestampMs': timestampMs,
      'signingPublicKey': base64Encode(signingPublicKey),
      'agreementPublicKey': base64Encode(agreementPublicKey),
      'signature': base64Encode(prekeySignature),
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(bundle)));
    final blobId = _prekeyBundleId(_selfId);
    final scopeId = 'prekey:$_selfId';
    final ttlSeconds = _prekeyPublishTtl.inSeconds;
    final signaturePayload = buildReliableBlobSignaturePayload(
      id: blobId,
      from: _selfId,
      groupId: scopeId,
      fileName: 'prekey.json',
      mimeType: 'application/vnd.peerlink.prekey+json',
      timestampMs: timestampMs,
      ttlSeconds: ttlSeconds,
      payload: bytes,
    );
    final blobSignature = await _sessions.signatures.sign(
      signaturePayload,
      _sessions.identity.signingKeyPair,
    );
    final envelope = RelayBlobUploadEnvelope(
      id: blobId,
      from: _selfId,
      groupId: scopeId,
      fileName: 'prekey.json',
      mimeType: 'application/vnd.peerlink.prekey+json',
      timestampMs: timestampMs,
      ttlSeconds: ttlSeconds,
      payload: bytes,
      signature: blobSignature,
      senderSigningPublicKey: signingPublicKey,
    );
    try {
      await _relay.storeBlob(envelope);
      _log('prekey:publish ok peer=$_selfId ttlSeconds=$ttlSeconds');
    } catch (error) {
      _log('prekey:publish failed peer=$_selfId error=$error');
    }
  }

  String _prekeyBundleId(String peerId) => 'prekey:$peerId';

  /// Отправляет direct control/data envelope (handshake/plain/secure) через relay.
  Future<ReliableSendReceipt> _sendControlEnvelope({
    required String peerId,
    required ReliableEnvelopeType type,
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
      "senderIdentityBundleV3": _sessions.identity.identityBundleV3Json,
    };

    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    final signaturePayload = buildReliableSignaturePayload(
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

    final receipt = await _relay.store(
      relayEnvelope,
      preferredServers:
          _peerRelayDirectory?.freshRelayServersFor(peerId) ?? const <String>[],
    );
    final sendReceipt = ReliableSendReceipt(
      sent: true,
      relayServers: receipt.serverUrls,
    );
    _sendStatusController.add(
      ReliableSendStatus(
        peerId: peerId,
        messageId: envelopeId,
        status: ReliableSendState.sent,
      ),
    );
    return sendReceipt;
  }

  Future<int> pollRelay({List<String>? relayServers}) async {
    return _relayPollController.poll(relayServers: relayServers);
  }

  Future<bool> _handleReliableEnvelope({
    required String envelopeId,
    required String fromPeerId,
    String? groupId,
    required int timestampMs,
    required Uint8List bytes,
  }) async {
    return _inboundProcessor.handleReliableEnvelope(
      envelopeId: envelopeId,
      fromPeerId: fromPeerId,
      groupId: groupId,
      timestampMs: timestampMs,
      bytes: bytes,
    );
  }

  Future<void> _flushPendingSecureInbound(String peerId) async {
    await _inboundProcessor.flushPendingSecureInbound(peerId);
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
    if (!await _sessionController.ensureSessionForPeer(peerId)) {
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

  Future<bool> _retryPendingOperation(
    ReliablePendingOperation operation,
  ) async {
    switch (operation.kind) {
      case ReliablePendingOperationKind.directPayload:
      case ReliablePendingOperationKind.groupPayload:
        try {
          await sendPayload(
            operation.targetId!,
            operation.payload!,
            targetKind:
                operation.kind == ReliablePendingOperationKind.groupPayload
                ? MessagingTargetKind.group
                : MessagingTargetKind.direct,
            recipients: operation.recipients,
            messageId: operation.messageId,
            forcePlain: operation.forcePlain,
            persistIfNeeded: false,
          );
        } catch (_) {
          return false;
        }
        return !_pendingOperationStore.contains(operation.operationId);
      case ReliablePendingOperationKind.groupMembers:
        try {
          await _sendGroupMembersUpdate(
            operationId: operation.operationId,
            groupId: operation.groupId!,
            ownerPeerId: operation.ownerPeerId!,
            memberPeerIds: operation.memberPeerIds!,
            ttlSeconds: operation.ttlSeconds ?? 86400,
          );
          return true;
        } catch (error) {
          if (_isTerminalGroupMembersOwnerMismatch(error)) {
            _log(
              'pending:retry terminal ${operation.diagnosticsSummary()} '
              'reason=owner-mismatch',
            );
            return true;
          }
          rethrow;
        }
    }
  }

  bool _isTerminalGroupMembersOwnerMismatch(Object error) {
    final message = error.toString();
    return message.contains('group-members-update') &&
        message.contains('owner mismatch');
  }

  void _handlePendingOperationGiveUp(ReliablePendingOperation operation) {
    switch (operation.kind) {
      case ReliablePendingOperationKind.directPayload:
      case ReliablePendingOperationKind.groupPayload:
        final targetId = operation.targetId;
        final messageId = operation.messageId;
        if (targetId == null || messageId == null) {
          return;
        }
        if (operation.kind == ReliablePendingOperationKind.directPayload) {
          _pendingMessages.remove(targetId);
          _sessionController.stopHandshakeRetry(
            targetId,
            reason: 'pending-giveup',
          );
        }
        _sendStatusController.add(
          ReliableSendStatus(
            peerId: targetId,
            messageId: messageId,
            status: ReliableSendState.undelivered,
          ),
        );
      case ReliablePendingOperationKind.groupMembers:
        return;
    }
  }

  /// Освобождает ресурсы и подписки надежного messaging-слоя.
  Future<void> dispose() async {
    _disposed = true;
    await _sessionController.dispose();
    await _incomingController.close();
    await _errorController.close();
    await _sendStatusController.close();
    _pendingOperationRetryScheduler.cancel();
    _relayPollController.stop();
  }

  void _log(String message) {
    final shouldForceFileLog =
        message.startsWith('pending:') ||
        message.startsWith('prekey:') ||
        message.startsWith('group-store') ||
        message.startsWith('send deferred') ||
        message.startsWith('send failed') ||
        message.startsWith('updateGroupMembers deferred') ||
        message.startsWith('updateGroupMembers failed');
    AppFileLogger.log(
      '[reliable][$_selfId][${_logSeq++}] $message',
      name: 'reliable',
      level: shouldForceFileLog ? 900 : 0,
    );
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
