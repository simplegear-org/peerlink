import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/incoming_call_bootstrap_policy.dart';

void main() {
  group('IncomingCallBootstrapPolicy', () {
    test('waits for runtime enrichment using bounded accept timeout', () async {
      const policy = IncomingCallBootstrapPolicy();
      final timeouts = <Duration>[];
      final logs = <String>[];

      await policy.waitForAcceptRuntimeEnrichment(
        waitForPendingRuntimeEnrichment: (timeout) async {
          timeouts.add(timeout);
        },
        log: logs.add,
      );

      expect(timeouts, hasLength(1));
      expect(timeouts.single, const Duration(seconds: 8));
      expect(logs.first, contains('incomingBootstrapPolicy:wait start'));
      expect(logs.last, contains('incomingBootstrapPolicy:wait done'));
    });
  });
}
