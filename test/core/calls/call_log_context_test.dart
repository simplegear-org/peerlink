import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_log_context.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

void main() {
  group('buildStructuredCallLogContext', () {
    test('includes core call fields in stable structured form', () {
      final context = buildStructuredCallLogContext(
        scope: 'service',
        peerId: 'peer-a',
        callId: 'call-a',
        epoch: 7,
        role: 'incoming',
        mediaType: CallMediaType.video,
        transportMode: TransportMode.turn,
        phase: CallPhase.active,
      );

      expect(context, contains('scope=service'));
      expect(context, contains('callId=call-a'));
      expect(context, contains('peerId=peer-a'));
      expect(context, contains('epoch=7'));
      expect(context, contains('role=incoming'));
      expect(context, contains('phase=active'));
      expect(context, contains('mode=turn'));
      expect(context, contains('media=video'));
      expect(context, contains('signaling=unknown'));
    });
  });
}
