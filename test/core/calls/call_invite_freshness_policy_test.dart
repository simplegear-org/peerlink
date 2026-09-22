import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_invite_freshness_policy.dart';

void main() {
  group('CallInviteFreshnessPolicy', () {
    final now = DateTime.utc(2026, 9, 22, 8, 24);
    final policy = CallInviteFreshnessPolicy(
      maxAge: const Duration(minutes: 2),
      now: () => now,
    );

    test('rejects delayed timestamp-based call IDs', () {
      final callId = now
          .subtract(const Duration(minutes: 3))
          .microsecondsSinceEpoch
          .toString();

      expect(policy.isExpired(callId), isTrue);
    });

    test('accepts current, future, and legacy call IDs', () {
      expect(policy.isExpired(now.microsecondsSinceEpoch.toString()), isFalse);
      expect(
        policy.isExpired(
          now.add(const Duration(minutes: 1)).microsecondsSinceEpoch.toString(),
        ),
        isFalse,
      );
      expect(policy.isExpired('legacy-call-id'), isFalse);
    });
  });
}
