import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/turn/turn_priority_failure_policy.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

void main() {
  const primary = TurnServerConfig(
    url: 'turn:primary.example:3478?transport=tcp',
    username: 'peerlink',
    password: 'secret',
    priority: 200,
  );

  test('applies bounded penalty and restores base priority after success', () {
    final policy = TurnPriorityFailurePolicy()
      ..replaceBasePriorities(const [primary]);

    policy
      ..reportFailure(primary.url, at: DateTime.utc(2026, 9, 22))
      ..reportFailure(primary.url, at: DateTime.utc(2026, 9, 22, 0, 1));

    expect(policy.priorityFor(primary.url), 0);
    expect(policy.failureCountFor(primary.url), 2);
    expect(policy.lastFailureFor(primary.url), DateTime.utc(2026, 9, 22, 0, 1));

    policy.reportSuccess(primary.url);

    expect(policy.priorityFor(primary.url), 200);
    expect(policy.failureCountFor(primary.url), 0);
    expect(policy.lastFailureFor(primary.url), isNull);
  });

  test(
    'replace clears stale priorities while reset preserves configured base',
    () {
      final policy = TurnPriorityFailurePolicy()
        ..replaceBasePriorities(const [primary])
        ..reportFailure(primary.url);

      policy.reset();
      expect(policy.priorityFor(primary.url), 200);

      policy.replaceBasePriorities(const []);
      expect(policy.priorityFor(primary.url), 100);
    },
  );
}
