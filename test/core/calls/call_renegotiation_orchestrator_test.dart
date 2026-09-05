import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_renegotiation_orchestrator.dart';

void main() {
  group('CallRenegotiationOrchestrator', () {
    test('queues latest reason while renegotiation is in progress', () async {
      final blocker = Completer<void>();
      final reasons = <String>[];
      final logs = <String>[];
      late final CallRenegotiationOrchestrator orchestrator;
      orchestrator = CallRenegotiationOrchestrator(
        log: logs.add,
        runRenegotiation: (reason) async {
          reasons.add(reason);
          if (reason == 'first') {
            await orchestrator.run('second');
            await blocker.future;
          }
        },
      );

      final first = orchestrator.run('first');
      await Future<void>.delayed(Duration.zero);

      expect(orchestrator.inProgress, isTrue);
      expect(reasons, <String>['first']);
      expect(
        logs,
        contains('renegotiation:queued already-in-progress reason="second"'),
      );

      blocker.complete();
      await first;

      expect(orchestrator.inProgress, isFalse);
      expect(reasons, <String>['first', 'second']);
    });
  });
}
