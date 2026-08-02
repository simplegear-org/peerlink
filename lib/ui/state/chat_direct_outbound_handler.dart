import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/relay/relay_media_transfer_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_notification_type.dart';

class ChatDirectOutboundHandler {
  const ChatDirectOutboundHandler({
    required NodeFacade facade,
    required RelayMediaTransferService relayMediaTransfer,
    required ChatOutboundCodec outboundCodec,
  }) : _facade = facade,
       _relayMediaTransfer = relayMediaTransfer,
       _outboundCodec = outboundCodec;

  final NodeFacade _facade;
  final RelayMediaTransferService _relayMediaTransfer;
  final ChatOutboundCodec _outboundCodec;

  Future<void> sendMessage(
    String peerId,
    Message message, {
    required Future<void> Function(
      String peerId,
      String messageId,
      MessageStatus status,
    )
    updateMessageStatusById,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
  }) async {
    setStatus(peerId, ChatConnectionStatus.connecting);
    try {
      final receipt = await _facade.sendPayload(
        peerId,
        text: message.text,
        messageId: message.id,
        replyToMessageId: message.replyToMessageId,
        replyToSenderPeerId: message.replyToSenderPeerId,
        replyToSenderLabel: message.replyToSenderLabel,
        replyToTextPreview: message.replyToTextPreview,
        replyToKind: message.replyToKind,
      );
      try {
        await _facade.sendDirectPushEvent(
          directPeerId: peerId,
          messageId: message.id,
          relayServers: receipt.relayServers,
          notificationType: 'text',
          relayScopeKind: 'direct',
          relayMessageId: message.id,
        );
      } catch (error) {
        developer.log(
          'push event send failed direct=$peerId messageId=${message.id} error=$error',
          name: 'chat',
        );
      }
      await updateMessageStatusById(peerId, message.id, MessageStatus.sent);
      setStatus(peerId, ChatConnectionStatus.connected);
    } catch (e) {
      await updateMessageStatusById(peerId, message.id, MessageStatus.failed);
      setStatus(peerId, ChatConnectionStatus.error, error: e.toString());
    }
  }

