import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_runtime_logger.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

void main() {
  group('CallRuntimeLogger', () {
    test('can be created with full structured context provider', () {
      final logger = CallRuntimeLogger(
        channel: 'call',
        getOwnerId: () => 'self',
        getContext: () => (
          peerId: 'peer-a',
          callId: 'call-a',
          epoch: 3,
          role: 'incoming',
          mediaType: CallMediaType.video,
          transportMode: TransportMode.turn,
          phase: CallPhase.active,
          signalingState: 'stable',
        ),
      );

      expect(logger, isNotNull);
    });
  });
}
