import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_connection_state_controller.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

void main() {
  group('CallConnectionStateController', () {
    test('notifyConnected waits until ice and remote track are both ready', () {
      final logs = <String>[];
      final connectedModes = <TransportMode>[];
      var connected = false;
      var iceConnected = true;
      var remoteTrackSeen = false;
      var mediaFallbackArmed = 0;

      final controller = CallConnectionStateController(
        log: logs.add,
        getMode: () => TransportMode.turn,
        getConnected: () => connected,
        setConnected: (value) => connected = value,
        getIceConnected: () => iceConnected,
        getRemoteTrackSeen: () => remoteTrackSeen,
        getRemoteAudioFlowSeen: () => false,
        onConnected: connectedModes.add,
        armMediaFlowFallback: () => mediaFallbackArmed++,
      );

      controller.notifyConnected();

      expect(connected, isFalse);
      expect(connectedModes, isEmpty);
      expect(mediaFallbackArmed, 0);
      expect(logs.single, contains('connected:waiting'));
    });

    test('notifyConnected transitions once and arms media fallback', () {
      final connectedModes = <TransportMode>[];
      var connected = false;
      var mediaFallbackArmed = 0;

      final controller = CallConnectionStateController(
        log: (_) {},
        getMode: () => TransportMode.turn,
        getConnected: () => connected,
        setConnected: (value) => connected = value,
        getIceConnected: () => true,
        getRemoteTrackSeen: () => true,
        getRemoteAudioFlowSeen: () => true,
        onConnected: connectedModes.add,
        armMediaFlowFallback: () => mediaFallbackArmed++,
      );

      controller.notifyConnected();
      controller.notifyConnected();

      expect(connected, isTrue);
      expect(connectedModes, equals(<TransportMode>[TransportMode.turn]));
      expect(mediaFallbackArmed, 1);
    });
  });
}
