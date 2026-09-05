import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/reliable_pending_operation_store.dart';
import 'package:peerlink/core/messaging/reliable_retry_scheduler.dart';

ReliablePendingOperation _operation(String id) =>
    ReliablePendingOperation.directOrGroupPayload(
      operationId: 'direct:peer-a:$id',
      targetId: 'peer-a',
      payload: <String, dynamic>{'id': id},
      operationKind: ReliablePendingOperationKind.directPayload,
      recipients: null,
      messageId: id,
      forcePlain: false,
    );

void main() {
  test('retryDueOperations skips concurrent runs', () async {
    final logs = <String>[];
    final operation = _operation('message-1');
    final retryCompleter = Completer<bool>();
    var retryCalls = 0;

    final scheduler = ReliableRetryScheduler(
      isDisposed: () => false,
      isRelayEnabled: () => true,
      hasPendingOperations: () => true,
      pendingOperations: () => <ReliablePendingOperation>[operation],
      removeOperation: (_) async {},
      persistOperations: () async {},
      retryOperation: (_) {
        retryCalls += 1;
        return retryCompleter.future;
      },
      onError: (_, _) {},
      onGiveUp: (_) {},
      log: logs.add,
    );

    final firstRun = scheduler.retryDueOperations();
    await scheduler.retryDueOperations();
    retryCompleter.complete(false);
    await firstRun;

    expect(retryCalls, 1);
    expect(logs, contains('pending:retry skipped reason=in-progress'));
  });

  test('retryDueOperations caps due operations per tick', () async {
    final logs = <String>[];
    final operations = List<ReliablePendingOperation>.generate(
      5,
      (index) => _operation('message-$index'),
    );
    var retryCalls = 0;
    var persistCalls = 0;

    final scheduler = ReliableRetryScheduler(
      isDisposed: () => false,
      isRelayEnabled: () => true,
      hasPendingOperations: () => true,
      pendingOperations: () => operations,
      removeOperation: (_) async {},
      persistOperations: () async {
        persistCalls += 1;
      },
      retryOperation: (_) async {
        retryCalls += 1;
        return false;
      },
      onError: (_, _) {},
      onGiveUp: (_) {},
      log: logs.add,
      maxOperationsPerTick: 2,
    );

    await scheduler.retryDueOperations();

    expect(retryCalls, 2);
    expect(persistCalls, 2);
    expect(
      logs,
      contains(
        'pending:retry tick total=5 due=5 max=2 capped=true '
        'relayEnabled=true',
      ),
    );
  });

  test('retryDueOperations gives up after max attempts', () async {
    final logs = <String>[];
    final operation = _operation('message-1');
    final removed = <String>[];
    final givenUp = <ReliablePendingOperation>[];
    var retryCalls = 0;

    final scheduler = ReliableRetryScheduler(
      isDisposed: () => false,
      isRelayEnabled: () => true,
      hasPendingOperations: () => true,
      pendingOperations: () => <ReliablePendingOperation>[operation],
      removeOperation: (operationId) async {
        removed.add(operationId);
      },
      persistOperations: () async {},
      retryOperation: (_) async {
        retryCalls += 1;
        return false;
      },
      onError: (_, _) {},
      onGiveUp: givenUp.add,
      log: logs.add,
      maxAttempts: 3,
    );

    await scheduler.retryDueOperations();
    operation.nextAttemptMs = 0;
    await scheduler.retryDueOperations();
    operation.nextAttemptMs = 0;
    await scheduler.retryDueOperations();

    expect(retryCalls, 3);
    expect(removed, <String>[operation.operationId]);
    expect(givenUp, <ReliablePendingOperation>[operation]);
    expect(logs.any((item) => item.startsWith('pending:retry giveup')), isTrue);
  });

  test(
    'retryDueOperations removes restored operation that exceeded attempts',
    () async {
      final logs = <String>[];
      final operation = _operation('message-1')..attempts = 4;
      final removed = <String>[];
      final givenUp = <ReliablePendingOperation>[];
      var retryCalls = 0;

      final scheduler = ReliableRetryScheduler(
        isDisposed: () => false,
        isRelayEnabled: () => true,
        hasPendingOperations: () => true,
        pendingOperations: () => <ReliablePendingOperation>[operation],
        removeOperation: (operationId) async {
          removed.add(operationId);
        },
        persistOperations: () async {},
        retryOperation: (_) async {
          retryCalls += 1;
          return false;
        },
        onError: (_, _) {},
        onGiveUp: givenUp.add,
        log: logs.add,
        maxAttempts: 3,
      );

      await scheduler.retryDueOperations();

      expect(retryCalls, 0);
      expect(removed, <String>[operation.operationId]);
      expect(givenUp, <ReliablePendingOperation>[operation]);
      expect(
        logs.any((item) => item.contains('reason=max-attempts-before-send')),
        isTrue,
      );
    },
  );
}
