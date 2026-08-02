import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_repository.dart';

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
    if (!_storage.isManagedMediaPath(path)) {
      return;
    }
    await _storage.deleteMediaFile(path);
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
