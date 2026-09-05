import 'package:peerlink/core/messaging/reliable_operation_id.dart';
import 'package:test/test.dart';

void main() {
  test('pendingMessage uses explicit direct and group prefixes', () {
    expect(
      ReliableOperationId.pendingMessage(
        isGroup: false,
        targetId: 'peer-1',
        messageId: 'm1',
      ),
      'direct:peer-1:m1',
    );
    expect(
      ReliableOperationId.pendingMessage(
        isGroup: true,
        targetId: 'group-1',
        messageId: 'm2',
      ),
      'group:group-1:m2',
    );
  });
}
