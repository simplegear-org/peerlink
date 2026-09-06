import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peerlink_storage_test_');
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('writes and reads chat messages from real SQLite storage', () async {
    const peerId = 'peer-a';
    final storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    const messageStore = ChatDatabaseChatMessageStore();

    final messages = <Message>[
      Message(
        id: 'm1',
        peerId: peerId,
        text: 'hello',
        incoming: true,
        timestamp: DateTime.utc(2026, 1, 1, 10),
        isRead: false,
      ),
      Message(
        id: 'm2',
        peerId: peerId,
        text: 'world',
        incoming: false,
        timestamp: DateTime.utc(2026, 1, 1, 11),
        status: MessageStatus.sending,
        receiptStatus: MessageReceiptStatus.delivered,
        deliveredAtByPeer: const <String, int>{'peer-b': 101},
        readAtByPeer: const <String, int>{},
        replyToMessageId: 'm1',
        replyToSenderPeerId: peerId,
        replyToTextPreview: 'hello',
      ),
    ];

    await messageStore.write(
      peerId,
      messages.map((message) => message.toPersistentJson()).toList(),
    );

    await StorageService.resetForTesting();
    final reopened = StorageService();
    await reopened.initForTesting(rootDirectory: root);

    final stored = await messageStore.read(peerId);

    expect(stored.map((json) => json['id']), ['m1', 'm2']);
    expect(stored[0]['text'], 'hello');
    expect(stored[0]['isRead'], isFalse);
    expect(stored[1]['status'], MessageStatus.sending.name);
    expect(stored[1]['receiptStatus'], MessageReceiptStatus.delivered.name);
    expect(stored[1]['deliveredAtByPeer'], {'peer-b': 101});
    expect(stored[1]['replyToMessageId'], 'm1');
  });

  test('keeps equal message ids isolated between different chats', () async {
    final storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    const messageStore = ChatDatabaseChatMessageStore();

    await messageStore.upsert('peer-a', [
      Message(
        id: 'same-message-id',
        peerId: 'peer-a',
        text: 'from peer-a',
        incoming: true,
        timestamp: DateTime.utc(2026, 1, 1, 10),
      ).toPersistentJson(),
    ]);
    await messageStore.upsert('peer-b', [
      Message(
        id: 'same-message-id',
        peerId: 'peer-b',
        text: 'from peer-b',
        incoming: true,
        timestamp: DateTime.utc(2026, 1, 1, 11),
      ).toPersistentJson(),
    ]);

    final peerA = await messageStore.read('peer-a');
    final peerB = await messageStore.read('peer-b');

    expect(peerA, hasLength(1));
    expect(peerA.single['text'], 'from peer-a');
    expect(peerB, hasLength(1));
    expect(peerB.single['text'], 'from peer-b');
  });
}
