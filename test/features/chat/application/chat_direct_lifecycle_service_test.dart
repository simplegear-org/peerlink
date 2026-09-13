import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/chat/application/chat_direct_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';

void main() {
  test('creates one direct chat and reuses it when opened again', () async {
    final chats = <String, Chat>{};
    final persisted = <Chat>[];
    final scheduled = <String>[];
    final notified = <String>[];
    final service = ChatDirectLifecycleService(
      facade: _FakeChatRuntime(),
      chats: chats,
      contactNameFor: (peerId, {fallback}) =>
          peerId == 'peer-a' ? 'Alice' : (fallback ?? peerId),
      persistChatSummary: (chat) async => persisted.add(chat),
      schedulePersistChatSummary: scheduled.add,
      notifyMessageUpdated: notified.add,
      setStatus: (peerId, status, {error}) {},
    );

    final created = await service.createDirectChat(
      peerId: 'peer-a',
      name: 'peer-a',
    );
    final ensured = await service.createDirectChat(
      peerId: 'peer-a',
      name: 'Alice',
    );
    final opened = service.openChat('peer-a', 'Alice');

    expect(chats, hasLength(1));
    expect(identical(created, ensured), isTrue);
    expect(identical(created, opened), isTrue);
    expect(created.name, 'Alice');
    expect(created.isGroup, isFalse);
    expect(persisted, hasLength(2));
    expect(notified, <String>['peer-a', 'peer-a']);
    expect(scheduled, <String>['peer-a']);
  });
}

class _FakeChatRuntime implements ChatRuntimeApi {
  @override
  String get peerId => 'local-peer';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
