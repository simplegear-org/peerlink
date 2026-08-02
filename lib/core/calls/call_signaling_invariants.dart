import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallSignalingInvariants {
  const CallSignalingInvariants._();

  static bool isDuplicateOffer({
    required String offerKey,
    required String? activeOfferKey,
    required String? lastCompletedOfferKey,
  }) {
    return activeOfferKey == offerKey || lastCompletedOfferKey == offerKey;
  }

  static bool canCreateAnswer({
    required RTCSignalingState? signalingState,
    required String? localDescriptionType,
  }) {
    return signalingState ==
            RTCSignalingState.RTCSignalingStateHaveRemoteOffer ||
        signalingState ==
            RTCSignalingState.RTCSignalingStateHaveLocalPrAnswer ||
        localDescriptionType == null;
  }

  static bool isWaitingForAnswer({
    required RTCSignalingState? signalingState,
    required String? localDescriptionType,
  }) {
    return signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  }

  static bool shouldRecreatePeerForIncomingOffer({
    required bool hasPeer,
    required bool modeChanged,
    required bool remoteDescriptionSet,
    required RTCSignalingState? signalingState,
    required String? localDescriptionType,
  }) {
    if (!hasPeer) {
      return false;
    }

    final hasPendingLocalOffer =
        signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer;

    if (!modeChanged && remoteDescriptionSet && hasPendingLocalOffer) {
      return false;
    }

    return modeChanged || !remoteDescriptionSet || hasPendingLocalOffer;
  }

  static bool shouldRollbackLocalOfferForIncomingOffer({
    required RTCSignalingState? signalingState,
    required String? localDescriptionType,
  }) {
    return signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  }

  static bool shouldIgnoreSetDescriptionErrorAsLate({
    required RTCSignalingState? signalingState,
    required String? localDescriptionType,
    required Object error,
  }) {
    final becameStable =
        signalingState == RTCSignalingState.RTCSignalingStateStable;
    return becameStable ||
        error.toString().contains('Called in wrong state: stable');
  }
}
