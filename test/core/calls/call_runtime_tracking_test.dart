import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_runtime_tracking.dart';
import 'package:peerlink/core/calls/call_state_update_helper.dart';

void main() {
  group('CallRuntimeTracking', () {
    const stateUpdateHelper = CallStateUpdateHelper();

    test('tracks media activity only when stats advance', () {
      final tracking = CallRuntimeTracking();
      final now = DateTime(2026, 1, 1, 12);
      const state = CallState(
        phase: CallPhase.active,
        callId: 'call-a',
        peerId: 'peer-a',
      );

      final unchanged = tracking.applyPeerStats(
        currentState: state,
        sentBytes: 0,
        receivedBytes: 0,
        stateUpdateHelper: stateUpdateHelper,
        now: () => now,
      );

      expect(unchanged.state.bytesSent, 0);
      expect(unchanged.state.bytesReceived, 0);
      expect(
        tracking.isMediaRecentlyActive(
          grace: const Duration(seconds: 6),
          now: () => now,
        ),
        isFalse,
      );

      final advanced = tracking.applyPeerStats(
        currentState: state,
        sentBytes: 10,
        receivedBytes: 20,
        stateUpdateHelper: stateUpdateHelper,
        now: () => now,
      );

      expect(advanced.state.bytesSent, 10);
      expect(advanced.state.bytesReceived, 20);
      expect(
        tracking.isMediaRecentlyActive(
          grace: const Duration(seconds: 6),
          now: () => now.add(const Duration(seconds: 5)),
        ),
        isTrue,
      );
      expect(
        tracking.isMediaRecentlyActive(
          grace: const Duration(seconds: 6),
          now: () => now.add(const Duration(seconds: 7)),
        ),
        isFalse,
      );
    });

    test('resets stats offsets from current call state', () {
      final tracking = CallRuntimeTracking();
      const state = CallState(
        phase: CallPhase.active,
        callId: 'call-a',
        peerId: 'peer-a',
        bytesSent: 50,
        bytesReceived: 70,
      );

      tracking.resetPeerStatsTracking(state);
      final result = tracking.applyPeerStats(
        currentState: state,
        sentBytes: 5,
        receivedBytes: 9,
        stateUpdateHelper: stateUpdateHelper,
      );

      expect(result.state.bytesSent, 55);
      expect(result.state.bytesReceived, 79);
    });

    test('tracks local and remote audio mute versions', () {
      final tracking = CallRuntimeTracking();

      expect(tracking.nextLocalAudioMuteVersion(), 1);
      expect(tracking.nextLocalAudioMuteVersion(), 2);
      expect(tracking.remoteAudioMuteSnapshot, isNull);
      expect(tracking.shouldApplyRemoteAudioMuteVersion(1), isTrue);

      tracking.applyRemoteAudioMute(muted: true, version: 1);
      expect(tracking.remoteAudioMuteVersion, 1);
      expect(tracking.shouldApplyRemoteAudioMuteVersion(1), isFalse);
      expect(tracking.shouldApplyRemoteAudioMuteVersion(2), isTrue);
      expect(tracking.remoteAudioMuteSnapshot?.muted, isTrue);
      expect(tracking.remoteAudioMuteSnapshot?.version, 1);

      tracking.reset();
      expect(tracking.nextLocalAudioMuteVersion(), 1);
      expect(tracking.remoteAudioMuteSnapshot, isNull);
      expect(tracking.shouldApplyRemoteAudioMuteVersion(0), isTrue);
    });

    test('tracks remote video state versions for replay after attach', () {
      final tracking = CallRuntimeTracking();

      expect(tracking.remoteVideoStateSnapshot, isNull);
      expect(tracking.shouldApplyRemoteVideoStateVersion(3), isTrue);

      tracking.applyRemoteVideoState(enabled: true, version: 3);
      expect(tracking.remoteVideoStateVersion, 3);
      expect(tracking.shouldApplyRemoteVideoStateVersion(3), isFalse);
      expect(tracking.shouldApplyRemoteVideoStateVersion(4), isTrue);
      expect(tracking.remoteVideoStateSnapshot?.enabled, isTrue);
      expect(tracking.remoteVideoStateSnapshot?.version, 3);

      tracking.applyRemoteVideoState(enabled: false, version: 4);
      expect(tracking.remoteVideoStateSnapshot?.enabled, isFalse);
      expect(tracking.remoteVideoStateSnapshot?.version, 4);

      tracking.reset();
      expect(tracking.remoteVideoStateSnapshot, isNull);
      expect(tracking.shouldApplyRemoteVideoStateVersion(0), isTrue);
    });
  });
}
