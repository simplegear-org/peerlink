import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_models.dart';

class CallLocalVideoTrackController {
  final void Function(String message) _log;
  MediaStream? _videoSourceStream;
  bool _localVideoTrackAttached = false;
  bool _isFrontCamera = true;

  CallLocalVideoTrackController({required void Function(String message) log})
    : _log = log;

  MediaStream? get videoSourceStream => _videoSourceStream;
  bool get localVideoTrackAttached => _localVideoTrackAttached;
  bool get isFrontCamera => _isFrontCamera;

  void resetAttachment() {
    _localVideoTrackAttached = false;
  }

  String _trackIds(List<MediaStreamTrack> tracks) =>
      tracks.map((track) => track.id).join(',');

  String _trackState(MediaStreamTrack track) {
    return '${track.kind}:${track.id}:enabled=${track.enabled}:muted=${track.muted}';
  }

  String _trackStates(List<MediaStreamTrack> tracks) =>
      tracks.map(_trackState).join(',');

  String _streamSummary(MediaStream? stream) {
    if (stream == null) {
      return 'null';
    }
    final audioTracks = List<MediaStreamTrack>.from(stream.getAudioTracks());
    final videoTracks = List<MediaStreamTrack>.from(stream.getVideoTracks());
    return 'id=${stream.id} '
        'audio=${audioTracks.length}[${_trackIds(audioTracks)}] '
        'video=${videoTracks.length}[${_trackIds(videoTracks)}]';
  }

  Future<void> flipCamera({
    required MediaStream? localStream,
    required void Function(MediaStream stream) onLocalStream,
  }) async {
    final track = _resolvePrimaryVideoTrack(localStream);
    if (track == null) {
      _log(
        'video:flip skipped local=${_streamSummary(localStream)} '
        'source=${_streamSummary(_videoSourceStream)}',
      );
      return;
    }
    _log(
      'video:flip start front=$_isFrontCamera '
      'track=${track.id} local=${_streamSummary(localStream)} '
      'source=${_streamSummary(_videoSourceStream)}',
    );
    await Helper.switchCamera(track);
    _isFrontCamera = !_isFrontCamera;
    _log(
      'video:flip done front=$_isFrontCamera '
      'track=${track.id} local=${_streamSummary(localStream)} '
      'source=${_streamSummary(_videoSourceStream)}',
    );
    if (localStream != null) {
      onLocalStream(localStream);
    }
  }

  Future<void> syncLocalVideoTrack({
    required MediaStream localStream,
    required CallMediaType mediaType,
    required Future<void> Function() refreshVideoChannelHandles,
    required Future<void> Function() applyInitialVideoQualityProfile,
    required RTCRtpSender? Function() getVideoSendSender,
    required RTCRtpTransceiver? Function() getVideoSendTransceiver,
    required void Function(RTCRtpSender? sender) setVideoSendSender,
    required void Function(MediaStream stream) onLocalStream,
  }) async {
    await refreshVideoChannelHandles();

    if (mediaType == CallMediaType.video) {
      final track = await _ensurePrimaryVideoTrack();
      if (track == null) {
        return;
      }
      final beforeLocalIds = _trackIds(
        List<MediaStreamTrack>.from(localStream.getVideoTracks()),
      );
      final alreadyAttached = localStream.getVideoTracks().any(
        (existing) => existing.id == track.id,
      );
      if (!alreadyAttached) {
        await localStream.addTrack(track);
        _log(
          'video:local addTrack stable track=${track.id} '
          'before=[$beforeLocalIds] after=[${_trackIds(localStream.getVideoTracks())}]',
        );
      }
      await _setTrackEnabled(track, enabled: true, reason: 'enable');
      await _ensureSenderBoundToTrack(
        localStream: localStream,
        track: track,
        getVideoSendSender: getVideoSendSender,
        getVideoSendTransceiver: getVideoSendTransceiver,
        setVideoSendSender: setVideoSendSender,
      );
      _localVideoTrackAttached = true;
      await applyInitialVideoQualityProfile();
      _log(
        'video:sync stable enabled local=${_streamSummary(localStream)} '
        'source=${_streamSummary(_videoSourceStream)}',
      );
      onLocalStream(localStream);
      return;
    }

    final track = _resolvePrimaryVideoTrack(localStream);
    if (track == null) {
      _localVideoTrackAttached = false;
      _log(
        'video:sync stable disable skipped local=${_streamSummary(localStream)} '
        'source=${_streamSummary(_videoSourceStream)}',
      );
      return;
    }
    await _setTrackEnabled(track, enabled: false, reason: 'disable');
    await _ensureSenderBoundToTrack(
      localStream: localStream,
      track: track,
      getVideoSendSender: getVideoSendSender,
      getVideoSendTransceiver: getVideoSendTransceiver,
      setVideoSendSender: setVideoSendSender,
    );
    _localVideoTrackAttached = true;
    _log(
      'video:sync stable disabled local=${_streamSummary(localStream)} '
      'source=${_streamSummary(_videoSourceStream)}',
    );
    onLocalStream(localStream);
  }

