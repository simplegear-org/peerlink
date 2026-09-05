import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_media_readiness_helper.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

void main() {
  group('CallMediaReadinessHelper', () {
    const helper = CallMediaReadinessHelper();

    test('moves call to active when both sides are ready', () {
      final now = DateTime(2026, 6, 9, 12, 0);
      final state = CallState(
        phase: CallPhase.connecting,
        peerId: 'peer-a',
        callId: 'call-a',
        transportMode: TransportMode.turn,
      );

      final next = helper.buildReadinessState(
        currentState: state,
        localMediaReady: true,
        remoteMediaReady: true,
        now: now,
      );

      expect(next.phase, CallPhase.active);
      expect(next.connectedAt, now);
      expect(next.debugStatus, 'Звонок через TURN активен, видеоканал готов');
    });

    test('keeps call in connecting with explicit waiting reason', () {
      final state = CallState(
        phase: CallPhase.connecting,
        peerId: 'peer-b',
        callId: 'call-b',
      );

      final next = helper.buildReadinessState(
        currentState: state,
        localMediaReady: false,
        remoteMediaReady: true,
        now: DateTime(2026, 6, 9, 12, 0),
      );

      expect(next.phase, CallPhase.connecting);
      expect(next.debugStatus, 'Ждем локальный входящий аудиопоток');
    });
  });
}
