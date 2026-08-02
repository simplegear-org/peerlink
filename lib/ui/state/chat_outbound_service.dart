import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../core/node/node_facade.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_direct_outbound_handler.dart';
import 'chat_group_outbound_handler.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_notification_type.dart';
import '../../core/relay/relay_media_transfer_service.dart';

class ChatOutboundService {
  final NodeFacade facade;
  final RelayMediaTransferService relayMediaTransfer;
  final ChatOutboundCodec outboundCodec;
  late final ChatDirectOutboundHandler _directOutboundHandler;
  late final ChatGroupOutboundHandler _groupOutboundHandler;

  ChatOutboundService({
    required this.facade,
    required this.relayMediaTransfer,
    required this.outboundCodec,
  }) {
    _directOutboundHandler = ChatDirectOutboundHandler(
      facade: facade,
      relayMediaTransfer: relayMediaTransfer,
      outboundCodec: outboundCodec,
    );
    _groupOutboundHandler = ChatGroupOutboundHandler(
      facade: facade,
      relayMediaTransfer: relayMediaTransfer,
      outboundCodec: outboundCodec,
    );
  }

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
    await _directOutboundHandler.sendMessage(
      peerId,
      message,
      updateMessageStatusById: updateMessageStatusById,
      setStatus: setStatus,
    );
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
    await _groupOutboundHandler.sendMessage(
      groupChat,
      message,
      persistChatSummary: persistChatSummary,
      ensureGroupKey: ensureGroupKey,
      encryptGroupBytes: encryptGroupBytes,
      encryptGroupText: encryptGroupText,
      collectGroupRecipients: collectGroupRecipients,
      updateMessageStatusById: updateMessageStatusById,
      setStatus: setStatus,
    );
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
    await _directOutboundHandler.sendFile(
      peerId,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      replySenderLabel: replySenderLabel,
      replyTextPreview: replyTextPreview,
      replyKind: replyKind,
      updateFileProgress: updateFileProgress,
      logQueue: logQueue,
      setStatus: setStatus,
      rememberOutgoingRelayMediaState: rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: forgetOutgoingRelayMediaState,
      replaceMessage: replaceMessage,
      clearProgressUpdate: clearProgressUpdate,
      isTransferCancelled: isTransferCancelled,
      removeCancelledTransfer: removeCancelledTransfer,
      saveMediaFile: saveMediaFile,
      saveMediaBytes: saveMediaBytes,
      removeMessageWithMediaCleanup: removeMessageWithMediaCleanup,
      findChat: findChat,
      unreadMessagesCount: unreadMessagesCount,
      setBadgeCount: setBadgeCount,
      notifyMessageUpdated: notifyMessageUpdated,
      transferStatusForError: transferStatusForError,
    );
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
    await _groupOutboundHandler.sendFile(
      groupChat,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      persistChatSummary: persistChatSummary,
      collectGroupRecipients: collectGroupRecipients,
      ensureGroupKey: ensureGroupKey,
      encryptGroupBytes: encryptGroupBytes,
      encryptGroupText: encryptGroupText,
      replySenderLabel: replySenderLabel,
      replyTextPreview: replyTextPreview,
      replyKind: replyKind,
      updateFileProgress: updateFileProgress,
      rememberOutgoingRelayMediaState: rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: forgetOutgoingRelayMediaState,
      replaceMessage: replaceMessage,
      clearProgressUpdate: clearProgressUpdate,
      saveMediaFile: saveMediaFile,
      saveMediaBytes: saveMediaBytes,
      transferStatusForError: transferStatusForError,
      setStatus: setStatus,
      notifyMessageUpdated: notifyMessageUpdated,
    );
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
    return chatNotificationTypeForFile(fileName: fileName, mimeType: mimeType);
  }
}
