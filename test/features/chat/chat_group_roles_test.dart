import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/chat/domain/chat.dart';

void main() {
  test('preserves additive group administrator peer ids', () {
    final chat = Chat(
      peerId: 'group:roles',
      name: 'Roles',
      isGroup: true,
      memberPeerIds: <String>['owner', 'admin'],
      adminPeerIds: <String>['admin'],
      ownerPeerId: 'owner',
    );

    final restored = Chat.fromJson(chat.toJson());

    expect(restored.ownerPeerId, 'owner');
    expect(restored.adminPeerIds, <String>['admin']);
  });
}
