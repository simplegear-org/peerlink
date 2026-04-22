import 'dart:async';
import 'dart:convert';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'dart:io';
import 'dart:typed_data';

import 'reliable_messaging_service.dart';
import '../relay/relay_models.dart';
import '../runtime/network_event_bus.dart';
import '../runtime/network_event.dart';

/// Базовая доменная модель входящего/исходящего chat payload,
/// общая для direct и group delivery paths.
class ChatMessage {
  final String id;
  final String peerId;
  final String text;
  final String kind;
  final String? fileName;
  final String? mimeType;
  final String? fileDataBase64;
  final String? transferId;
  final int? totalBytes;
  final String? replyToMessageId;
  final String? replyToSenderPeerId;
  final String? replyToSenderLabel;
  final String? replyToTextPreview;
  final String? replyToKind;
  final int? chunkIndex;
  final int? totalChunks;
  final String? chunkDataBase64;

  ChatMessage({
    required this.id,
    required this.peerId,
    required this.text,
    this.kind = 'text',
    this.fileName,
    this.mimeType,
    this.fileDataBase64,
    this.transferId,
    this.totalBytes,
    this.replyToMessageId,
    this.replyToSenderPeerId,
    this.replyToSenderLabel,
    this.replyToTextPreview,
    this.replyToKind,
    this.chunkIndex,
    this.totalChunks,
    this.chunkDataBase64,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'peerId': peerId,
    'text': text,
    'kind': kind,
    'fileName': fileName,
    'mimeType': mimeType,
    'fileDataBase64': fileDataBase64,
    'transferId': transferId,
    'totalBytes': totalBytes,
    'replyToMessageId': replyToMessageId,
    'replyToSenderPeerId': replyToSenderPeerId,
    'replyToSenderLabel': replyToSenderLabel,
    'replyToTextPreview': replyToTextPreview,
    'replyToKind': replyToKind,
    'chunkIndex': chunkIndex,
    'totalChunks': totalChunks,
    'chunkDataBase64': chunkDataBase64,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String,
      peerId: json['peerId'] as String,
      text: json['text'] as String,
      kind: json['kind'] as String? ?? 'text',
      fileName: json['fileName'] as String?,
      mimeType: json['mimeType'] as String?,
      fileDataBase64: json['fileDataBase64'] as String?,
      transferId: json['transferId'] as String?,
      totalBytes: json['totalBytes'] as int?,
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToSenderPeerId: json['replyToSenderPeerId'] as String?,
      replyToSenderLabel: json['replyToSenderLabel'] as String?,
      replyToTextPreview: json['replyToTextPreview'] as String?,
      replyToKind: json['replyToKind'] as String?,
      chunkIndex: json['chunkIndex'] as int?,
      totalChunks: json['totalChunks'] as int?,
      chunkDataBase64: json['chunkDataBase64'] as String?,
    );
  }
}

enum ChatPayloadTargetKind { direct, group }

class ChatService {
  final ReliableMessagingService _messaging;
  final NetworkEventBus _eventBus;
  late final StreamSubscription<ReliableMessageEnvelope> _messageSubscription;
  late final StreamSubscription<ReliableSendStatus> _sendStatusSubscription;
  int _logSeq = 0;

  /// Подписывает chat-сервис на входящий поток надежного messaging-слоя.
  ChatService(this._messaging, this._eventBus) {
    _messageSubscription = _messaging.onMessage.listen(_handleIncoming);
    _sendStatusSubscription =
        _messaging.onSendStatus.listen(_handleSendStatus);
  }

