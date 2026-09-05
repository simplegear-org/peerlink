import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_session_epoch.dart';

void main() {
  group('CallSessionEpoch', () {
    test('starts at zero and increments immutably', () {
      final initial = CallSessionEpoch.initial();
      final next = initial.next();
      final next2 = next.next();

      expect(initial.value, 0);
      expect(next.value, 1);
      expect(next2.value, 2);
      expect(initial, CallSessionEpoch.initial());
      expect(next, isNot(initial));
    });
  });
}
