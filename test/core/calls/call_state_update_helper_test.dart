import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_state_update_helper.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

void main() {
  test('native remote stream can disable track-specific renderer binding', () {
    const state = CallState(
      phase: CallPhase.active,
      remoteVideoUsesTrackBinding: true,
    );

    final refreshed = state.copyWith(remoteVideoUsesTrackBinding: false);

    expect(refreshed.remoteVideoUsesTrackBinding, isFalse);
  });

  group('CallStateUpdateHelper', () {
    const helper = CallStateUpdateHelper();

    test('remote video upgrade keeps active audio call stable', () {
      final state = CallState(
        phase: CallPhase.active,
        callId: 'call-a',
        peerId: 'peer-a',
        mediaType: CallMediaType.audio,
        transportMode: TransportMode.turn,
        debugStatus: 'Аудиозвонок активен',
        remoteVideoEnabled: false,
        remoteVideoAvailable: false,
        remoteVideoActive: false,
      );

      final next = helper.applyRemoteVideoState(
        currentState: state,
        enabled: true,
        streamHasVideo: (_) => false,
      );

      expect(next.phase, CallPhase.active);
      expect(next.mediaType, CallMediaType.audio);
      expect(next.callId, 'call-a');
      expect(next.peerId, 'peer-a');
      expect(next.transportMode, TransportMode.turn);
      expect(next.remoteVideoEnabled, isTrue);
      expect(next.remoteVideoAvailable, isFalse);
      expect(next.remoteVideoActive, isFalse);
      expect(next.debugStatus, 'Собеседник включает видео');
    });
  });
}