  /// Унифицированная отправка chat payload:
  /// - `direct` target идет через personal reliable messaging path;
  /// - `group` target идет через relay group path с явными `recipients`.
  Future<void> sendPayload(
    String targetId, {
    ChatPayloadTargetKind targetKind = ChatPayloadTargetKind.direct,
    List<String>? recipients,
    required String text,
    String kind = 'text',
    String? messageId,
    String? fileName,
    String? mimeType,
    String? transferId,
    int? totalBytes,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
    bool forcePlain = false,
    bool emitStatusEvent = true,
  }) async {
    final targetLabel = targetKind == ChatPayloadTargetKind.group ? 'group' : 'peer';
    _log('send target=$targetLabel:$targetId kind=$kind length=${text.length}');
    final message = ChatMessage(
      id: messageId ?? DateTime.now().microsecondsSinceEpoch.toString(),
      peerId: targetId,
      text: text,
      kind: kind,
      fileName: fileName,
      mimeType: mimeType,
      transferId: transferId,
      totalBytes: totalBytes,
      replyToMessageId: replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel,
      replyToTextPreview: replyToTextPreview,
      replyToKind: replyToKind,
    );

    if (emitStatusEvent) {
      _eventBus.emit(
        NetworkEvent(
          type: NetworkEventType.messageStatusChanged,
          payload: ChatMessageStatusUpdate(
            messageId: message.id,
            peerId: targetId,
            status: ChatMessageDeliveryStatus.sending,
          ),
        ),
      );
    }

    try {
      await _messaging.sendPayload(
        targetId,
        message.toJson(),
        targetKind: targetKind == ChatPayloadTargetKind.group
            ? MessagingTargetKind.group
            : MessagingTargetKind.direct,
        recipients: recipients,
        messageId: message.id,
        forcePlain: forcePlain,
      );
    } catch (_) {
      // Ошибка отправки уже попала в outbox; статус обновим через onSendStatus.
    }
  }

  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
    bool forcePlain = false,
  }) async {
    _log('send target=peer:$peerId kind=$kind text=${text.length} control=true');
    try {
      await sendPayload(
        peerId,
        text: text,
        kind: kind,
        forcePlain: forcePlain,
        emitStatusEvent: false,
      );
    } catch (_) {
      // ignore control send failure; no preview update needed
    }
  }

  Future<void> updateGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  }) {
    return _messaging.updateGroupMembers(
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
    );
  }

  Future<String> uploadBlob({
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
    })? onProgress,
  }) {
    return _messaging.storeBlob(
      scopeKind: scopeKind,
      targetId: targetId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      blobId: blobId,
      onProgress: onProgress,
    );
  }

  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  }) {
    return _messaging.fetchBlob(
      blobId,
      onProgress: onProgress,
    );
  }

  Future<void> sendFile(
    String peerId, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int totalBytes,
    String? mimeType,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
    required bool Function() isCancelled,
    required void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })
    onProgress,
  }) async {
    if (fileBytes == null && filePath == null) {
      throw ArgumentError('Either fileBytes or filePath must be provided');
    }

    _log(
      'sendFile peer=$peerId file=$fileName bytes=$totalBytes mode=direct-blob',
    );

    _eventBus.emit(
      NetworkEvent(
        type: NetworkEventType.messageStatusChanged,
        payload: ChatMessageStatusUpdate(
          messageId: messageId,
          peerId: peerId,
          status: ChatMessageDeliveryStatus.sending,
        ),
      ),
    );

    if (isCancelled()) {
      throw _FileTransferCancelledException();
    }

    Uint8List resolvedBytes;
    if (fileBytes != null) {
      resolvedBytes = fileBytes;
    } else {
      resolvedBytes = Uint8List.fromList(await File(filePath!).readAsBytes());
    }

    final blobId = await _messaging.storeBlob(
      scopeKind: RelayBlobScopeKind.direct,
      targetId: peerId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: resolvedBytes,
      blobId: 'blob:$messageId',
      onProgress: onProgress,
    );

    if (isCancelled()) {
      throw _FileTransferCancelledException();
    }

    final payload = <String, dynamic>{
      'type': 'direct_blob_ref',
      'v': 1,
      'peerId': _messaging.selfId,
      'counterpartyPeerId': peerId,
      'messageId': messageId,
      'contentKind': 'media',
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSizeBytes': totalBytes,
      'blobId': blobId,
      'createdAt': DateTime.now().toIso8601String(),
    };

    await sendPayload(
      peerId,
      text: '__peerlink_direct_blob_ref_v1__:${jsonEncode(payload)}',
      messageId: messageId,
      replyToMessageId: replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel,
      replyToTextPreview: replyToTextPreview,
      replyToKind: replyToKind,
    );
  }

  /// Преобразует надежный envelope в ChatMessage и публикует его в event bus.
  void _handleIncoming(ReliableMessageEnvelope envelope) {
    final payload = envelope.payload;
    final sourcePeerId = envelope.fromPeerId;
    final id = payload['id'];
    final text = payload['text'];
    _log('recv target=peer:$sourcePeerId id=$id');

    if (id is! String || text is! String) {
      throw const FormatException('Invalid chat payload fields');
    }

    final message = ChatMessage(
      id: id,
      peerId: sourcePeerId,
      text: text,
      kind: payload['kind'] as String? ?? 'text',
      fileName: payload['fileName'] as String?,
      mimeType: payload['mimeType'] as String?,
      fileDataBase64: payload['fileDataBase64'] as String?,
      transferId: payload['transferId'] as String?,
      totalBytes: payload['totalBytes'] as int?,
      replyToMessageId: payload['replyToMessageId'] as String?,
      replyToSenderPeerId: payload['replyToSenderPeerId'] as String?,
      replyToSenderLabel: payload['replyToSenderLabel'] as String?,
      replyToTextPreview: payload['replyToTextPreview'] as String?,
      replyToKind: payload['replyToKind'] as String?,
      chunkIndex: payload['chunkIndex'] as int?,
      totalChunks: payload['totalChunks'] as int?,
      chunkDataBase64: payload['chunkDataBase64'] as String?,
    );

    _eventBus.emit(
      NetworkEvent(
        type: NetworkEventType.messageReceived,
        payload: message,
      ),
    );
  }

  /// Освобождает подписки chat-сервиса.
  Future<void> dispose() async {
    await _messageSubscription.cancel();
    await _sendStatusSubscription.cancel();
  }

  void _log(String message) {
    AppFileLogger.log('[chat][${_logSeq++}] $message');
  }

  void _handleSendStatus(ReliableSendStatus status) {
    final mapped = switch (status.status) {
      ReliableSendState.sent => ChatMessageDeliveryStatus.sent,
      ReliableSendState.undelivered => ChatMessageDeliveryStatus.undelivered,
    };

    _eventBus.emit(
      NetworkEvent(
        type: NetworkEventType.messageStatusChanged,
        payload: ChatMessageStatusUpdate(
          messageId: status.messageId,
          peerId: status.peerId,
          status: mapped,
        ),
      ),
    );
  }
}

class _FileTransferCancelledException implements Exception {
  @override
  String toString() => 'File transfer cancelled';
}

enum ChatMessageDeliveryStatus { sending, sent, undelivered }

class ChatMessageStatusUpdate {
  final String messageId;
  final String peerId;
  final ChatMessageDeliveryStatus status;

  ChatMessageStatusUpdate({
    required this.messageId,
    required this.peerId,
    required this.status,
  });
}
