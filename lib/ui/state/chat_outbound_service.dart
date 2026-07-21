import 'dart:async';
import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../../core/messaging/chat_service.dart';
import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_outbound_codec.dart';
import '../../core/relay/relay_media_transfer_service.dart';

class ChatOutboundService {
  final NodeFacade facade;
  final RelayMediaTransferService relayMediaTransfer;
  final ChatOutboundCodec outboundCodec;

  ChatOutboundService({
    required this.facade,
    required this.relayMediaTransfer,
    required this.outboundCodec,
  });

  Future<void> sendDirectMessage(
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
      final receipt = await facade.sendPayload(
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
        await facade.sendDirectPushEvent(
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

  Future<void> sendGroupMessage(
    Chat groupChat,
    Message message, {
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<String> Function(Chat chat) ensureGroupKey,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List plainBytes,
    })
    encryptGroupBytes,
    required Future<String?> Function({
      required String groupId,
      required String plainText,
    })
    encryptGroupText,
    required List<String> Function(Chat chat) collectGroupRecipients,
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
    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        facade.peerId,
      }.toList(growable: false);
      await persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      await updateMessageStatusById(
        groupChat.peerId,
        message.id,
        MessageStatus.failed,
      );
      setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Вы больше не участник этого чата',
      );
      return;
    }

