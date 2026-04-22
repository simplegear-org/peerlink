import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallVideoState {
  RTCRtpSender? videoSendSender;
  RTCRtpTransceiver? videoSendTransceiver;
  RTCRtpTransceiver? videoReceiveTransceiver;

  String? expectedVideoSendMid;
  String? expectedVideoReceiveMid;

  bool remoteVideoEnabled = false;
  bool remoteVideoFlowSeen = false;

  int? pendingRemoteVideoFlowAckVersion;
  int? pendingVideoFlowVersion;

  int videoStateVersion = 0;
  int? pendingVideoStateVersion;
  bool? pendingVideoStateEnabled;
  int pendingVideoStateAttempts = 0;

  int lastInboundVideoBytes = -1;
  int lastInboundVideoFramesDecoded = -1;

  Timer? videoUplinkFallbackTimer;
  Timer? videoStateAckTimer;
  Timer? videoQualityUpgradeTimer;
}