  Future<void> disposeVideoSourceStream() async {
    final tracks = List<MediaStreamTrack>.from(
      _videoSourceStream?.getTracks() ?? const <MediaStreamTrack>[],
    );
    _log(
      'stream:video_source dispose ${_streamSummary(_videoSourceStream)} '
      'tracks=[${_trackIds(tracks)}]',
    );
    for (final track in tracks) {
      try {
        track.stop();
      } catch (_) {}
    }
    try {
      await _videoSourceStream?.dispose();
    } catch (_) {}
    _videoSourceStream = null;
    _localVideoTrackAttached = false;
  }

  Future<MediaStreamTrack?> _ensurePrimaryVideoTrack() async {
    if (_videoSourceStream == null) {
      _log('video:source create start constraints=640x360@24 facing=user');
      try {
        _videoSourceStream = await navigator.mediaDevices.getUserMedia({
          'audio': false,
          'video': {
            'facingMode': 'user',
            'width': 640,
            'height': 360,
            'frameRate': 24,
          },
        });
        final sourceTracks = List<MediaStreamTrack>.from(
          _videoSourceStream!.getVideoTracks(),
        );
        _log(
          'video:source create done source=${_streamSummary(_videoSourceStream)} '
          'tracks=[${_trackStates(sourceTracks)}]',
        );
      } catch (error) {
        _log('diagnostic:warning video-source create failed error=$error');
        rethrow;
      }
    }
    final sourceTracks = List<MediaStreamTrack>.from(
      _videoSourceStream!.getVideoTracks(),
    );
    if (sourceTracks.isEmpty) {
      _log(
        'video:source missing-track '
        'source=${_streamSummary(_videoSourceStream)}',
      );
      return null;
    }
    _log('video:source primary track=${_trackState(sourceTracks.first)}');
    return sourceTracks.first;
  }

  MediaStreamTrack? _resolvePrimaryVideoTrack(MediaStream? localStream) {
    final localTracks = List<MediaStreamTrack>.from(
      localStream?.getVideoTracks() ?? const <MediaStreamTrack>[],
    );
    if (localTracks.isNotEmpty) {
      return localTracks.first;
    }
    final sourceTracks = List<MediaStreamTrack>.from(
      _videoSourceStream?.getVideoTracks() ?? const <MediaStreamTrack>[],
    );
    if (sourceTracks.isNotEmpty) {
      return sourceTracks.first;
    }
    return null;
  }

  Future<void> _setTrackEnabled(
    MediaStreamTrack track, {
    required bool enabled,
    required String reason,
  }) async {
    if (track.enabled == enabled) {
      return;
    }
    track.enabled = enabled;
    _log('video:track state track=${track.id} enabled=$enabled reason=$reason');
  }

  Future<void> _ensureSenderBoundToTrack({
    required MediaStream localStream,
    required MediaStreamTrack track,
    required RTCRtpSender? Function() getVideoSendSender,
    required RTCRtpTransceiver? Function() getVideoSendTransceiver,
    required void Function(RTCRtpSender? sender) setVideoSendSender,
  }) async {
    final sender = getVideoSendSender() ?? getVideoSendTransceiver()?.sender;
    if (sender == null) {
      _log(
        'diagnostic:warning video-sender missing action=wait-renegotiation '
        'track=${_trackState(track)}',
      );
      return;
    }
    final oldTrackId = sender.track?.id;
    if (oldTrackId == track.id) {
      await _bindSenderStreams(sender: sender, localStream: localStream);
      setVideoSendSender(sender);
      _log(
        'video:sender already-bound track=${track.id} '
        'senderId=${sender.senderId}',
      );
      return;
    }
    await sender.replaceTrack(track);
    await _bindSenderStreams(sender: sender, localStream: localStream);
    setVideoSendSender(sender);
    _log(
      'video:sender replaceTrack stable old=$oldTrackId new=${track.id} '
      'senderId=${sender.senderId}',
    );
  }

  Future<void> _bindSenderStreams({
    required RTCRtpSender sender,
    required MediaStream localStream,
  }) async {
    try {
      await sender.setStreams(<MediaStream>[localStream]);
      _log(
        'video:sender setStreams stream=${localStream.id} '
        'senderId=${sender.senderId}',
      );
    } catch (error) {
      _log(
        'diagnostic:warning video:sender setStreams failed '
        'stream=${localStream.id} senderId=${sender.senderId} error=$error',
      );
    }
  }
}
