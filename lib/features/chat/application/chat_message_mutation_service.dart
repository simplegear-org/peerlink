// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';

class ChatMessageMutationService {
  const ChatMessageMutationService({
    required StorageService storage,
    required ChatRepository chatRepository,
    required Map<String, Chat> chats,
  }) : _storage = storage,
       _chatRepository = chatRepository,
       _chats = chats;

  final StorageService _storage;
  final ChatRepository _chatRepository;
  final Map<String, Chat> _chats;

  Future<void> appendMessage(String peerId, Message message) {
    return _chatRepository.appendMessage(peerId, message);
  }

  Future<bool> removeMessage(String peerId, String messageId) {
    return _chatRepository.removeMessage(
      peerId,
      messageId,
      loadedChat: _chats[peerId],
    );
  }

  Future<Message?> findMessage(String peerId, String messageId) {
    return _chatRepository.findMessage(
      peerId,
      messageId,
      loadedChat: _chats[peerId],
    );
  }

  Future<void> deleteManagedMediaForMessage(Message? message) async {
    final path = message?.localFilePath;
    if (_storage.isManagedMediaPath(path)) {
      await _storage.deleteMediaFile(path);
    }
    final thumbnailPath = message?.thumbnailPath;
    if (_storage.isManagedMediaPath(thumbnailPath)) {
      await _storage.deleteMediaFile(thumbnailPath);
    }
  }

  Future<bool> removeMessageWithMediaCleanup(
    String peerId,
    String messageId,
  ) async {
    final message = await findMessage(peerId, messageId);
    await deleteManagedMediaForMessage(message);
    return removeMessage(peerId, messageId);
  }

  Future<bool> removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  ) async {
    final message = await findMessage(peerId, messageId);
    if (message == null) {
      return false;
    }
    final expectedAuthor = (message.senderPeerId ?? message.peerId).trim();
    final requestedAuthor = authorPeerId.trim();
    if (expectedAuthor.isEmpty ||
        requestedAuthor.isEmpty ||
        expectedAuthor != requestedAuthor) {
      developer.log(
        '[chat] delete ignored author mismatch peer=$peerId '
        'messageId=$messageId expected=$expectedAuthor requested=$requestedAuthor',
        name: 'chat',
      );
      return false;
    }
    await deleteManagedMediaForMessage(message);
    return removeMessage(peerId, messageId);
  }

  Future<void> replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) {
    return _chatRepository.replaceMessage(peerId, messageId, transform);
  }
}
