import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_video_state.dart';

class CallVideoChannelSnapshot {
  const CallVideoChannelSnapshot({
    required CallVideoState state,
    required bool Function() getLocalVideoTrackAttached,
  }) : _state = state,
       _getLocalVideoTrackAttached = getLocalVideoTrackAttached;

  final CallVideoState _state;
  final bool Function() _getLocalVideoTrackAttached;

  String format() {
    return 'sendSenderId=${_state.videoSendSender?.senderId} '
        'sendTrack=${_trackSnapshot(_state.videoSendSender?.track)} '
        'sendMid=${_state.videoSendTransceiver?.mid} '
        'recvMid=${_state.videoReceiveTransceiver?.mid} '
        'recvTrack=${_trackSnapshot(_state.videoReceiveTransceiver?.receiver.track)} '
        'expectedSendMid=${_state.expectedVideoSendMid} '
        'expectedRecvMid=${_state.expectedVideoReceiveMid} '
        'localAttached=${_getLocalVideoTrackAttached()} '
        'profile=${_state.localVideoQualityProfile}';
  }

  String _trackSnapshot(MediaStreamTrack? track) {
    if (track == null) {
      return 'null';
    }
    return '${track.kind}:${track.id}:enabled=${track.enabled}:muted=${track.muted}';
  }
}
