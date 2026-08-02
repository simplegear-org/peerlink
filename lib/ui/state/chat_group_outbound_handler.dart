import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/relay/relay_media_transfer_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_notification_type.dart';

class ChatGroupOutboundHandler {
  const ChatGroupOutboundHandler({
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
    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        _facade.peerId,
      }.toList(growable: false);
      await persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
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
      final blobId = await _facade.uploadBlob(
        scopeKind: RelayBlobScopeKind.group,
        targetId: groupChat.peerId,
        fileName: 'text.txt',
        mimeType: 'text/plain',
        bytes: payloadBytes,
        blobId: 'blob:${message.id}',
      );
      final blobRefPayload = _outboundCodec.encodeGroupBlobRefPayload(
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
          _outboundCodec.encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: message.id,
            text: blobRefPayload,
          );
      receipt = await _facade.sendPayload(
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
      final payload = _outboundCodec.encodeGroupMessagePayload(
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
              await _facade.sendPayload(
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
      await _facade.sendGroupPushEvent(
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

  Future<void> sendFile(
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
    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        _facade.peerId,
      }.toList(growable: false);
      await persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
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
      final uploadResult = await _relayMediaTransfer.uploadBlob(
        peerId: groupChat.peerId,
        messageId: messageId,
        upload: (onProgress) => _facade.uploadBlob(
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
      final blobRefPayload = _outboundCodec.encodeGroupBlobRefPayload(
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
          _outboundCodec.encodeGroupMessagePayload(
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
      sendReceipt = await _facade.sendPayload(
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
            ? _outboundCodec.groupBlobTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
                blobId: blobId,
              )
            : _outboundCodec.groupFileTransferId(
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
        await _facade.sendGroupPushEvent(
          groupId: groupChat.peerId,
          messageId: messageId,
          recipientUserIds: recipients,
          relayServers: sendReceipt.relayServers,
          notificationType: chatNotificationTypeForFile(
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
}
