// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

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
       _saveMediaFile = saveMediaFile,
       _saveMediaBytes = saveMediaBytes,
       _ensureThumbnail = ensureThumbnail;

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
  final Future<String> Function({
    required String peerId,
    required String messageId,
    required String fileName,
    required String sourcePath,
  })
  _saveMediaFile;
  final Future<String> Function({
    required String peerId,
    required String messageId,
    required String fileName,
    required Uint8List bytes,
  })
  _saveMediaBytes;
  final Future<String?> Function(Message message) _ensureThumbnail;

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
    unawaited(
      _prepareLocalMediaAndUpdate(
        chat: chat,
        peerId: peerId,
        messageId: messageId,
        fileName: fileName,
        fileBytes: fileBytes,
        filePath: filePath,
        mimeType: mimeType,
      ),
    );
  }

  Future<void> _prepareLocalMediaAndUpdate({
    required Chat chat,
    required String peerId,
    required String messageId,
    required String fileName,
    required Uint8List? fileBytes,
    required String? filePath,
    required String? mimeType,
  }) async {
    String? localPath;
    try {
      if (filePath != null && filePath.isNotEmpty) {
        localPath = await _saveMediaFile(
          peerId: peerId,
          messageId: messageId,
          fileName: fileName,
          sourcePath: filePath,
        );
      } else if (fileBytes != null) {
        localPath = await _saveMediaBytes(
          peerId: peerId,
          messageId: messageId,
          fileName: fileName,
          bytes: fileBytes,
        );
      }
    } catch (_) {
      localPath = null;
    }

    String? thumbnailPath;
    if (localPath != null && localPath.isNotEmpty) {
      try {
        thumbnailPath = await _ensureThumbnail(
          Message(
            id: messageId,
            peerId: peerId,
            text: fileName,
            incoming: false,
            timestamp: DateTime.now(),
            kind: MessageKind.file,
            fileName: fileName,
            mimeType: mimeType,
            localFilePath: localPath,
          ),
        );
      } catch (_) {
        thumbnailPath = null;
      }
    }

    if ((localPath == null || localPath.isEmpty) &&
        (thumbnailPath == null || thumbnailPath.isEmpty)) {
      return;
    }

    final index = chat.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) {
      return;
    }
    final current = chat.messages[index];
    chat.messages[index] = ChatMessageCopy.copy(
      current,
      localFilePath: localPath?.isNotEmpty == true
          ? localPath
          : current.localFilePath,
      thumbnailPath: thumbnailPath?.isNotEmpty == true
          ? thumbnailPath
          : current.thumbnailPath,
    );
    await _persistLoadedChat(peerId);
    _notifyMessageUpdated(peerId);
  }
}
