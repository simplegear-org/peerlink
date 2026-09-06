import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';

class _FakeStorageService extends StorageService {}

class _FakeChatSummaryStore implements ChatSummaryStore {
  final Map<String, Map<String, dynamic>> summaries =
      <String, Map<String, dynamic>>{};

  @override
  Future<List<Map<String, dynamic>>> loadAll() async {
    return summaries.values
        .map((summary) => Map<String, dynamic>.from(summary))
        .toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>?> get(String peerId) async {
    final summary = summaries[peerId];
    return summary == null ? null : Map<String, dynamic>.from(summary);
  }

  @override
  Future<void> save(String peerId, Map<String, dynamic> json) async {
    summaries[peerId] = Map<String, dynamic>.from(json);
  }

  @override
  Future<void> delete(String peerId) async {
    summaries.remove(peerId);
  }

  @override
  Future<int> unreadMessagesCount() async {
    return summaries.values.fold<int>(
      0,
      (sum, summary) => sum + (summary['unreadCount'] as int? ?? 0),
    );
  }
}

class _FakeChatMessageStore implements ChatMessageStore {
  final Map<String, List<Map<String, dynamic>>> messages =
      <String, List<Map<String, dynamic>>>{};

  @override
  Future<List<Map<String, dynamic>>> read(String peerId) async {
    return List<Map<String, dynamic>>.from(
      messages[peerId] ?? const <Map<String, dynamic>>[],
    );
  }

  @override
  Future<void> write(
    String peerId,
    List<Map<String, dynamic>> nextMessages,
  ) async {
    messages[peerId] = List<Map<String, dynamic>>.from(nextMessages);
  }

  @override
  Future<void> upsert(
    String peerId,
    List<Map<String, dynamic>> nextMessages,
  ) async {
    final existing = List<Map<String, dynamic>>.from(
      messages[peerId] ?? const <Map<String, dynamic>>[],
    );
    for (final next in nextMessages) {
      final id = next['id'] as String;
      final index = existing.indexWhere((item) => item['id'] == id);
      if (index == -1) {
        existing.add(next);
      } else {
        existing[index] = next;
      }
    }
    existing.sort(
      (a, b) => (a['timestamp'] as String).compareTo(b['timestamp'] as String),
    );
    messages[peerId] = existing;
  }

  @override
  Future<int> count(String peerId) async {
    return messages[peerId]?.length ?? 0;
  }

  @override
  Future<List<Map<String, dynamic>>> readPage(
    String peerId,
    int offset,
    int limit,
  ) async {
    final existing = messages[peerId] ?? const <Map<String, dynamic>>[];
    final start = existing.length - offset - limit;
    final end = existing.length - offset;
    return List<Map<String, dynamic>>.from(
      existing.sublist(start < 0 ? 0 : start, end < 0 ? 0 : end),
    );
  }

  @override
  Future<int?> offsetFromNewest(String peerId, String messageId) async {
    final existing = messages[peerId] ?? const <Map<String, dynamic>>[];
    final index = existing.indexWhere((item) => item['id'] == messageId);
    return index == -1 ? null : existing.length - index - 1;
  }

