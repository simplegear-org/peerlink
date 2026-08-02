import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import 'call_media_stream_controller.dart';
import 'call_media_stats_utils.dart';
import 'call_models.dart';
import 'call_video_channel_snapshot.dart';
import 'call_video_quality_controller.dart';
import 'call_video_signaling_controller.dart';
import 'call_video_state.dart';
import 'call_video_transceiver_controller.dart';

class CallVideoController {
  final CallVideoState _state;
  final void Function(String message) _log;

  final CallMediaType Function() _getMediaType;
  final CallMediaStreamController _mediaStreamController;
  late final CallVideoChannelSnapshot _channelSnapshot;
  late final CallVideoQualityController _qualityController;
  late final CallVideoSignalingController _signalingController;
  late final CallVideoTransceiverController _transceiverController;

  CallVideoController({
    required SignalingService signaling,
    required CallMediaStreamController mediaStreamController,
    required CallVideoState state,
    required void Function(String message) log,
    required List<String> Function(String? sdp) extractVideoMids,
    required void Function(bool active) onRemoteVideoFlowChanged,
    required Future<void> Function(String reason) onRemoteVideoFlowStalled,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required bool Function() getStartedAsOfferer,
    required CallMediaType Function() getMediaType,
    required bool Function() getLocalVideoTrackAttached,
    required RTCPeerConnection? Function() getPeer,
    required int Function() getSessionEpoch,
  }) : _state = state,
       _log = log,
       _getMediaType = getMediaType,
       _mediaStreamController = mediaStreamController {
    _channelSnapshot = CallVideoChannelSnapshot(
      state: state,
      getLocalVideoTrackAttached: getLocalVideoTrackAttached,
    );
    _qualityController = CallVideoQualityController(
      state: state,
      log: log,
      getSessionEpoch: getSessionEpoch,
      getMediaType: getMediaType,
      getLocalVideoTrackAttached: getLocalVideoTrackAttached,
      videoChannelSnapshot: _videoChannelSnapshot,
    );
    _signalingController = CallVideoSignalingController(
      signaling: signaling,
      state: state,
      log: log,
      getSessionEpoch: getSessionEpoch,
      getPeerId: getPeerId,
      getCallId: getCallId,
      onRemoteVideoFlowChanged: onRemoteVideoFlowChanged,
      onRemoteVideoFlowStalled: onRemoteVideoFlowStalled,
      scheduleVideoQualityUpgrade:
          _qualityController.scheduleVideoQualityUpgrade,
    );
    _transceiverController = CallVideoTransceiverController(
      state: state,
      log: log,
      extractVideoMids: extractVideoMids,
      getStartedAsOfferer: getStartedAsOfferer,
      getPeer: getPeer,
      videoChannelSnapshot: _videoChannelSnapshot,
    );
  }

  void scheduleVideoUplinkFallback(int version) {
    _signalingController.scheduleVideoUplinkFallback(version);
  }

  void scheduleRemoteVideoFlowRecovery(int version) {
    _signalingController.scheduleRemoteVideoFlowRecovery(version);
  }

  void cancelRemoteVideoFlowRecovery() {
    _signalingController.cancelRemoteVideoFlowRecovery();
  }

  void cancelVideoUplinkFallback() {
    _signalingController.cancelVideoUplinkFallback();
  }

  Future<void> sendVideoState({
    required bool enabled,
    required String peerId,
    required String callId,
  }) async {
    await _signalingController.sendVideoState(
      enabled: enabled,
      peerId: peerId,
      callId: callId,
    );
  }

  Future<void> handleRemoteVideoState({
    required bool enabled,
    required int version,
    required String peerId,
    required String callId,
  }) async {
    await _signalingController.handleRemoteVideoState(
      enabled: enabled,
      version: version,
      peerId: peerId,
      callId: callId,
    );
  }

  void handleVideoStateAck({required bool enabled, required int version}) {
    _signalingController.handleVideoStateAck(
      enabled: enabled,
      version: version,
    );
  }

  void handleVideoFlowAck({required int version}) {
    _signalingController.handleVideoFlowAck(version: version);
  }

  void markRemoteVideoFlowDetected() {
    _signalingController.markRemoteVideoFlowDetected();
  }

  Future<void> sendVideoStateAttempt({
    required bool enabled,
    required String peerId,
    required String callId,
    required int version,
  }) async {
    await _signalingController.sendVideoStateAttempt(
      enabled: enabled,
      peerId: peerId,
      callId: callId,
      version: version,
    );
  }

  Future<void> applyInitialVideoQualityProfile() async {
    await _qualityController.applyInitialVideoQualityProfile();
  }

  void scheduleVideoQualityUpgrade() {
    _qualityController.scheduleVideoQualityUpgrade();
  }

  void cancelVideoQualityUpgrade() {
    _qualityController.cancelVideoQualityUpgrade();
  }

  Future<void> applyUpgradedVideoQualityProfile() async {
    await _qualityController.applyUpgradedVideoQualityProfile();
  }

  Future<void> handleNetworkStats({
    required AudioTrafficStats stats,
    required double outboundKbps,
  }) async {
    await _qualityController.handleNetworkStats(
      stats: stats,
      outboundKbps: outboundKbps,
    );
  }

  String _videoChannelSnapshot() {
    return _channelSnapshot.format();
  }

  void cancelPendingVideoStateAck() {
    _signalingController.cancelPendingVideoStateAck();
  }

  Future<void> syncLocalMediaTracks() async {
    _log(
      'video:sync begin media=${_getMediaType().name} '
      '${_videoChannelSnapshot()}',
    );
    await _mediaStreamController.syncLocalMediaTracks(
      mediaType: _getMediaType(),
      refreshVideoChannelHandles: refreshVideoChannelHandles,
      applyInitialVideoQualityProfile: applyInitialVideoQualityProfile,
      getVideoSendSender: () => _state.videoSendSender,
      getVideoSendTransceiver: () => _state.videoSendTransceiver,
      setVideoSendSender: (sender) => _state.videoSendSender = sender,
    );
    if (_getMediaType() == CallMediaType.audio) {
      cancelVideoQualityUpgrade();
    }
    _log(
      'video:sync done media=${_getMediaType().name} '
      '${_videoChannelSnapshot()}',
    );
  }

  Future<bool> ensureVideoTransceiversReady() {
    return _transceiverController.ensureVideoTransceiversReady();
  }

  Future<void> refreshVideoChannelHandles() {
    return _transceiverController.refreshVideoChannelHandles();
  }

  Future<TransceiverDirection?> safeGetDirection(
    RTCRtpTransceiver transceiver,
  ) {
    return _transceiverController.safeGetDirection(transceiver);
  }

  Future<TransceiverDirection?> safeGetCurrentDirection(
    RTCRtpTransceiver transceiver,
  ) {
    return _transceiverController.safeGetCurrentDirection(transceiver);
  }

  void captureExpectedVideoMidsForLocalOffer(String? sdp) {
    _transceiverController.captureExpectedVideoMidsForLocalOffer(sdp);
  }

  void captureExpectedVideoMidsForRemoteOffer(String? sdp) {
    _transceiverController.captureExpectedVideoMidsForRemoteOffer(sdp);
  }

  void captureExpectedVideoMidsForRemoteAnswer(String? sdp) {
    _transceiverController.captureExpectedVideoMidsForRemoteAnswer(sdp);
  }

  Future<void> ensureVideoTransceiverDirectionsForRole() {
    return _transceiverController.ensureVideoTransceiverDirectionsForRole();
  }
}
