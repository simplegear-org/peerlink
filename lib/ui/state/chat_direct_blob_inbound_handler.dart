import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';

class ChatDirectBlobInboundHandler {
  const ChatDirectBlobInboundHandler();

  Future<void> handleIncomingDirectBlobRef(
    ChatMessage msg,
    IncomingBlobRefPayload blobRef, {
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat Function(String peerId, {String? fallbackName}) ensureChat,
    required Future<void> Function(String peerId) persistLoadedChat,
    required String Function({
      required String peerId,
      required String messageId,
      required String blobId,
    })
    directBlobTransferId,
    required void Function(String peerId) notifyMessageUpdated,
    required bool Function(Message message) shouldAutoRestoreIncomingMedia,
    required String incomingRelayFetchStatus,
    required void Function(Message message, {required bool isGroup, bool force})
    restoreMediaInBackground,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final peerId = msg.peerId;
    final payloadPeerId = blobRef.raw['peerId'] as String? ?? '';
    final messageId = blobRef.messageId.trim().isNotEmpty
        ? blobRef.messageId
        : msg.id;
    final fileName = (blobRef.fileName ?? '').trim();
    final blobId = blobRef.blobId.trim();
    final contentKind = blobRef.contentKind.trim();

    if (payloadPeerId.isNotEmpty && payloadPeerId != peerId) {
      developer.log(
        '[chat] direct blob ref ignored peer-mismatch payloadPeer=$payloadPeerId actualPeer=$peerId',
        name: 'chat',
      );
      return;
    }
    if (contentKind != 'media' ||
        messageId.isEmpty ||
        fileName.isEmpty ||
        blobId.isEmpty) {
      return;
    }

    await ensureChatLoaded(peerId);
    final chat = ensureChat(peerId);
    final existingIndex = chat.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (existingIndex == -1) {
      chat.messages.add(
        Message(
          id: messageId,
          peerId: peerId,
          text: fileName,
          senderPeerId: peerId,
          incoming: true,
          timestamp: DateTime.now(),
          kind: MessageKind.file,
          fileName: fileName,
          mimeType: blobRef.mimeType,
          transferId: directBlobTransferId(
            peerId: peerId,
            messageId: messageId,
            blobId: blobId,
          ),
          fileSizeBytes: blobRef.fileSizeBytes,
          replyToMessageId: msg.replyToMessageId,
          replyToSenderPeerId: msg.replyToSenderPeerId,
          replyToSenderLabel: msg.replyToSenderLabel,
          replyToTextPreview: msg.replyToTextPreview,
          replyToKind: msg.replyToKind,
          transferredBytes: 0,
          transferStatus: incomingRelayFetchStatus,
          status: MessageStatus.sent,
          isRead: false,
        ),
      );
      await persistLoadedChat(peerId);
      notifyMessageUpdated(peerId);
      restoreMediaInBackground(
        chat.messages.last,
        isGroup: false,
        force: false,
      );
    } else if (shouldAutoRestoreIncomingMedia(chat.messages[existingIndex])) {
      notifyMessageUpdated(peerId);
      restoreMediaInBackground(
        chat.messages[existingIndex],
        isGroup: false,
        force: false,
      );
    } else {
      notifyMessageUpdated(peerId);
    }

    notifyNewMessage(
      ChatMessage(
        id: messageId,
        peerId: peerId,
        text: fileName,
        kind: 'file',
        fileName: fileName,
        mimeType: blobRef.mimeType,
      ),
    );
    await showMessageNotification(
      fromPeerId: chat.name,
      message: fileName,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }
}