  @override
  Future<void> deleteByIds(String peerId, List<String> messageIds) async {
    messages[peerId]?.removeWhere((item) => messageIds.contains(item['id']));
  }
}

void main() {
  test(
    'initial load keeps latest window when unread exists in older history',
    () async {
      const peerId = 'peer-a';
      final storage = _FakeStorageService();
      final messageStore = _FakeChatMessageStore();
      final summaryStore = _FakeChatSummaryStore();
      final chat = Chat(peerId: peerId, name: peerId, hasMoreMessages: true);
      final allMessages = List<Message>.generate(
        80,
        (index) => Message(
          id: 'm$index',
          peerId: peerId,
          text: 'message $index',
          incoming: index == 10,
          timestamp: DateTime.utc(2026, 1, 1, 0, index),
          isRead: index != 10,
        ),
      );
      messageStore.messages[peerId] = allMessages
          .map((message) => message.toPersistentJson())
          .toList(growable: false);

      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chat,
        persistChatSummary: (chat) =>
            summaryStore.save(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (message) => message.incoming && !message.isRead,
        messageStore: messageStore,
        summaryStore: summaryStore,
      );

      final loaded = await repository.loadInitialMessages(peerId, 50);

      expect(loaded.first.id, 'm30');
      expect(loaded.last.id, 'm79');
    },
  );

  test('firstInitialUnreadMessageId returns persisted unread anchor', () async {
    const peerId = 'peer-a';
    final storage = _FakeStorageService();
    final messageStore = _FakeChatMessageStore();
    final summaryStore = _FakeChatSummaryStore();
    final chat = Chat(peerId: peerId, name: peerId, hasMoreMessages: true);
    final allMessages = List<Message>.generate(
      3,
      (index) => Message(
        id: 'm$index',
        peerId: peerId,
        text: 'message $index',
        incoming: true,
        timestamp: DateTime.utc(2026, 1, 1, 0, index),
        isRead: index != 1,
      ),
    );
    messageStore.messages[peerId] = allMessages
        .map((message) => message.toPersistentJson())
        .toList(growable: false);

    final repository = ChatRepository(
      storage: storage,
      ensureChat: (id, {fallbackName}) => chat,
      persistChatSummary: (chat) =>
          summaryStore.save(chat.peerId, chat.toJson()),
      isInitialUnreadAnchor: (message) => message.incoming && !message.isRead,
      messageStore: messageStore,
      summaryStore: summaryStore,
    );

    expect(await repository.firstInitialUnreadMessageId(peerId), 'm1');
  });

  test(
    'append preserves older messages when chat is partially loaded',
    () async {
      const peerId = 'peer-a';
      final storage = _FakeStorageService();
      final messageStore = _FakeChatMessageStore();
      final summaryStore = _FakeChatSummaryStore();
      final chat = Chat(peerId: peerId, name: peerId, hasMoreMessages: true);
      final allMessages = List<Message>.generate(
        60,
        (index) => Message(
          id: 'm$index',
          peerId: peerId,
          text: 'message $index',
          incoming: index.isEven,
          timestamp: DateTime.utc(2026, 1, 1, 0, index),
        ),
      );
      messageStore.messages[peerId] = allMessages
          .map((message) => message.toPersistentJson())
          .toList(growable: false);
      chat.messages = allMessages.sublist(10).toList(growable: true);
      chat.messagesLoaded = true;

      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chat,
        persistChatSummary: (chat) =>
            summaryStore.save(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (_) => false,
        messageStore: messageStore,
        summaryStore: summaryStore,
      );

      await repository.appendMessage(
        peerId,
        Message(
          id: 'm60',
          peerId: peerId,
          text: 'message 60',
          incoming: false,
          timestamp: DateTime.utc(2026, 1, 1, 1),
        ),
      );

      final storedIds = messageStore.messages[peerId]!
          .map((item) => item['id'] as String)
          .toList(growable: false);
      expect(storedIds, hasLength(61));
      expect(
        storedIds.take(10),
        List<String>.generate(10, (index) => 'm$index'),
      );
      expect(storedIds.last, 'm60');
    },
  );

  test(
    'replace preserves older messages when chat is partially loaded',
    () async {
      const peerId = 'peer-a';
      final storage = _FakeStorageService();
      final messageStore = _FakeChatMessageStore();
      final summaryStore = _FakeChatSummaryStore();
      final chat = Chat(peerId: peerId, name: peerId, hasMoreMessages: true);
      final allMessages = List<Message>.generate(
        60,
        (index) => Message(
          id: 'm$index',
          peerId: peerId,
          text: 'message $index',
          incoming: index.isEven,
          timestamp: DateTime.utc(2026, 1, 1, 0, index),
        ),
      );
      messageStore.messages[peerId] = allMessages
          .map((message) => message.toPersistentJson())
          .toList(growable: false);
      chat.messages = allMessages.sublist(10).toList(growable: true);
      chat.messagesLoaded = true;

      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chat,
        persistChatSummary: (chat) =>
            summaryStore.save(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (_) => false,
        messageStore: messageStore,
        summaryStore: summaryStore,
      );

      await repository.replaceMessage(
        peerId,
        'm59',
        (current) => Message(
          id: current.id,
          peerId: current.peerId,
          text: 'updated',
          incoming: current.incoming,
          timestamp: current.timestamp,
        ),
      );

      final stored = messageStore.messages[peerId]!;
      final storedIds = stored
          .map((item) => item['id'] as String)
          .toList(growable: false);
      expect(storedIds, hasLength(60));
      expect(
        storedIds.take(10),
        List<String>.generate(10, (index) => 'm$index'),
      );
      expect(stored.last['text'], 'updated');
    },
  );
}
