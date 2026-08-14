// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_direct_media_crypto_service.dart';
import 'chat_media_outbound_service.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_notification_type.dart';

class ChatDirectOutboundHandler {
  const ChatDirectOutboundHandler({
    required NodeFacade facade,
    required ChatOutboundCodec outboundCodec,
    required ChatMediaOutboundService mediaOutboundService,
    required ChatDirectMediaCryptoService directMediaCryptoService,
  }) : _facade = facade,
       _outboundCodec = outboundCodec,
       _mediaOutboundService = mediaOutboundService,
       _directMediaCryptoService = directMediaCryptoService;

  final NodeFacade _facade;
  final ChatOutboundCodec _outboundCodec;
  final ChatMediaOutboundService _mediaOutboundService;
  final ChatDirectMediaCryptoService _directMediaCryptoService;

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
    required Future<String?> Function(Message message) ensureThumbnail,
    required Future<void> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required Chat? Function(String peerId) findChat,
    required int Function() unreadMessagesCount,
    required void Function(int count) setBadgeCount,
    required void Function(String peerId) notifyMessageUpdated,
    required String Function(Object error, {required String fallback})
    transferStatusForError,
  }) async {
    setStatus(peerId, ChatConnectionStatus.connecting);
    try {
      final upload = await _mediaOutboundService.prepareAndUpload(
        chatPeerId: peerId,
        messageId: messageId,
        fileName: fileName,
        fileBytes: fileBytes,
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        mimeType: mimeType,
        scopeKind: RelayBlobScopeKind.direct,
        targetId: peerId,
        updateFileProgress: updateFileProgress,
        logQueue: logQueue,
        isCancelled: () => isTransferCancelled(messageId),
        transformPayload: (plainBytes) {
          return _directMediaCryptoService.encryptForPeer(
            peerId: peerId,
            plainBytes: plainBytes,
          );
        },
      );
      final blobId = upload.blobId;

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

      final local = await _mediaOutboundService.saveLocalMedia(
        peerId: peerId,
        messageId: messageId,
        fileName: fileName,
        fileBytes: fileBytes,
        filePath: filePath,
        mimeType: mimeType,
        saveMediaFile: saveMediaFile,
        saveMediaBytes: saveMediaBytes,
        ensureThumbnail: ensureThumbnail,
      );

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
          localFilePath:
              (local.localPath != null && local.localPath!.isNotEmpty)
              ? local.localPath
              : current.localFilePath,
          thumbnailPath: local.thumbnailPath ?? current.thumbnailPath,
          fileDataBase64: null,
          status: MessageStatus.sent,
          receiptStatus: MessageReceiptStatus.sent,
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
