import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/ui/screens/chat_screen_mime_type.dart';
import 'package:peerlink/ui/screens/chat_screen_unread_target_resolver.dart';
import 'package:test/test.dart';

void main() {
  test('ChatScreenMimeType resolves image mime type by filename', () {
    expect(
      ChatScreenMimeType.forPath('avatar.png', 'fallback.jpg'),
      'image/png',
    );
    expect(ChatScreenMimeType.forPath('', 'avatar.webp'), 'image/webp');
    expect(
      ChatScreenMimeType.forPath('avatar.jpeg', 'fallback.png'),
      'image/jpeg',
    );
  });

  test('ChatScreenUnreadTargetResolver finds message targets', () {
    final messages = [
      _message('m1', incoming: true, isRead: true),
      _message('m2', incoming: true, isRead: false),
      _message('m3', incoming: false, isRead: true),
    ];

    expect(
      ChatScreenUnreadTargetResolver.containsMessage(messages, 'm2'),
      isTrue,
    );
    expect(
      ChatScreenUnreadTargetResolver.firstUnreadMessageId(
        messages,
        isInitialUnreadAnchor: (message) => message.incoming && !message.isRead,
      ),
      'm2',
    );
  });
}

Message _message(String id, {required bool incoming, required bool isRead}) {
  return Message(
    id: id,
    peerId: 'peer',
    text: id,
    incoming: incoming,
    timestamp: DateTime(2026),
    isRead: isRead,
  );
}
