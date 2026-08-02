import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/message.dart';

class ChatRepository {
  final StorageService storage;
  final Chat Function(String peerId, {String? fallbackName}) ensureChat;
  final Future<void> Function(Chat chat) persistChatSummary;
  final bool Function(Message message) isInitialUnreadAnchor;

  ChatRepository({
    required this.storage,
    required this.ensureChat,
    required this.persistChatSummary,
    required this.isInitialUnreadAnchor,
  });

  Future<List<Message>> loadInitialMessages(String peerId, int limit) async {
    final stored = await readStoredMessages(peerId);
    if (stored.length <= limit) {
      return stored;
    }

    final firstUnreadIndex = stored.indexWhere(isInitialUnreadAnchor);
    if (firstUnreadIndex != -1) {
      final leadingContextCount = limit ~/ 2;
      final startIndex = (firstUnreadIndex - leadingContextCount).clamp(
        0,
        stored.length,
      );
      return List<Message>.from(stored.sublist(startIndex), growable: true);
    }

    final startIndex = stored.length - limit;
    if (startIndex <= 0) {
      return stored;
    }

    return List<Message>.from(stored.sublist(startIndex), growable: true);
  }

  Future<List<Message>> readStoredMessages(String peerId) async {
    final raw = await storage.readChatMessages(peerId);
    return raw.map(Message.fromJson).toList(growable: true);
  }

  Future<void> writeStoredMessages(
    String peerId,
    List<Message> messages,
  ) async {
    await storage.writeChatMessages(
      peerId,
      messages
          .map((message) => message.toPersistentJson())
          .toList(growable: false),
    );
  }

  Future<void> upsertStoredMessages(
    String peerId,
    List<Message> messages,
  ) async {
    await storage.upsertChatMessages(
      peerId,
      messages
          .map((message) => message.toPersistentJson())
          .toList(growable: false),
    );
  }

  Future<void> deleteStoredMessagesByIds(
    String peerId,
    List<String> messageIds,
  ) {
    return storage.deleteChatMessagesByIds(peerId, messageIds);
  }

  Future<bool> hasMoreMessages(String peerId, int loadedCount) async {
    final index = await storage.loadMessagesIndex(peerId);
    final totalMessages = index['totalMessages'] as int? ?? 0;
    developer.log(
      '[chat] hasMore peer=$peerId total=$totalMessages loaded=$loadedCount '
      'result=${totalMessages > loadedCount}',
      name: 'chat',
    );
    return totalMessages > loadedCount;
  }

  Future<List<Message>> readOlderMessages(
    String peerId,
    int endIndex,
    int limit,
  ) async {
    final raw = await storage.loadMessagesPage(peerId, endIndex, limit);
    developer.log(
      '[chat] readOlder peer=$peerId offset=$endIndex limit=$limit fetched=${raw.length}',
      name: 'chat',
    );
    return raw.map(Message.fromJson).toList(growable: true);
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return storage.getMessageOffsetFromNewest(peerId, messageId);
  }

  void refreshSummaryFromMessages(Chat chat, List<Message> messages) {
    chat.previewMessage = messages.isEmpty ? null : messages.last;
    chat.unreadCount = messages
        .where((message) => message.incoming && !message.isRead)
        .length;
  }

  Future<void> persistLoadedChat(Chat chat) async {
    refreshSummaryFromMessages(chat, chat.messages);
    await persistChatSummary(chat);
    await _persistLoadedMessages(chat);
  }

  Future<void> appendMessage(String peerId, Message message) async {
    final chat = ensureChat(peerId);
    if (chat.messagesLoaded) {
      chat.messages.add(message);
      refreshSummaryFromMessages(chat, chat.messages);
      await persistChatSummary(chat);
      await upsertStoredMessages(peerId, <Message>[message]);
      return;
    }

    final stored = await readStoredMessages(peerId);
    stored.add(message);
    await writeStoredMessages(peerId, stored);
    chat.previewMessage = message;
    if (message.incoming && !message.isRead) {
      chat.unreadCount += 1;
    }
    await persistChatSummary(chat);
  }

  Future<bool> removeMessage(
    String peerId,
    String messageId, {
    required Chat? loadedChat,
  }) async {
    final chat = loadedChat ?? await _loadSummaryChat(peerId);

    if (chat.messagesLoaded) {
      final before = chat.messages.length;
      chat.messages.removeWhere((message) => message.id == messageId);
      if (chat.messages.length == before) {
        return false;
      }
      await deleteStoredMessagesByIds(peerId, <String>[messageId]);
      await _refreshSummaryFromStorage(chat);
      await persistChatSummary(chat);
      return true;
    }

    final stored = await readStoredMessages(peerId);
    final before = stored.length;
    stored.removeWhere((message) => message.id == messageId);
    if (stored.length == before) {
      return false;
    }
    await deleteStoredMessagesByIds(peerId, <String>[messageId]);
    await _refreshSummaryFromStorage(chat);
    await persistChatSummary(chat);
    return true;
  }

  Future<Chat> _loadSummaryChat(String peerId) async {
    final raw = await storage.getChatSummary(peerId);
    if (raw != null) {
      try {
        return Chat.fromJson(Map<String, dynamic>.from(raw));
      } catch (_) {
        // Fall through to synthetic chat.
      }
    }
    return Chat(peerId: peerId, name: peerId, messagesLoaded: false);
  }

  Future<Message?> findMessage(
    String peerId,
    String messageId, {
    required Chat? loadedChat,
  }) async {
    if (loadedChat?.messagesLoaded == true) {
      for (final message in loadedChat!.messages) {
        if (message.id == messageId) {
          return message;
        }
      }
      return null;
    }

    final stored = await readStoredMessages(peerId);
    for (final message in stored) {
      if (message.id == messageId) {
        return message;
      }
    }
    return null;
  }

  Future<void> replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) async {
    final chat = ensureChat(peerId);

    if (chat.messagesLoaded) {
      for (var i = 0; i < chat.messages.length; i++) {
        final current = chat.messages[i];
        if (current.id != messageId) {
          continue;
        }
        chat.messages[i] = transform(current);
        await upsertStoredMessages(peerId, <Message>[chat.messages[i]]);
        await _refreshSummaryAfterMutation(chat);
        await persistChatSummary(chat);
        return;
      }
      return;
    }

    final stored = await readStoredMessages(peerId);
    for (var i = 0; i < stored.length; i++) {
      final current = stored[i];
      if (current.id != messageId) {
        continue;
      }
      stored[i] = transform(current);
      await upsertStoredMessages(peerId, <Message>[stored[i]]);
      await _refreshSummaryFromStorage(chat);
      await persistChatSummary(chat);
      return;
    }
  }

  Future<void> _persistLoadedMessages(Chat chat) async {
    if (chat.hasMoreMessages) {
      await upsertStoredMessages(chat.peerId, chat.messages);
      return;
    }
    await writeStoredMessages(chat.peerId, chat.messages);
  }

  Future<void> _refreshSummaryAfterMutation(Chat chat) async {
    if (!chat.hasMoreMessages) {
      refreshSummaryFromMessages(chat, chat.messages);
      return;
    }

    await _refreshSummaryFromStorage(chat);
  }

  Future<void> _refreshSummaryFromStorage(Chat chat) async {
    final stored = await readStoredMessages(chat.peerId);
    refreshSummaryFromMessages(chat, stored);
  }
}