  Future<void> sendFile(
    String peerId, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
    required String? Function(String chatPeerId, Message? replyTo)
    replySenderLabel,
    required String? Function(Message? replyTo) replyTextPreview,
    required String? Function(Message? replyTo) replyKind,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    updateFileProgress,
    required void Function(String message) logQueue,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required Future<void> Function(OutgoingRelayMediaState state)
    rememberOutgoingRelayMediaState,
    required Future<void> Function(String peerId, String messageId)
    forgetOutgoingRelayMediaState,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required void Function(String peerId, String messageId) clearProgressUpdate,
    required bool Function(String messageId) isTransferCancelled,
    required bool Function(String messageId) removeCancelledTransfer,
    required Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required String sourcePath,
    })
    saveMediaFile,
    required Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required Uint8List bytes,
    })
    saveMediaBytes,
    required Future<void> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required Chat? Function(String peerId) findChat,
    required int Function() unreadMessagesCount,
    required void Function(int count) setBadgeCount,
    required void Function(String peerId) notifyMessageUpdated,
    required String Function(Object error, {required String fallback})
    transferStatusForError,
  }) async {
    logQueue(
      'upload prepare peer=$peerId messageId=$messageId file=$fileName '
      'size=$fileSizeBytes path=${filePath?.isNotEmpty == true} '
      'bytes=${fileBytes?.length ?? 0}',
    );
    await updateFileProgress(
      peerId,
      messageId,
      sentBytes: 0,
      totalBytes: fileSizeBytes,
      statusText: 'Подготовка',
    );
    setStatus(peerId, ChatConnectionStatus.connecting);
    try {
      Uint8List? resolvedBytes = fileBytes;
      if (resolvedBytes == null && filePath != null && filePath.isNotEmpty) {
        resolvedBytes = Uint8List.fromList(await File(filePath).readAsBytes());
      }
      if (resolvedBytes == null) {
        throw StateError('Не удалось прочитать файл');
      }
      logQueue(
        'upload blob start peer=$peerId messageId=$messageId bytes=${resolvedBytes.length}',
      );
      if (isTransferCancelled(messageId)) {
        throw const FileTransferCancelledException();
      }

      final uploadResult = await _relayMediaTransfer.uploadBlob(
        peerId: peerId,
        messageId: messageId,
        upload: (onProgress) => _facade.uploadBlob(
          scopeKind: RelayBlobScopeKind.direct,
          targetId: peerId,
          fileName: fileName,
          mimeType: mimeType,
          bytes: resolvedBytes!,
          blobId: 'blob:$messageId',
          onProgress: onProgress,
        ),
        onProgress:
            ({
              required int sentBytes,
              required int totalBytes,
              required String status,
            }) {
              unawaited(
                updateFileProgress(
                  peerId,
                  messageId,
                  sentBytes: sentBytes,
                  totalBytes: totalBytes,
                  statusText: status,
                ),
              );
            },
      );
      if (!uploadResult.isUploaded) {
        throw uploadResult.error ?? StateError('Relay blob upload failed');
      }
      final blobId = uploadResult.blobId!;
      if (isTransferCancelled(messageId)) {
        throw const FileTransferCancelledException();
      }
      logQueue(
        'upload blob done peer=$peerId messageId=$messageId blobId=$blobId',
      );

      final blobRefPayload = _outboundCodec.encodeDirectBlobRefPayload(
        peerId: peerId,
        messageId: messageId,
        contentKind: 'media',
        fileName: fileName,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
        blobId: blobId,
      );
      await rememberOutgoingRelayMediaState(
        OutgoingRelayMediaState(
          peerId: peerId,
          messageId: messageId,
          targetKind: OutgoingRelayMediaTargetKind.direct,
          blobId: blobId,
          payloadText: blobRefPayload,
          recipients: null,
          localFilePath: filePath,
          replyToMessageId: replyTo?.id,
          replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
          replyToSenderLabel: replySenderLabel(peerId, replyTo),
          replyToTextPreview: replyTextPreview(replyTo),
          replyToKind: replyKind(replyTo),
        ),
      );
      final sendReceipt = await _facade.sendPayload(
        peerId,
        text: blobRefPayload,
        messageId: messageId,
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: replySenderLabel(peerId, replyTo),
        replyToTextPreview: replyTextPreview(replyTo),
        replyToKind: replyKind(replyTo),
      );
      await forgetOutgoingRelayMediaState(peerId, messageId);
      logQueue('send ref done peer=$peerId messageId=$messageId');

      String? localPath;
      if (filePath != null && filePath.isNotEmpty) {
        localPath = await saveMediaFile(
          peerId: peerId,
          messageId: messageId,
          fileName: fileName,
          sourcePath: filePath,
        );
      } else if (fileBytes != null) {
        localPath = await saveMediaBytes(
          peerId: peerId,
          messageId: messageId,
          fileName: fileName,
          bytes: fileBytes,
        );
      }

      await replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferId: _outboundCodec.directBlobTransferId(
            peerId: peerId,
            messageId: messageId,
            blobId: blobId,
          ),
          transferredBytes: null,
          sendProgress: null,
          transferStatus: null,
          localFilePath: (localPath != null && localPath.isNotEmpty)
              ? localPath
              : current.localFilePath,
          fileDataBase64: null,
          status: MessageStatus.sent,
        ),
      );
      clearProgressUpdate(peerId, messageId);
      try {
        await _facade.sendDirectPushEvent(
          directPeerId: peerId,
          messageId: messageId,
          relayServers: sendReceipt.relayServers,
          notificationType: chatNotificationTypeForFile(
            fileName: fileName,
            mimeType: mimeType,
          ),
          relayScopeKind: 'direct',
          relayBlobId: blobId,
          relayMessageId: messageId,
        );
      } catch (error) {
        developer.log(
          'push event send failed direct=$peerId messageId=$messageId error=$error',
          name: 'chat',
        );
      }

      if (removeCancelledTransfer(messageId)) {
        final chat = findChat(peerId);
        if (chat != null && chat.messagesLoaded) {
          Message? message;
          for (final m in chat.messages) {
            if (m.id == messageId) {
              message = m;
              break;
            }
          }
          if (message != null && (message.transferredBytes ?? 0) == 0) {
            await removeMessageWithMediaCleanup(peerId, messageId);
            setStatus(peerId, ChatConnectionStatus.connected);
            setBadgeCount(unreadMessagesCount());
            notifyMessageUpdated(peerId);
            return;
          }
        }
      }

      setStatus(peerId, ChatConnectionStatus.connected);
      setBadgeCount(unreadMessagesCount());
      notifyMessageUpdated(peerId);
    } catch (e) {
      logQueue('failed peer=$peerId messageId=$messageId error=$e');
      final wasCancelled = removeCancelledTransfer(messageId);
      if (wasCancelled) {
        await forgetOutgoingRelayMediaState(peerId, messageId);
        setStatus(peerId, ChatConnectionStatus.connected);
        notifyMessageUpdated(peerId);
        return;
      }

      await replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferredBytes: 0,
          sendProgress: 0.0,
          transferStatus: transferStatusForError(
            e,
            fallback: 'Ошибка отправки',
          ),
          status: MessageStatus.failed,
        ),
      );
      clearProgressUpdate(peerId, messageId);
      setStatus(peerId, ChatConnectionStatus.error, error: e.toString());
      notifyMessageUpdated(peerId);
    }
  }
}
