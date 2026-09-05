import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/push/push_event_factory.dart';

void main() {
  group('PushEventFactory', () {
    const factory = PushEventFactory();

    test('call invite uses both standard and voip delivery', () {
      final draft = factory.buildCallInvite(
        callerUserId: 'caller',
        calleeUserId: 'callee',
        callId: 'call-1',
        mediaType: CallMediaType.audio,
      );

      expect(draft.delivery.standard, isTrue);
      expect(draft.delivery.voip, isTrue);
    });

    test('call end uses both standard and voip delivery', () {
      final draft = factory.buildCallEnd(
        callerUserId: 'caller',
        calleeUserId: 'callee',
        callId: 'call-1',
      );

      expect(draft.delivery.standard, isTrue);
      expect(draft.delivery.voip, isTrue);
    });
  });
}