    final recipients = collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      await updateMessageStatusById(
        groupChat.peerId,
        message.id,
        MessageStatus.failed,
      );
      setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Group has no members',
      );
      return;
    }

    setStatus(groupChat.peerId, ChatConnectionStatus.connecting);
    var hasFailure = false;
    var receipt = ChatSendReceipt.empty;
    try {
      await ensureGroupKey(groupChat);
      final plainBytes = Uint8List.fromList(utf8.encode(message.text));
      final encryptedBytes = await encryptGroupBytes(
        groupId: groupChat.peerId,
        plainBytes: plainBytes,
      );
      final payloadBytes = encryptedBytes ?? plainBytes;
      final blobId = await facade.uploadBlob(
        scopeKind: RelayBlobScopeKind.group,
        targetId: groupChat.peerId,
        fileName: 'text.txt',
        mimeType: 'text/plain',
        bytes: payloadBytes,
        blobId: 'blob:${message.id}',
      );
      final blobRefPayload = outboundCodec.encodeGroupBlobRefPayload(
        groupChat: groupChat,
        messageId: message.id,
        contentKind: 'text',
        textPreview: message.text,
        blobId: blobId,
      );
      final securePayload = await encryptGroupText(
        groupId: groupChat.peerId,
        plainText: blobRefPayload,
      );
      final payload =
          securePayload ??
          outboundCodec.encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: message.id,
            text: blobRefPayload,
          );
      receipt = await facade.sendPayload(
        groupChat.peerId,
        targetKind: ChatPayloadTargetKind.group,
        recipients: recipients,
        text: payload,
        messageId: message.id,
        kind: 'text',
        replyToMessageId: message.replyToMessageId,
        replyToSenderPeerId: message.replyToSenderPeerId,
        replyToSenderLabel: message.replyToSenderLabel,
        replyToTextPreview: message.replyToTextPreview,
        replyToKind: message.replyToKind,
      );
    } catch (_) {
      const fanoutConcurrency = 6;
      final payload = outboundCodec.encodeGroupMessagePayload(
        groupChat: groupChat,
        messageId: message.id,
        text: message.text,
      );
      for (
        var batchStart = 0;
        batchStart < recipients.length;
        batchStart += fanoutConcurrency
      ) {
        final batchEnd = (batchStart + fanoutConcurrency > recipients.length)
            ? recipients.length
            : batchStart + fanoutConcurrency;
        final batch = recipients.sublist(batchStart, batchEnd);
        final results = await Future.wait(
          batch.asMap().entries.map((entry) async {
            final recipient = entry.value;
            final recipientIndex = batchStart + entry.key;
            final perRecipientMessageId = '${message.id}:$recipientIndex';
            try {
              await facade.sendPayload(
                recipient,
                text: payload,
                messageId: perRecipientMessageId,
                replyToMessageId: message.replyToMessageId,
                replyToSenderPeerId: message.replyToSenderPeerId,
                replyToSenderLabel: message.replyToSenderLabel,
                replyToTextPreview: message.replyToTextPreview,
                replyToKind: message.replyToKind,
              );
              return true;
            } catch (_) {
              return false;
            }
          }),
        );
        if (results.any((ok) => !ok)) {
          hasFailure = true;
        }
      }
    }

    if (hasFailure) {
      await updateMessageStatusById(
        groupChat.peerId,
        message.id,
        MessageStatus.failed,
      );
      setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Failed to send to some group members',
      );
      return;
    }

    await updateMessageStatusById(
      groupChat.peerId,
      message.id,
      MessageStatus.sent,
    );
    try {
      await facade.sendGroupPushEvent(
        groupId: groupChat.peerId,
        messageId: message.id,
        recipientUserIds: recipients,
        relayServers: receipt.relayServers,
        notificationType: 'text',
        relayScopeKind: 'group',
        relayMessageId: message.id,
      );
    } catch (error) {
      developer.log(
        'push event send failed group=${groupChat.peerId} messageId=${message.id} error=$error',
        name: 'chat',
      );
    }
    setStatus(groupChat.peerId, ChatConnectionStatus.connected);
  }

  Future<void> sendDirectFile(
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

      final uploadResult = await relayMediaTransfer.uploadBlob(
        peerId: peerId,
        messageId: messageId,
        upload: (onProgress) => facade.uploadBlob(
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

      final blobRefPayload = outboundCodec.encodeDirectBlobRefPayload(
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
      final sendReceipt = await facade.sendPayload(
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
          transferId: outboundCodec.directBlobTransferId(
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
        await facade.sendDirectPushEvent(
          directPeerId: peerId,
          messageId: messageId,
          relayServers: sendReceipt.relayServers,
          notificationType: notificationTypeForFile(
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

  Future<void> sendGroupFile(
    Chat groupChat, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
    required Future<void> Function(Chat chat) persistChatSummary,
    required List<String> Function(Chat chat) collectGroupRecipients,
    required Future<String> Function(Chat chat) ensureGroupKey,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List plainBytes,
    })
    encryptGroupBytes,
    required Future<String?> Function({
      required String groupId,
      required String plainText,
    })
    encryptGroupText,
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
    required String Function(Object error, {required String fallback})
    transferStatusForError,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        facade.peerId,
      }.toList(growable: false);
      await persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      await replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Вы больше не участник чата',
        ),
      );
      setStatus(groupChat.peerId, ChatConnectionStatus.error);
      return;
    }

    final recipients = collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      await replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Нет участников для отправки',
        ),
      );
      return;
    }

    setStatus(groupChat.peerId, ChatConnectionStatus.connecting);
    await updateFileProgress(
      groupChat.peerId,
      messageId,
      sentBytes: 0,
      totalBytes: fileSizeBytes,
      statusText: 'Подготовка',
    );

    Uint8List? resolvedBytes = fileBytes;
    if (resolvedBytes == null && filePath != null && filePath.isNotEmpty) {
      resolvedBytes = Uint8List.fromList(await File(filePath).readAsBytes());
    }
    if (resolvedBytes == null) {
      await replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Не удалось прочитать файл',
        ),
      );
      setStatus(groupChat.peerId, ChatConnectionStatus.error);
      return;
    }

    var hasFailure = false;
    Object? failureError;
    String? blobId;
    var sendReceipt = ChatSendReceipt.empty;
    try {
      await ensureGroupKey(groupChat);
      final encryptedBytes = await encryptGroupBytes(
        groupId: groupChat.peerId,
        plainBytes: resolvedBytes,
      );
      final payloadBytes = encryptedBytes ?? resolvedBytes;
      await updateFileProgress(
        groupChat.peerId,
        messageId,
        sentBytes: 0,
        totalBytes: fileSizeBytes,
        statusText: 'Загрузка в relay',
      );
      final uploadResult = await relayMediaTransfer.uploadBlob(
        peerId: groupChat.peerId,
        messageId: messageId,
        upload: (onProgress) => facade.uploadBlob(
          scopeKind: RelayBlobScopeKind.group,
          targetId: groupChat.peerId,
          fileName: fileName,
          mimeType: mimeType,
          bytes: payloadBytes,
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
                  groupChat.peerId,
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
      final uploadedBlobId = uploadResult.blobId!;
      blobId = uploadedBlobId;
      final blobRefPayload = outboundCodec.encodeGroupBlobRefPayload(
        groupChat: groupChat,
        messageId: messageId,
        contentKind: 'media',
        fileName: fileName,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
        blobId: uploadedBlobId,
      );
      final securePayload = await encryptGroupText(
        groupId: groupChat.peerId,
        plainText: blobRefPayload,
      );
      final payload =
          securePayload ??
          outboundCodec.encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: messageId,
            text: blobRefPayload,
          );
      await rememberOutgoingRelayMediaState(
        OutgoingRelayMediaState(
          peerId: groupChat.peerId,
          messageId: messageId,
          targetKind: OutgoingRelayMediaTargetKind.group,
          blobId: uploadedBlobId,
          payloadText: payload,
          recipients: recipients,
          localFilePath: filePath,
          replyToMessageId: replyTo?.id,
          replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
          replyToSenderLabel: replySenderLabel(groupChat.peerId, replyTo),
          replyToTextPreview: replyTextPreview(replyTo),
          replyToKind: replyKind(replyTo),
        ),
      );
      sendReceipt = await facade.sendPayload(
        groupChat.peerId,
        targetKind: ChatPayloadTargetKind.group,
        recipients: recipients,
        text: payload,
        messageId: messageId,
        kind: 'text',
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: replySenderLabel(groupChat.peerId, replyTo),
        replyToTextPreview: replyTextPreview(replyTo),
        replyToKind: replyKind(replyTo),
      );
      await forgetOutgoingRelayMediaState(groupChat.peerId, messageId);
      await updateFileProgress(
        groupChat.peerId,
        messageId,
        sentBytes: fileSizeBytes,
        totalBytes: fileSizeBytes,
        statusText: 'Отправлено',
      );
    } catch (error) {
      hasFailure = true;
      failureError = error;
    }

    String? localPath;
    if (filePath != null && filePath.isNotEmpty) {
      localPath = await saveMediaFile(
        peerId: groupChat.peerId,
        messageId: messageId,
        fileName: fileName,
        sourcePath: filePath,
      );
    } else if (fileBytes != null) {
      localPath = await saveMediaBytes(
        peerId: groupChat.peerId,
        messageId: messageId,
        fileName: fileName,
        bytes: fileBytes,
      );
    }

    await replaceMessage(
      groupChat.peerId,
      messageId,
      (current) => ChatMessageCopy.copy(
        current,
        transferId: blobId != null
            ? outboundCodec.groupBlobTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
                blobId: blobId,
              )
            : outboundCodec.groupFileTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
              ),
        localFilePath: (localPath != null && localPath.isNotEmpty)
            ? localPath
            : current.localFilePath,
        fileDataBase64: null,
        transferredBytes: hasFailure ? current.transferredBytes : null,
        sendProgress: hasFailure ? current.sendProgress : null,
        transferStatus: hasFailure
            ? transferStatusForError(
                failureError ?? StateError('group media send failed'),
                fallback: 'Ошибка отправки',
              )
            : null,
        status: hasFailure ? MessageStatus.failed : MessageStatus.sent,
      ),
    );
    clearProgressUpdate(groupChat.peerId, messageId);

    setStatus(
      groupChat.peerId,
      hasFailure ? ChatConnectionStatus.error : ChatConnectionStatus.connected,
      error: hasFailure ? 'Failed to send group media' : null,
    );
    if (!hasFailure) {
      try {
        await facade.sendGroupPushEvent(
          groupId: groupChat.peerId,
          messageId: messageId,
          recipientUserIds: recipients,
          relayServers: sendReceipt.relayServers,
          notificationType: notificationTypeForFile(
            fileName: fileName,
            mimeType: mimeType,
          ),
          relayScopeKind: 'group',
          relayBlobId: blobId,
          relayMessageId: messageId,
        );
      } catch (error) {
        developer.log(
          'push event send failed group=${groupChat.peerId} '
          'messageId=$messageId error=$error',
          name: 'chat',
        );
      }
    }
    notifyMessageUpdated(groupChat.peerId);
  }

  Future<void> retryFileMessage(
    Chat chat,
    Message message, {
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required Message? Function(String peerId, Message message) rebuildReply,
    required bool Function(String messageId) isFileQueuedOrActive,
    required void Function(QueuedFileTransfer item) enqueueFile,
    required void Function() refreshQueuedFileStatuses,
    required Future<void> Function(
      Chat groupChat, {
      required String messageId,
      required String fileName,
      Uint8List? fileBytes,
      String? filePath,
      required int fileSizeBytes,
      String? mimeType,
      Message? replyTo,
    })
    sendGroupFile,
    required Future<void> Function() drainFileQueue,
  }) async {
    final fileName = message.fileName ?? message.text;
    Uint8List? bytes;
    String? path = message.localFilePath?.trim();
    if (path != null && path.isEmpty) {
      path = null;
    }
    if (path != null && !File(path).existsSync()) {
      path = null;
    }
    final embedded = message.fileDataBase64;
    if (path == null && embedded != null && embedded.isNotEmpty) {
      try {
        bytes = base64Decode(embedded);
      } catch (_) {
        bytes = null;
      }
    }
    if (path == null && (bytes == null || bytes.isEmpty)) {
      await replaceMessage(
        chat.peerId,
        message.id,
        (current) => ChatMessageCopy.copy(
          current,
          transferredBytes: 0,
          sendProgress: 0.0,
          transferStatus: 'Файл недоступен',
          status: MessageStatus.failed,
        ),
      );
      return;
    }

    final fileSize =
        message.fileSizeBytes ??
        bytes?.length ??
        (path == null ? 0 : File(path).lengthSync());
    await replaceMessage(
      chat.peerId,
      message.id,
      (current) => ChatMessageCopy.copy(
        current,
        transferredBytes: 0,
        sendProgress: 0.02,
        transferStatus: 'В очереди',
        status: MessageStatus.sending,
      ),
    );

    if (chat.isGroup) {
      unawaited(
        sendGroupFile(
          chat,
          messageId: message.id,
          fileName: fileName,
          fileBytes: bytes,
          filePath: path,
          fileSizeBytes: fileSize,
          mimeType: message.mimeType,
          replyTo: rebuildReply(chat.peerId, message),
        ),
      );
      return;
    }

    if (!isFileQueuedOrActive(message.id)) {
      enqueueFile(
        QueuedFileTransfer(
          peerId: chat.peerId,
          messageId: message.id,
          fileName: fileName,
          fileBytes: bytes,
          filePath: path,
          fileSizeBytes: fileSize,
          mimeType: message.mimeType,
          replyTo: rebuildReply(chat.peerId, message),
        ),
      );
    }
    refreshQueuedFileStatuses();
    unawaited(drainFileQueue());
  }

  String notificationTypeForFile({required String fileName, String? mimeType}) {
    final mime = (mimeType ?? '').trim().toLowerCase();
    final name = fileName.trim().toLowerCase();
    if (mime.startsWith('image/')) {
      return 'photo';
    }
    if (mime.startsWith('video/')) {
      return 'video';
    }
    if (mime.startsWith('audio/') ||
        name.endsWith('.m4a') ||
        name.endsWith('.aac') ||
        name.endsWith('.mp3') ||
        name.endsWith('.wav') ||
        name.endsWith('.ogg') ||
        name.endsWith('.opus')) {
      return 'voice';
    }
    if (mime.contains('geo') ||
        mime.contains('gpx') ||
        mime.contains('kml') ||
        name.endsWith('.geojson') ||
        name.endsWith('.gpx') ||
        name.endsWith('.kml')) {
      return 'geo';
    }
    return 'file';
  }
}
