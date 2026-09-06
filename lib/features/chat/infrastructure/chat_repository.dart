// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'package:peerlink/core/runtime/storage_service.dart';

import '../domain/chat.dart';
import '../domain/message.dart';
import 'chat_database.dart';
import 'chat_summary_store.dart';

class ChatRepository {
  final StorageService storage;
  final Chat Function(String peerId, {String? fallbackName}) ensureChat;
  final Future<void> Function(Chat chat) persistChatSummary;
  final bool Function(Message message) isInitialUnreadAnchor;
  final ChatMessageStore _messageStore;
  final ChatSummaryStore _summaryStore;

  ChatRepository({
    required this.storage,
    required this.ensureChat,
    required this.persistChatSummary,
    required this.isInitialUnreadAnchor,
    ChatMessageStore? messageStore,
    ChatSummaryStore? summaryStore,
  }) : _messageStore = messageStore ?? const ChatDatabaseChatMessageStore(),
       _summaryStore = summaryStore ?? const ChatDatabaseSummaryStore();

  Future<List<Message>> loadInitialMessages(String peerId, int limit) async {
    final stored = await readStoredMessages(peerId);
    if (stored.length <= limit) {
      return stored;
    }

    final startIndex = stored.length - limit;
    if (startIndex <= 0) {
      return stored;
    }

    return List<Message>.from(stored.sublist(startIndex), growable: true);
  }

  Future<String?> firstInitialUnreadMessageId(String peerId) async {
    final stored = await readStoredMessages(peerId);
    for (final message in stored) {
      if (isInitialUnreadAnchor(message)) {
        return message.id;
      }
    }
    return null;
  }

  Future<List<Message>> readStoredMessages(String peerId) async {
    final raw = await _messageStore.read(peerId);
    return raw.map(Message.fromJson).toList(growable: true);
  }

  Future<void> writeStoredMessages(
    String peerId,
    List<Message> messages,
  ) async {
    await _messageStore.write(
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
    await _messageStore.upsert(
      peerId,
      messages
          .map((message) => message.toPersistentJson())
          .toList(growable: false),
    );
  }

  Future<void> deleteStoredMessagesByIds(
    String peerId,
    List<String> messageIds,
  ) async {
    if (messageIds.isEmpty) {
      return;
    }
    await _messageStore.deleteByIds(peerId, messageIds);
  }

  Future<bool> hasMoreMessages(String peerId, int loadedCount) async {
    final totalMessages = await _messageStore.count(peerId);
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
    final raw = await _messageStore.readPage(peerId, endIndex, limit);
    developer.log(
      '[chat] readOlder peer=$peerId offset=$endIndex limit=$limit fetched=${raw.length}',
      name: 'chat',
    );
    return raw.map(Message.fromJson).toList(growable: true);
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _messageStore.offsetFromNewest(peerId, messageId);
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
    final raw = await _summaryStore.get(peerId);
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

abstract class ChatMessageStore {
  Future<List<Map<String, dynamic>>> read(String peerId);

  Future<void> write(String peerId, List<Map<String, dynamic>> messages);

  Future<void> upsert(String peerId, List<Map<String, dynamic>> messages);

  Future<int> count(String peerId);

  Future<List<Map<String, dynamic>>> readPage(
    String peerId,
    int offset,
    int limit,
  );

  Future<int?> offsetFromNewest(String peerId, String messageId);

  Future<void> deleteByIds(String peerId, List<String> messageIds);
}

class ChatDatabaseChatMessageStore implements ChatMessageStore {
  const ChatDatabaseChatMessageStore();

  @override
  Future<List<Map<String, dynamic>>> read(String peerId) {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getMessagesAsJson(peerId),
      operation: 'readChatMessages($peerId)',
    );
  }

  @override
  Future<void> write(String peerId, List<Map<String, dynamic>> messages) async {
    final normalized = messages
        .map(
          (message) => _normalizeMessageForStorage(
            peerId,
            Map<String, dynamic>.from(message),
          ),
        )
        .toList(growable: false);
    await ChatDatabaseService.runWithRecovery(
      (database) => database.replaceMessages(peerId, normalized),
      operation: 'writeChatMessages($peerId)',
    );
  }

  @override
  Future<void> upsert(
    String peerId,
    List<Map<String, dynamic>> messages,
  ) async {
    if (messages.isEmpty) {
      return;
    }
    final normalized = messages
        .map(
          (message) => _normalizeMessageForStorage(
            peerId,
            Map<String, dynamic>.from(message),
          ),
        )
        .toList(growable: false);
    await ChatDatabaseService.runWithRecovery(
      (database) => database.upsertMessages(normalized),
      operation: 'upsertChatMessages($peerId)',
    );
  }

  @override
  Future<int> count(String peerId) {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.countMessages(peerId),
      operation: 'countMessages($peerId)',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> readPage(
    String peerId,
    int offset,
    int limit,
  ) {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getMessagesPageAsJson(peerId, offset, limit),
      operation: 'loadMessagesPage($peerId,$offset,$limit)',
    );
  }

  @override
  Future<int?> offsetFromNewest(String peerId, String messageId) {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getMessageOffsetFromNewest(peerId, messageId),
      operation: 'getMessageOffsetFromNewest($peerId,$messageId)',
    );
  }

  @override
  Future<void> deleteByIds(String peerId, List<String> messageIds) async {
    if (messageIds.isEmpty) {
      return;
    }
    await ChatDatabaseService.runWithRecovery(
      (database) => database.deleteMessagesByIds(peerId, messageIds),
      operation: 'deleteChatMessagesByIds($peerId)',
    );
  }

  Map<String, dynamic> _normalizeMessageForStorage(
    String peerId,
    Map<String, dynamic> message,
  ) {
    final normalized = Map<String, dynamic>.from(message);
    normalized['peerId'] = normalized['peerId'] ?? peerId;
    normalized['fileDataBase64'] = null;

    return normalized;
  }
}
