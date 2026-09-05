import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_peer_invariant_helper.dart';

void main() {
  group('CallPeerInvariantHelper', () {
    const helper = CallPeerInvariantHelper();

    test('matches only exact active peer and call pair', () {
      const state = CallState(
        phase: CallPhase.active,
        peerId: 'peer-a',
        callId: 'call-a',
        direction: CallDirection.outgoing,
      );

      expect(
        helper.matchesCurrentCall(
          currentState: state,
          peerId: 'peer-a',
          callId: 'call-a',
        ),
        isTrue,
      );
      expect(
        helper.matchesCurrentCall(
          currentState: state,
          peerId: 'peer-b',
          callId: 'call-a',
        ),
        isFalse,
      );
    });

    test('detects foreign peer collision for same active callId', () {
      const state = CallState(
        phase: CallPhase.connecting,
        peerId: 'peer-a',
        callId: 'call-a',
        direction: CallDirection.incoming,
      );

      expect(
        helper.hasForeignPeerForActiveCallId(
          currentState: state,
          peerId: 'peer-b',
          callId: 'call-a',
        ),
        isTrue,
      );
      expect(
        helper.hasForeignPeerForActiveCallId(
          currentState: state,
          peerId: 'peer-a',
          callId: 'call-a',
        ),
        isFalse,
      );
    });
  });
}
