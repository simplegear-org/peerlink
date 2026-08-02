import 'dart:async';
import 'dart:typed_data';

import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_parts.dart';
import 'chat_file_transfer_coordinator.dart';

class ChatFileSendCoordinator {
  static const int maxFileSizeBytes = 1024 * 1024 * 1024;

  const ChatFileSendCoordinator({
    required ChatFileTransferCoordinator fileTransferCoordinator,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat Function(String peerId) ensureChat,
    required String Function() nextLocalMessageId,
    required Future<void> Function(String peerId) persistLoadedChat,
    required String? Function(String chatPeerId, Message? replyTo)
    replySenderLabel,
    required String? Function(Message? replyTo) replyTextPreview,
    required String? Function(Message? replyTo) replyKind,
    required void Function(String message) logQueue,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function() refreshQueuedFileStatuses,
    required Future<void> Function() drainFileQueue,
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
  }) : _fileTransferCoordinator = fileTransferCoordinator,
       _ensureChatLoaded = ensureChatLoaded,
       _ensureChat = ensureChat,
       _nextLocalMessageId = nextLocalMessageId,
       _persistLoadedChat = persistLoadedChat,
       _replySenderLabel = replySenderLabel,
       _replyTextPreview = replyTextPreview,
       _replyKind = replyKind,
       _logQueue = logQueue,
       _notifyMessageUpdated = notifyMessageUpdated,
       _refreshQueuedFileStatuses = refreshQueuedFileStatuses,
       _drainFileQueue = drainFileQueue,
       _sendGroupFile = sendGroupFile;

  final ChatFileTransferCoordinator _fileTransferCoordinator;
  final Future<void> Function(String peerId) _ensureChatLoaded;
  final Chat Function(String peerId) _ensureChat;
  final String Function() _nextLocalMessageId;
  final Future<void> Function(String peerId) _persistLoadedChat;
  final String? Function(String chatPeerId, Message? replyTo) _replySenderLabel;
  final String? Function(Message? replyTo) _replyTextPreview;
  final String? Function(Message? replyTo) _replyKind;
  final void Function(String message) _logQueue;
  final void Function(String peerId) _notifyMessageUpdated;
  final void Function() _refreshQueuedFileStatuses;
  final Future<void> Function() _drainFileQueue;
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

  Future<void> sendFile(
    String peerId, {
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    int? fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) async {
    final resolvedSize = fileSizeBytes ?? fileBytes?.length;
    if ((fileBytes == null && filePath == null) || resolvedSize == null) {
      throw ArgumentError('Either fileBytes or filePath must be provided');
    }

    if (resolvedSize > maxFileSizeBytes) {
      throw StateError('File size exceeds maximum limit of 1 GB');
    }

    await _ensureChatLoaded(peerId);
    final chat = _ensureChat(peerId);

    final messageId = _nextLocalMessageId();
    _logQueue(
      'add peer=$peerId messageId=$messageId file=$fileName size=$resolvedSize path=${filePath?.isNotEmpty == true}',
    );
    chat.messages.add(
      Message(
        id: messageId,
        peerId: peerId,
        text: fileName,
        incoming: false,
        timestamp: DateTime.now(),
        kind: MessageKind.file,
        fileName: fileName,
        mimeType: mimeType,
        localFilePath: filePath,
        transferId: messageId,
        fileSizeBytes: resolvedSize,
        transferredBytes: 0,
        sendProgress: 0.02,
        transferStatus: 'В очереди',
        status: MessageStatus.sending,
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: _replySenderLabel(peerId, replyTo),
        replyToTextPreview: _replyTextPreview(replyTo),
        replyToKind: _replyKind(replyTo),
      ),
    );

    await _persistLoadedChat(peerId);
    _notifyMessageUpdated(peerId);

    if (chat.isGroup) {
      unawaited(
        _sendGroupFile(
          chat,
          messageId: messageId,
          fileName: fileName,
          fileBytes: fileBytes,
          filePath: filePath,
          fileSizeBytes: resolvedSize,
          mimeType: mimeType,
          replyTo: replyTo,
        ),
      );
      return;
    }

    _fileTransferCoordinator.enqueue(
      QueuedFileTransfer(
        peerId: peerId,
        messageId: messageId,
        fileName: fileName,
        fileBytes: fileBytes,
        filePath: filePath,
        fileSizeBytes: resolvedSize,
        mimeType: mimeType,
        replyTo: replyTo,
      ),
    );
    _refreshQueuedFileStatuses();
    unawaited(_drainFileQueue());
  }
}
