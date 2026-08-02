import 'dart:async';
import 'dart:typed_data';

import '../../core/notification/notification_service.dart';
import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_file_queue_service.dart';
import 'chat_outbound_service.dart';

class ChatFileTransferCoordinator {
  const ChatFileTransferCoordinator({
    required ChatFileQueueService fileQueueService,
    required ChatOutboundService outboundService,
    required StorageService storage,
    required String localPeerId,
    required Map<String, Chat> chats,
    required void Function(String message) logQueue,
    required Future<void> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required Future<void> Function(String peerId, String messageId)
    forgetOutgoingRelayMediaState,
    required void Function(String peerId) schedulePersistLoadedChat,
    required void Function(String peerId) notifyMessageUpdated,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    updateFileProgress,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required void Function(String peerId, String messageId) clearProgressUpdate,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required Future<void> Function(OutgoingRelayMediaState state)
    rememberOutgoingRelayMediaState,
    required String? Function(String chatPeerId, Message? replyTo)
    replySenderLabel,
    required String? Function(Message? replyTo) replyTextPreview,
    required String? Function(Message? replyTo) replyKind,
    required int Function() unreadMessagesCount,
    required void Function(int unreadCount)? onUnreadBadgeCountChanged,
    required String Function(Object error, {required String fallback})
    transferStatusForError,
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
  }) : _fileQueueService = fileQueueService,
       _outboundService = outboundService,
       _storage = storage,
       _localPeerId = localPeerId,
       _chats = chats,
       _logQueue = logQueue,
       _removeMessageWithMediaCleanup = removeMessageWithMediaCleanup,
       _forgetOutgoingRelayMediaState = forgetOutgoingRelayMediaState,
       _schedulePersistLoadedChat = schedulePersistLoadedChat,
       _notifyMessageUpdated = notifyMessageUpdated,
       _updateFileProgress = updateFileProgress,
       _replaceMessage = replaceMessage,
       _clearProgressUpdate = clearProgressUpdate,
       _setStatus = setStatus,
       _rememberOutgoingRelayMediaState = rememberOutgoingRelayMediaState,
       _replySenderLabel = replySenderLabel,
       _replyTextPreview = replyTextPreview,
       _replyKind = replyKind,
       _unreadMessagesCount = unreadMessagesCount,
       _onUnreadBadgeCountChanged = onUnreadBadgeCountChanged,
       _transferStatusForError = transferStatusForError,
       _sendGroupFile = sendGroupFile;

