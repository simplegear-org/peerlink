import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';

class _FakeStorageService extends StorageService {
  final Map<String, List<Map<String, dynamic>>> messages =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, Map<String, dynamic>> summaries =
      <String, Map<String, dynamic>>{};

  @override
  Future<List<Map<String, dynamic>>> readChatMessages(String peerId) async {
    return List<Map<String, dynamic>>.from(
      messages[peerId] ?? const <Map<String, dynamic>>[],
    );
  }

  @override
  Future<void> writeChatMessages(
    String peerId,
    List<Map<String, dynamic>> nextMessages,
  ) async {
    messages[peerId] = List<Map<String, dynamic>>.from(nextMessages);
  }

  @override
  Future<void> upsertChatMessages(
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
  Future<void> deleteChatMessagesByIds(
    String peerId,
    List<String> messageIds,
  ) async {
    messages[peerId]?.removeWhere((item) => messageIds.contains(item['id']));
  }

  @override
  Future<void> saveChatSummaryMap(
    String peerId,
    Map<String, dynamic> json,
  ) async {
    summaries[peerId] = Map<String, dynamic>.from(json);
  }
}

void main() {
  test(
    'initial load keeps latest window when unread exists in older history',
    () async {
      const peerId = 'peer-a';
      final storage = _FakeStorageService();
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
      storage.messages[peerId] = allMessages
          .map((message) => message.toPersistentJson())
          .toList(growable: false);

      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chat,
        persistChatSummary: (chat) =>
            storage.saveChatSummaryMap(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (message) => message.incoming && !message.isRead,
      );

      final loaded = await repository.loadInitialMessages(peerId, 50);

      expect(loaded.first.id, 'm30');
      expect(loaded.last.id, 'm79');
    },
  );

  test('firstInitialUnreadMessageId returns persisted unread anchor', () async {
    const peerId = 'peer-a';
    final storage = _FakeStorageService();
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
    storage.messages[peerId] = allMessages
        .map((message) => message.toPersistentJson())
        .toList(growable: false);

    final repository = ChatRepository(
      storage: storage,
      ensureChat: (id, {fallbackName}) => chat,
      persistChatSummary: (chat) =>
          storage.saveChatSummaryMap(chat.peerId, chat.toJson()),
      isInitialUnreadAnchor: (message) => message.incoming && !message.isRead,
    );

    expect(await repository.firstInitialUnreadMessageId(peerId), 'm1');
  });

  test(
    'append preserves older messages when chat is partially loaded',
    () async {
      const peerId = 'peer-a';
      final storage = _FakeStorageService();
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
      storage.messages[peerId] = allMessages
          .map((message) => message.toPersistentJson())
          .toList(growable: false);
      chat.messages = allMessages.sublist(10).toList(growable: true);
      chat.messagesLoaded = true;

      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chat,
        persistChatSummary: (chat) =>
            storage.saveChatSummaryMap(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (_) => false,
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

      final storedIds = storage.messages[peerId]!
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
      storage.messages[peerId] = allMessages
          .map((message) => message.toPersistentJson())
          .toList(growable: false);
      chat.messages = allMessages.sublist(10).toList(growable: true);
      chat.messagesLoaded = true;

      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chat,
        persistChatSummary: (chat) =>
            storage.saveChatSummaryMap(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (_) => false,
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

      final stored = storage.messages[peerId]!;
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
