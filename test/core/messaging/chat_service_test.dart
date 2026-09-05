import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/chat_service.dart';

void main() {
  test('resolveIncomingChatTargetPeerId uses groupId for group envelopes', () {
    final targetPeerId = resolveIncomingChatTargetPeerId(
      sourcePeerId: 'sender-peer',
      groupId: 'group:123',
    );

    expect(targetPeerId, 'group:123');
  });

  test('resolveIncomingChatTargetPeerId falls back to source peer', () {
    final targetPeerId = resolveIncomingChatTargetPeerId(
      sourcePeerId: 'sender-peer',
      groupId: '   ',
    );

    expect(targetPeerId, 'sender-peer');
  });

  test('ChatMessage preserves senderPeerId separately from target peer', () {
    final message = ChatMessage(
      id: 'm1',
      peerId: 'group:123',
      senderPeerId: 'sender-peer',
      text: 'hello',
    );

    expect(message.peerId, 'group:123');
    expect(message.senderPeerId, 'sender-peer');
    expect(ChatMessage.fromJson(message.toJson()).senderPeerId, 'sender-peer');
  });
}
