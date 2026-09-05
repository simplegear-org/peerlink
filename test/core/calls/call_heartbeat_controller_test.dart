import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_heartbeat_controller.dart';

class _SentSignal {
  const _SentSignal({
    required this.peerId,
    required this.type,
    required this.data,
  });

  final String peerId;
  final String type;
  final Map<String, dynamic> data;
}

void main() {
  group('CallHeartbeatController', () {
    test('sends heartbeat immediately and on interval', () {
      fakeAsync((async) {
        final sent = <_SentSignal>[];
        final controller = CallHeartbeatController(
          interval: const Duration(seconds: 1),
          sendSignal: (peerId, type, data) async {
            sent.add(_SentSignal(peerId: peerId, type: type, data: data));
          },
          isSignalingConnected: () => true,
          onHeartbeatMissed: (_) async {},
          log: (_) {},
        );

        controller.start(peerId: 'peer-a', callId: 'call-a');
        async.flushMicrotasks();

        expect(sent, hasLength(1));
        expect(sent.single.peerId, 'peer-a');
        expect(sent.single.type, 'call_heartbeat');
        expect(sent.single.data['callId'], 'call-a');
        expect(sent.single.data['seq'], 1);

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(sent, hasLength(2));
        expect(sent.last.data['seq'], 2);

        controller.stop();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(sent, hasLength(2));
      });
    });

    test('does not trigger recovery until remote heartbeat was seen', () {
      fakeAsync((async) {
        final missed = <String>[];
        final controller = CallHeartbeatController(
          interval: const Duration(seconds: 1),
          sendSignal: (_, _, _) async {},
          isSignalingConnected: () => true,
          onHeartbeatMissed: (reason) async {
            missed.add(reason);
          },
          log: (_) {},
        );

        controller.start(peerId: 'peer-a', callId: 'call-a');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 6));
        async.flushMicrotasks();

        expect(missed, isEmpty);
      });
    });

    test('warns before recovery after remote heartbeat is missed', () {
      fakeAsync((async) {
        final missed = <String>[];
        final logs = <String>[];
        var now = DateTime(2026);
        final controller = CallHeartbeatController(
          interval: const Duration(seconds: 1),
          sendSignal: (_, _, _) async {},
          isSignalingConnected: () => true,
          onHeartbeatMissed: (reason) async {
            missed.add(reason);
          },
          log: logs.add,
          now: () => now,
        );

        controller.start(peerId: 'peer-a', callId: 'call-a');
        controller.markRemoteHeartbeat(
          peerId: 'peer-a',
          callId: 'call-a',
          seq: 1,
          sentAtMs: now.millisecondsSinceEpoch,
        );

        now = now.add(const Duration(seconds: 4));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        expect(logs, contains(contains('callHeartbeat missed')));
        expect(missed, isEmpty);

        now = now.add(const Duration(seconds: 9));
        async.elapse(const Duration(seconds: 9));
        async.flushMicrotasks();

        expect(missed, hasLength(1));
        expect(missed.single, contains('Call heartbeat missed'));

        now = now.add(const Duration(seconds: 4));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        expect(missed, hasLength(1));
      });
    });

    test('defers recovery while media was recently active', () {
      fakeAsync((async) {
        final missed = <String>[];
        final logs = <String>[];
        var mediaActive = true;
        var now = DateTime(2026);
        final controller = CallHeartbeatController(
          interval: const Duration(seconds: 1),
          sendSignal: (_, _, _) async {},
          isSignalingConnected: () => true,
          onHeartbeatMissed: (reason) async {
            missed.add(reason);
          },
          log: logs.add,
          isMediaRecentlyActive: () => mediaActive,
          now: () => now,
        );

        controller.start(peerId: 'peer-a', callId: 'call-a');
        controller.markRemoteHeartbeat(
          peerId: 'peer-a',
          callId: 'call-a',
          seq: 1,
          sentAtMs: now.millisecondsSinceEpoch,
        );

        now = now.add(const Duration(seconds: 13));
        async.elapse(const Duration(seconds: 13));
        async.flushMicrotasks();

        expect(missed, isEmpty);
        expect(logs, contains(contains('recovery defer media-active')));

        mediaActive = false;
        now = now.add(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(missed, hasLength(1));
      });
    });

    test('skips sending while signaling is disconnected', () {
      fakeAsync((async) {
        final sent = <_SentSignal>[];
        final controller = CallHeartbeatController(
          interval: const Duration(seconds: 1),
          sendSignal: (peerId, type, data) async {
            sent.add(_SentSignal(peerId: peerId, type: type, data: data));
          },
          isSignalingConnected: () => false,
          onHeartbeatMissed: (_) async {},
          log: (_) {},
        );

        controller.start(peerId: 'peer-a', callId: 'call-a');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(sent, isEmpty);
      });
    });
  });
}
