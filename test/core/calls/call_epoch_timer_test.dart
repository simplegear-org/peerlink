import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_epoch_timer.dart';

void main() {
  group('CallEpochTimer', () {
    test('suppresses callback when epoch changes before timer fires', () {
      fakeAsync((async) {
        var epoch = 1;
        var fired = false;
        var stale = false;

        CallEpochTimer.arm(
          duration: const Duration(seconds: 30),
          expectedEpoch: epoch,
          getCurrentEpoch: () => epoch,
          onCurrent: () {
            fired = true;
          },
          onStale: () {
            stale = true;
          },
        );

        epoch = 2;
        async.elapse(const Duration(seconds: 30));

        expect(fired, isFalse);
        expect(stale, isTrue);
      });
    });

    test('runs callback while epoch is still current', () {
      fakeAsync((async) {
        var epoch = 7;
        var fired = false;

        CallEpochTimer.arm(
          duration: const Duration(milliseconds: 10),
          expectedEpoch: epoch,
          getCurrentEpoch: () => epoch,
          onCurrent: () {
            fired = true;
          },
        );

        async.elapse(const Duration(milliseconds: 10));

        expect(fired, isTrue);
      });
    });
  });
}
