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
  int remoteVideoStateVersion = -1;

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
  Timer? remoteVideoFlowRecoveryTimer;
  int? pendingRemoteVideoRecoveryVersion;

  String? localVideoQualityProfile;
  int videoQualityStablePolls = 0;
  int videoQualityPoorPolls = 0;
  int lastVideoQualityAudioPacketsLost = -1;
  int lastVideoQualityVideoPacketsLost = -1;
  DateTime? lastVideoNetworkDiagnosticAt;
}
