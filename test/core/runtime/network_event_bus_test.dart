import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/network_event.dart';
import 'package:peerlink/core/runtime/network_event_bus.dart';

void main() {
  test(
    'emitAndWait reports false when no durable handler is registered',
    () async {
      final bus = NetworkEventBus();
      addTearDown(bus.dispose);

      final delivered = await bus.emitAndWait(
        NetworkEvent(type: NetworkEventType.messageReceived, payload: 'hello'),
      );

      expect(delivered, isFalse);
    },
  );

  test('emitAndWait waits for registered durable handlers', () async {
    final bus = NetworkEventBus();
    addTearDown(bus.dispose);
    final handledPayloads = <Object?>[];

    bus.addAwaitableHandler((event) async {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      handledPayloads.add(event.payload);
    });

    final delivered = await bus.emitAndWait(
      NetworkEvent(type: NetworkEventType.messageReceived, payload: 'photo'),
    );

    expect(delivered, isTrue);
    expect(handledPayloads, <Object?>['photo']);
  });
}
