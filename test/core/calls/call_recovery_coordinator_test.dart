import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_recovery_coordinator.dart';

void main() {
  group('CallRecoveryCoordinator', () {
    test('heartbeat miss is diagnostic only', () {
      fakeAsync((async) {
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {},
          onFatal: (_) {},
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.heartbeatMissed,
            reason: 'missed',
          ),
        );
        async.flushMicrotasks();

        expect(logs.single, contains('diagnostic-only'));
      });
    });

    test('ice disconnect marks passive recovery without restart', () {
      fakeAsync((async) {
        final recoveryStates = <bool>[];
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {
            recoveryStates.add(recovering);
          },
          onFatal: (_) {},
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.iceDisconnected,
            reason: 'ICE disconnected',
          ),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();

        expect(recoveryStates, <bool>[true]);
        expect(logs.single, contains('passive-watch'));
      });
    });

    test('ice failure is passive even with recent media', () {
      fakeAsync((async) {
        final recoveryStates = <bool>[];
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {
            recoveryStates.add(recovering);
          },
          onFatal: (_) {},
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.mediaAdvanced,
            reason: 'stats',
          ),
        );
        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.iceFailed,
            reason: 'ICE failed',
          ),
        );
        async.flushMicrotasks();

        expect(recoveryStates, <bool>[true]);
        expect(logs.single, contains('passive-watch'));
      });
    });

    test('inbound media clears passive recovery', () {
      fakeAsync((async) {
        final recoveryStates = <bool>[];
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {
            recoveryStates.add(recovering);
          },
          onFatal: (_) {},
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.iceDisconnected,
            reason: 'ICE disconnected',
          ),
        );
        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.mediaAdvanced,
            reason: 'stats',
          ),
        );
        async.flushMicrotasks();

        expect(recoveryStates, <bool>[true, false]);
        expect(logs.last, contains('recovery:cleared'));
      });
    });

    test('live media flow stall marks recovery', () {
      fakeAsync((async) {
        final recoveryStates = <bool>[];
        final statuses = <String>[];
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {
            recoveryStates.add(recovering);
            statuses.add(status);
          },
          onFatal: (_) {},
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.liveMediaFlowStalled,
            reason: 'Live media stalled while ICE remained connected',
          ),
        );
        async.flushMicrotasks();

        expect(recoveryStates, <bool>[true]);
        expect(statuses.single, contains('Медиа поток прерван'));
        expect(logs.single, contains('media-recovery'));
      });
    });

    test('post ice flow stall remains diagnostic only', () {
      fakeAsync((async) {
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {},
          onFatal: (_) {},
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.postIceRecoveryFlowStalled,
            reason: 'ICE did not reconnect after recovery signaling',
          ),
        );
        async.flushMicrotasks();

        expect(logs.single, contains('diagnostic-only'));
      });
    });

    test('media ready timeout retries before fatal threshold', () {
      fakeAsync((async) {
        final fatals = <String>[];
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {},
          onFatal: fatals.add,
          now: () => async.getClock(DateTime(2026)).now(),
        );

        CallRecoveryDisposition? disposition;
        coordinator
            .observe(
              const CallRecoveryObservation(
                kind: CallRecoveryObservationKind.mediaReadyTimeout,
                reason: 'media not ready',
                attempt: CallRecoveryCoordinator.mediaReadyFailAttempt - 1,
              ),
            )
            .then((value) => disposition = value);
        async.flushMicrotasks();

        expect(disposition, CallRecoveryDisposition.retryLater);
        expect(fatals, isEmpty);
        expect(logs.single, contains('observe-and-retry'));
      });
    });

    test('media ready timeout becomes fatal at threshold', () {
      fakeAsync((async) {
        final fatals = <String>[];
        final logs = <String>[];
        final coordinator = CallRecoveryCoordinator(
          log: logs.add,
          onRecoveryStateChanged: ({required recovering, required status}) {},
          onFatal: fatals.add,
          now: () => async.getClock(DateTime(2026)).now(),
        );

        coordinator.observe(
          const CallRecoveryObservation(
            kind: CallRecoveryObservationKind.mediaReadyTimeout,
            reason: 'media not ready',
            attempt: CallRecoveryCoordinator.mediaReadyFailAttempt,
          ),
        );
        async.flushMicrotasks();

        expect(fatals, hasLength(1));
        expect(logs.single, contains('fatal-no-media-ready'));
      });
    });
  });
}
