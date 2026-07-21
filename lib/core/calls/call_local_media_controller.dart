import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_media_stream_controller.dart';
import 'call_models.dart';
import 'call_video_controller.dart';

class CallLocalMediaController {
  final CallMediaStreamController _mediaStreamController;
  final void Function(String message) _log;
  final void Function(CallMediaType mediaType) _onMediaTypeChanged;
  final RTCPeerConnection? Function() _getPeer;
  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final CallMediaType Function() _getMediaType;
  final void Function(CallMediaType value) _setMediaType;
  final bool Function() _getLocalVideoTrackAttached;
  final RTCRtpSender? Function() _getVideoSendSender;
  final RTCRtpTransceiver? Function() _getVideoSendTransceiver;
  final RTCRtpTransceiver? Function() _getVideoReceiveTransceiver;
  final Future<bool> Function() _ensureVideoTransceiversReady;
  final Future<void> Function(String reason) _requestRenegotiation;
  final Future<void> Function({
    required bool enabled,
    required String peerId,
    required String callId,
  })
  _sendVideoState;
  final void Function() _cancelVideoUplinkFallback;
  final CallVideoController _videoController;

  const CallLocalMediaController({
    required CallMediaStreamController mediaStreamController,
    required void Function(String message) log,
    required void Function(CallMediaType mediaType) onMediaTypeChanged,
    required RTCPeerConnection? Function() getPeer,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required CallMediaType Function() getMediaType,
    required void Function(CallMediaType value) setMediaType,
    required bool Function() getLocalVideoTrackAttached,
    required RTCRtpSender? Function() getVideoSendSender,
    required RTCRtpTransceiver? Function() getVideoSendTransceiver,
    required RTCRtpTransceiver? Function() getVideoReceiveTransceiver,
    required Future<bool> Function() ensureVideoTransceiversReady,
    required Future<void> Function(String reason) requestRenegotiation,
    required Future<void> Function({
      required bool enabled,
      required String peerId,
      required String callId,
    })
    sendVideoState,
    required void Function() cancelVideoUplinkFallback,
    required CallVideoController videoController,
  }) : _mediaStreamController = mediaStreamController,
       _log = log,
       _onMediaTypeChanged = onMediaTypeChanged,
       _getPeer = getPeer,
       _getPeerId = getPeerId,
       _getCallId = getCallId,
       _getMediaType = getMediaType,
       _setMediaType = setMediaType,
       _getLocalVideoTrackAttached = getLocalVideoTrackAttached,
       _getVideoSendSender = getVideoSendSender,
       _getVideoSendTransceiver = getVideoSendTransceiver,
       _getVideoReceiveTransceiver = getVideoReceiveTransceiver,
       _ensureVideoTransceiversReady = ensureVideoTransceiversReady,
       _requestRenegotiation = requestRenegotiation,
       _sendVideoState = sendVideoState,
       _cancelVideoUplinkFallback = cancelVideoUplinkFallback,
       _videoController = videoController;

  Future<void> setMuted(bool muted) {
    _log('audio:mute request muted=$muted');
    return _mediaStreamController.setMuted(muted);
  }

  Future<void> setSpeakerOn(bool enabled) async {
    if (_mediaStreamController.localStream == null) {
      _log('audio:speakerphone deferred enabled=$enabled localStream=false');
      return;
    }
    await applySpeakerOn(enabled);
  }

  Future<void> applySpeakerOn(bool enabled) async {
    if (kIsWeb ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows) {
      _log(
        'audio:speakerphone ignored platform=$defaultTargetPlatform enabled=$enabled',
      );
      return;
    }
    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (error) {
      _log('audio:speakerphone failed enabled=$enabled error=$error');
    }
  }

  Future<void> flipCamera() {
    return _mediaStreamController.flipCamera();
  }

  Future<void> setLocalVideoEnabled(bool enabled) async {
    if ((_getMediaType() == CallMediaType.video) == enabled) {
      _log(
        'video:toggle skipped reason=already-applied enabled=$enabled '
        'media=${_getMediaType().name}',
      );
      return;
    }

    final peerId = _getPeerId();
    final callId = _getCallId();
    _log(
      'video:toggle start enabled=$enabled media=${_getMediaType().name} '
      'peer=${_getPeer() != null} localStream=${_mediaStreamController.localStream != null} '
      'peerId=${peerId != null} callId=${callId != null} '
      'senderId=${_getVideoSendSender()?.senderId} '
      'sendMid=${_getVideoSendTransceiver()?.mid} '
      'recvMid=${_getVideoReceiveTransceiver()?.mid} '
      'localAttached=${_getLocalVideoTrackAttached()}',
    );
    if (_getPeer() == null ||
        _mediaStreamController.localStream == null ||
        peerId == null ||
        callId == null) {
      final next = enabled ? CallMediaType.video : CallMediaType.audio;
      _setMediaType(next);
      _onMediaTypeChanged(next);
      _log(
        'diagnostic:warning video:toggle partial-applied reason=missing-runtime '
        'enabled=$enabled peer=${_getPeer() != null} '
        'localStream=${_mediaStreamController.localStream != null} '
        'peerId=${peerId != null} callId=${callId != null}',
      );
      return;
    }

    final next = enabled ? CallMediaType.video : CallMediaType.audio;
    var createdVideoTransceivers = false;
    _setMediaType(next);
    _onMediaTypeChanged(next);
    if (enabled) {
      createdVideoTransceivers = await _ensureVideoTransceiversReady();
    }
    await _videoController.syncLocalMediaTracks();
    if (enabled) {
      await _requestRenegotiation(
        createdVideoTransceivers
            ? 'video transceivers created on demand'
            : 'local video enabled',
      );
    }
    await _sendVideoState(enabled: enabled, peerId: peerId, callId: callId);
    if (enabled) {
      await _videoController.refreshVideoChannelHandles();
      _log(
        'video:toggle applied enabled=$enabled '
        'senderId=${_getVideoSendSender()?.senderId} '
        'sendMid=${_getVideoSendTransceiver()?.mid} '
        'recvMid=${_getVideoReceiveTransceiver()?.mid} '
        'localAttached=${_getLocalVideoTrackAttached()}',
      );
    } else {
      _cancelVideoUplinkFallback();
      _videoController.cancelVideoQualityUpgrade();
      _log(
        'video:toggle applied enabled=$enabled '
        'localTracks=${_mediaStreamController.localVideoTrackCount} '
        'localAttached=${_getLocalVideoTrackAttached()}',
      );
    }
  }
}
