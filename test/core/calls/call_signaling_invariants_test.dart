import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_signaling_invariants.dart';

void main() {
  group('CallSignalingInvariants', () {
    test('detects duplicate offer from in-flight and completed keys', () {
      expect(
        CallSignalingInvariants.isDuplicateOffer(
          offerKey: 'call-1:turn:abc',
          activeOfferKey: 'call-1:turn:abc',
          lastCompletedOfferKey: null,
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.isDuplicateOffer(
          offerKey: 'call-1:turn:abc',
          activeOfferKey: null,
          lastCompletedOfferKey: 'call-1:turn:abc',
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.isDuplicateOffer(
          offerKey: 'call-1:turn:abc',
          activeOfferKey: 'other',
          lastCompletedOfferKey: 'other',
        ),
        isFalse,
      );
    });

    test('allows answer only from offer-compatible signaling states', () {
      expect(
        CallSignalingInvariants.canCreateAnswer(
          signalingState: RTCSignalingState.RTCSignalingStateHaveRemoteOffer,
          localDescriptionType: null,
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.canCreateAnswer(
          signalingState: RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer,
          localDescriptionType: 'pranswer',
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.canCreateAnswer(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'answer',
        ),
        isFalse,
      );
    });

    test('treats answer as expected only while waiting for remote answer', () {
      expect(
        CallSignalingInvariants.isWaitingForAnswer(
          signalingState: RTCSignalingState.RTCSignalingStateHaveLocalOffer,
          localDescriptionType: 'offer',
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.isWaitingForAnswer(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'offer',
        ),
        isFalse,
      );
      expect(
        CallSignalingInvariants.isWaitingForAnswer(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'answer',
        ),
        isFalse,
      );
    });

    test('reuses peer for same-session offer on same transport', () {
      expect(
        CallSignalingInvariants.shouldRecreatePeerForIncomingOffer(
          hasPeer: true,
          modeChanged: false,
          remoteDescriptionSet: true,
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'answer',
        ),
        isFalse,
      );
      expect(
        CallSignalingInvariants.shouldRecreatePeerForIncomingOffer(
          hasPeer: true,
          modeChanged: false,
          remoteDescriptionSet: true,
          signalingState: RTCSignalingState.RTCSignalingStateHaveLocalOffer,
          localDescriptionType: 'offer',
        ),
        isFalse,
      );
      expect(
        CallSignalingInvariants.shouldRecreatePeerForIncomingOffer(
          hasPeer: true,
          modeChanged: false,
          remoteDescriptionSet: true,
          signalingState: RTCSignalingState.RTCSignalingStateHaveLocalOffer,
          localDescriptionType: 'offer',
        ),
        isFalse,
      );
    });

    test('recreates peer for incompatible incoming offer states', () {
      expect(
        CallSignalingInvariants.shouldRecreatePeerForIncomingOffer(
          hasPeer: true,
          modeChanged: true,
          remoteDescriptionSet: true,
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'answer',
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.shouldRecreatePeerForIncomingOffer(
          hasPeer: true,
          modeChanged: false,
          remoteDescriptionSet: false,
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'answer',
        ),
        isTrue,
      );
    });

    test(
      'classifies stable setDescription errors as late answer/offer races',
      () {
        expect(
          CallSignalingInvariants.shouldIgnoreSetDescriptionErrorAsLate(
            signalingState: RTCSignalingState.RTCSignalingStateStable,
            localDescriptionType: 'answer',
            error: StateError('anything'),
          ),
          isTrue,
        );
        expect(
          CallSignalingInvariants.shouldIgnoreSetDescriptionErrorAsLate(
            signalingState: RTCSignalingState.RTCSignalingStateStable,
            localDescriptionType: 'offer',
            error: StateError('anything'),
          ),
          isTrue,
        );
        expect(
          CallSignalingInvariants.shouldIgnoreSetDescriptionErrorAsLate(
            signalingState: RTCSignalingState.RTCSignalingStateHaveRemoteOffer,
            localDescriptionType: 'offer',
            error: Exception('Called in wrong state: stable'),
          ),
          isTrue,
        );
        expect(
          CallSignalingInvariants.shouldIgnoreSetDescriptionErrorAsLate(
            signalingState: RTCSignalingState.RTCSignalingStateHaveRemoteOffer,
            localDescriptionType: 'offer',
            error: Exception('other failure'),
          ),
          isFalse,
        );
      },
    );

    test('rolls back local offer before same-peer incoming recovery offer', () {
      expect(
        CallSignalingInvariants.shouldRollbackLocalOfferForIncomingOffer(
          signalingState: RTCSignalingState.RTCSignalingStateHaveLocalOffer,
          localDescriptionType: 'offer',
        ),
        isTrue,
      );
      expect(
        CallSignalingInvariants.shouldRollbackLocalOfferForIncomingOffer(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'offer',
        ),
        isFalse,
      );
      expect(
        CallSignalingInvariants.shouldRollbackLocalOfferForIncomingOffer(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescriptionType: 'answer',
        ),
        isFalse,
      );
      expect(
        CallSignalingInvariants.shouldRollbackLocalOfferForIncomingOffer(
          signalingState: RTCSignalingState.RTCSignalingStateHaveLocalOffer,
          localDescriptionType: 'offer',
        ),
        isTrue,
      );
    });
  });
}
