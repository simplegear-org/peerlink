import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_heartbeat_controller.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_remote_control_handler.dart';
import 'package:peerlink/core/calls/call_runtime_tracking.dart';

void main() {
  group('CallRemoteControlHandler', () {
    test('ignores stale remote video state replay', () async {
      var state = const CallState(
        phase: CallPhase.active,
        callId: 'call-a',
        peerId: 'peer-a',
        mediaType: CallMediaType.video,
      );
      final emittedStates = <CallState>[];
      final logs = <String>[];
      final tracking = CallRuntimeTracking();
      final handler = CallRemoteControlHandler(
        heartbeatController: CallHeartbeatController(
          sendSignal: (_, _, _) async {},
          isSignalingConnected: () => true,
          onHeartbeatMissed: (_) async {},
          log: logs.add,
        ),
        runtimeTracking: tracking,
        getState: () => state,
        getPeer: () => null,
        emit: (next) {
          state = next;
          emittedStates.add(next);
        },
        log: logs.add,
        markRemoteMediaReady: () {},
        cancelMediaReadyTimeout: () {},
        updateActiveState: () {},
        armMediaReadyTimeout: () {},
        streamHasVideo: (_) => false,
      );

      await handler.handleRemoteVideoState(
        peerId: 'peer-a',
        callId: 'call-a',
        enabled: true,
        version: 2,
      );
      await handler.handleRemoteVideoState(
        peerId: 'peer-a',
        callId: 'call-a',
        enabled: false,
        version: 1,
      );

      expect(emittedStates, hasLength(1));
      expect(tracking.remoteVideoStateSnapshot?.enabled, isTrue);
      expect(tracking.remoteVideoStateSnapshot?.version, 2);
      expect(logs.any((line) => line.contains('video:remote ignored')), isTrue);
    });
  });
}