  final ChatFileQueueService _fileQueueService;
  final ChatOutboundService _outboundService;
  final StorageService _storage;
  final String _localPeerId;
  final Map<String, Chat> _chats;
  final void Function(String message) _logQueue;
  final Future<void> Function(String peerId, String messageId)
  _removeMessageWithMediaCleanup;
  final Future<void> Function(String peerId, String messageId)
  _forgetOutgoingRelayMediaState;
  final void Function(String peerId) _schedulePersistLoadedChat;
  final void Function(String peerId) _notifyMessageUpdated;
  final Future<void> Function(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  })
  _updateFileProgress;
  final Future<void> Function(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  )
  _replaceMessage;
  final void Function(String peerId, String messageId) _clearProgressUpdate;
  final void Function(
    String peerId,
    ChatConnectionStatus status, {
    String? error,
  })
  _setStatus;
  final Future<void> Function(OutgoingRelayMediaState state)
  _rememberOutgoingRelayMediaState;
  final String? Function(String chatPeerId, Message? replyTo) _replySenderLabel;
  final String? Function(Message? replyTo) _replyTextPreview;
  final String? Function(Message? replyTo) _replyKind;
  final int Function() _unreadMessagesCount;
  final void Function(int unreadCount)? _onUnreadBadgeCountChanged;
  final String Function(Object error, {required String fallback})
  _transferStatusForError;
  final Future<void> Function(
    Chat groupChat, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  })
  _sendGroupFile;

  Future<void> drainFileQueue() async {
    await _fileQueueService.drain(
      logQueue: _logQueue,
      sendFile: (item) {
        return sendDirectFile(
          item.peerId,
          messageId: item.messageId,
          fileName: item.fileName,
          fileBytes: item.fileBytes,
          filePath: item.filePath,
          fileSizeBytes: item.fileSizeBytes,
          mimeType: item.mimeType,
        );
      },
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      refreshQueuedFileStatuses: refreshQueuedFileStatuses,
    );
  }

  void resumeRecoverableFileQueue() {
    _fileQueueService.resumeRecoverableFileQueue(
      chats: _chats.values,
      recoverPendingTransfersForChat: recoverPendingTransfersForChat,
      logQueue: _logQueue,
      refreshQueuedFileStatuses: refreshQueuedFileStatuses,
    );
    if (_fileQueueService.hasQueuedItems) {
      refreshQueuedFileStatuses();
      unawaited(drainFileQueue());
    }
  }

  int recoverPendingTransfersForChat(Chat chat) {
    return _fileQueueService.recoverPendingTransfersForChat(
      chat,
      isRecoverableOutgoingFile: isRecoverableOutgoingFile,
      rebuildReply: rebuildReplyMessage,
      schedulePersistLoadedChat: _schedulePersistLoadedChat,
      notifyMessageUpdated: _notifyMessageUpdated,
      refreshQueuedFileStatuses: refreshQueuedFileStatuses,
      logQueue: _logQueue,
    );
  }

  bool isRecoverableOutgoingFile(Message message) {
    if (message.incoming ||
        message.kind != MessageKind.file ||
        message.status != MessageStatus.sending) {
      return false;
    }
    final status = message.transferStatus ?? '';
    return status == 'В очереди' ||
        status == 'Подготовка' ||
        status.startsWith('Ожидает отправки');
  }

  bool isFileQueuedOrActive(String messageId) {
    return _fileQueueService.isQueuedOrActive(messageId);
  }

  Message? rebuildReplyMessage(String peerId, Message message) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) {
      return null;
    }
    final rawKind = message.replyToKind;
    final kind = MessageKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => MessageKind.text,
    );
    final senderPeerId = message.replyToSenderPeerId;
    return Message(
      id: replyId,
      peerId: peerId,
      text: message.replyToTextPreview ?? '',
      senderPeerId: senderPeerId,
      incoming: senderPeerId != null && senderPeerId != _localPeerId,
      timestamp: DateTime.now(),
      kind: kind,
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
  }) async {
    await _outboundService.sendDirectFile(
      peerId,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      updateFileProgress: _updateFileProgress,
      logQueue: _logQueue,
      setStatus: _setStatus,
      rememberOutgoingRelayMediaState: _rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      isTransferCancelled: _fileQueueService.isTransferCancelled,
      removeCancelledTransfer: _fileQueueService.removeCancelledTransfer,
      saveMediaFile:
          ({
            required peerId,
            required messageId,
            required fileName,
            required sourcePath,
          }) => _storage.saveMediaFile(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            sourcePath: sourcePath,
          ),
      saveMediaBytes:
          ({
            required peerId,
            required messageId,
            required fileName,
            required bytes,
          }) => _storage.saveMediaBytes(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            bytes: bytes,
          ),
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      findChat: (peerId) => _chats[peerId],
      unreadMessagesCount: _unreadMessagesCount,
      setBadgeCount:
          _onUnreadBadgeCountChanged ??
          NotificationService.instance.setBadgeCount,
      notifyMessageUpdated: _notifyMessageUpdated,
      transferStatusForError: _transferStatusForError,
    );
  }

  Future<void> cancelFileTransfer(String peerId, String messageId) async {
    await _fileQueueService.cancelFileTransfer(
      peerId,
      messageId,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      refreshQueuedFileStatuses: refreshQueuedFileStatuses,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> retryFileMessage(Chat chat, Message message) async {
    await _outboundService.retryFileMessage(
      chat,
      message,
      replaceMessage: _replaceMessage,
      rebuildReply: rebuildReplyMessage,
      isFileQueuedOrActive: isFileQueuedOrActive,
      enqueueFile: _fileQueueService.enqueue,
      refreshQueuedFileStatuses: refreshQueuedFileStatuses,
      sendGroupFile: _sendGroupFile,
      drainFileQueue: drainFileQueue,
    );
  }

  void refreshQueuedFileStatuses() {
    _fileQueueService.refreshQueuedFileStatuses(
      chats: _chats,
      schedulePersistLoadedChat: _schedulePersistLoadedChat,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  void enqueue(QueuedFileTransfer item) => _fileQueueService.enqueue(item);
}
