import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_local_video_track_controller.dart';
import 'call_models.dart';

class CallMediaStreamController {
  static bool _audioWarmupCompleted = false;

  final void Function(String message) _log;
  final void Function(MediaStream stream) _onLocalStream;
  final void Function(MediaStream stream) _onRemoteStream;
  final Future<MediaStream> Function(String label) _createRemoteRenderStream;
  late final CallLocalVideoTrackController _localVideoTrackController;

  MediaStream? _localStream;
  MediaStream? _remoteStream;
  bool _remoteStreamIsSynthetic = false;
  Future<void> _remoteStreamMutationQueue = Future<void>.value();

  CallMediaStreamController({
    required void Function(String message) log,
    required void Function(MediaStream stream) onLocalStream,
    required void Function(MediaStream stream) onRemoteStream,
    Future<MediaStream> Function(String label)? createRemoteRenderStream,
  }) : _log = log,
       _onLocalStream = onLocalStream,
       _onRemoteStream = onRemoteStream,
       _createRemoteRenderStream =
           createRemoteRenderStream ?? createLocalMediaStream {
    _localVideoTrackController = CallLocalVideoTrackController(log: log);
  }

  MediaStream? get localStream => _localStream;
  bool get localVideoTrackAttached =>
      _localVideoTrackController.localVideoTrackAttached;
  bool get isFrontCamera => _localVideoTrackController.isFrontCamera;
  int get localVideoTrackCount => _localStream?.getVideoTracks().length ?? 0;

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

  void resetLocalVideoAttachment() {
    _localVideoTrackController.resetAttachment();
  }

  Future<void> setMuted(bool muted) async {
    final tracks = _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[];
    for (final track in tracks) {
      track.enabled = !muted;
    }
    _log(
      'diagnostic:audio local-muted muted=$muted '
      'audioTracks=[${_trackStates(List<MediaStreamTrack>.from(tracks))}]',
    );
  }

  Future<void> refreshLocalAudioSender({
    required RTCPeerConnection peer,
    required bool muted,
    required String reason,
  }) async {
    final stream = _localStream;
    final audioTracks = List<MediaStreamTrack>.from(
      stream?.getAudioTracks() ?? const <MediaStreamTrack>[],
    );
    if (stream == null || audioTracks.isEmpty) {
      _log(
        'audio:sender refresh skipped reason="$reason" local=${_streamSummary(stream)}',
      );
      return;
    }
    final track = audioTracks.first;
    track.enabled = !muted;
    final senders = await peer.getSenders();
    final senderSummary = senders
        .map((sender) {
          final senderTrack = sender.track;
          return '${sender.senderId}:${senderTrack?.kind}:${senderTrack?.id}:'
              'enabled=${senderTrack?.enabled}:muted=${senderTrack?.muted}';
        })
        .join(',');
    _log(
      'diagnostic:warning audio-sender refresh inspect reason="$reason" '
      'localTrack=${_trackState(track)} senders=[$senderSummary]',
    );
    RTCRtpSender? audioSender;
    for (final sender in senders) {
      final senderTrack = sender.track;
      if (senderTrack?.kind == 'audio' || senderTrack?.id == track.id) {
        audioSender = sender;
        break;
      }
    }
    if (audioSender == null) {
      _log(
        'diagnostic:warning audio-sender refresh skipped reason="$reason" sender=false '
        'track=${track.id}',
      );
      return;
    }
    await audioSender.replaceTrack(track);
    _log(
      'diagnostic:warning audio-sender refresh done reason="$reason" '
      'track=${track.id} enabled=${track.enabled} senderId=${audioSender.senderId}',
    );
    _onLocalStream(stream);
  }

  Future<void> createInitialLocalStream({required bool muted}) async {
    if (_localStream != null) {
      final audioTracks = List<MediaStreamTrack>.from(
        _localStream!.getAudioTracks(),
      );
      for (final track in audioTracks) {
        track.enabled = !muted;
      }
      _log(
        'audio:local stream reused muted=$muted '
        'local=${_streamSummary(_localStream)} '
        'audioStates=[${_trackStates(audioTracks)}]',
      );
      return;
    }
    await _warmUpAudioIfNeeded();
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    final audioTracks = List<MediaStreamTrack>.from(
      _localStream!.getAudioTracks(),
    );
    for (final track in audioTracks) {
      track.enabled = !muted;
    }
    _log(
      'audio:local stream created muted=$muted '
      'local=${_streamSummary(_localStream)} '
      'audioStates=[${_trackStates(audioTracks)}]',
    );
    _onLocalStream(_localStream!);
  }

  Future<void> addInitialLocalTracksToPeer(RTCPeerConnection peer) async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    final localTracks = List<MediaStreamTrack>.from(stream.getTracks());
    for (final track in localTracks) {
      await peer.addTrack(track, stream);
      _log(
        'track:local added kind=${track.kind} track=${track.id} '
        'enabled=${track.enabled} muted=${track.muted} stream=${stream.id}',
      );
    }
  }

  Future<void> _warmUpAudioIfNeeded() async {
    if (_audioWarmupCompleted) {
      return;
    }
    _log('audio:warmup start');
    MediaStream? warmupStream;
    try {
      warmupStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
      final tracks = List<MediaStreamTrack>.from(warmupStream.getTracks());
      for (final track in tracks) {
        try {
          track.stop();
        } catch (_) {}
      }
      try {
        await warmupStream.dispose();
      } catch (_) {}
      _audioWarmupCompleted = true;
      _log('audio:warmup done');
    } catch (error) {
      _log('audio:warmup failed error=$error');
      rethrow;
    }
  }

  Future<void> flipCamera() async {
    await _localVideoTrackController.flipCamera(
      localStream: _localStream,
      onLocalStream: _onLocalStream,
    );
  }

  Future<void> syncLocalMediaTracks({
    required CallMediaType mediaType,
    required Future<void> Function() refreshVideoChannelHandles,
    required Future<void> Function() applyInitialVideoQualityProfile,
    required RTCRtpSender? Function() getVideoSendSender,
    required RTCRtpTransceiver? Function() getVideoSendTransceiver,
    required void Function(RTCRtpSender? sender) setVideoSendSender,
  }) async {
    final stream = _localStream;
    if (stream == null) {
      return;
    }
    await _localVideoTrackController.syncLocalVideoTrack(
      localStream: stream,
      mediaType: mediaType,
      refreshVideoChannelHandles: refreshVideoChannelHandles,
      applyInitialVideoQualityProfile: applyInitialVideoQualityProfile,
      getVideoSendSender: getVideoSendSender,
      getVideoSendTransceiver: getVideoSendTransceiver,
      setVideoSendSender: setVideoSendSender,
      onLocalStream: _onLocalStream,
    );
  }

  Future<void> disposeLocalStream() async {
    final tracks = List<MediaStreamTrack>.from(
      _localStream?.getTracks() ?? const <MediaStreamTrack>[],
    );
    _log(
      'stream:local dispose ${_streamSummary(_localStream)} '
      'tracks=[${_trackIds(tracks)}]',
    );
    for (final track in tracks) {
      try {
        track.stop();
      } catch (_) {}
    }
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _localVideoTrackController.resetAttachment();
  }

  Future<void> disposeVideoSourceStream() async {
    await _localVideoTrackController.disposeVideoSourceStream();
  }

  Future<void> disposeRemoteStream() async {
    await _serializeRemoteStreamMutation(() async {
      try {
        if (_remoteStream != null && _remoteStreamIsSynthetic) {
          await _remoteStream?.dispose();
        }
      } catch (_) {}
      _remoteStream = null;
      _remoteStreamIsSynthetic = false;
    });
  }

  Future<void> clearRemoteRenderStreamTracks() async {
    await _serializeRemoteStreamMutation(() async {
      final stream = _remoteStream;
      if (stream == null) {
        return;
      }
      if (!_remoteStreamIsSynthetic) {
        _remoteStream = null;
        _remoteStreamIsSynthetic = false;
        _log('stream:remote cleared native ${_streamSummary(stream)}');
        return;
      }
      final tracks = List<MediaStreamTrack>.from(stream.getTracks());
      for (final track in tracks) {
        try {
          await stream.removeTrack(track);
        } catch (_) {}
      }
      _log(
        'stream:remote cleared synthetic ${_streamSummary(stream)} '
        'tracks=[${_trackIds(tracks)}]',
      );
      _onRemoteStream(stream);
    });
  }

  Future<void> ingestRemoteStream(
    MediaStream incoming, {
    MediaStreamTrack? preferredTrack,
  }) async {
    await _serializeRemoteStreamMutation(() async {
      final incomingAudioTracks = List<MediaStreamTrack>.from(
        incoming.getAudioTracks(),
      );
      final incomingVideoTracks = List<MediaStreamTrack>.from(
        incoming.getVideoTracks(),
      );
      if (incomingVideoTracks.isNotEmpty) {
        final previousStream = _remoteStream;
        final previousVideoTrackId = previousStream
            ?.getVideoTracks()
            .lastOrNull
            ?.id;
        final preferredVideoTrack = preferredTrack?.kind == 'video'
            ? incomingVideoTracks.cast<MediaStreamTrack?>().firstWhere(
                (track) => track?.id == preferredTrack!.id,
                orElse: () => null,
              )
            : null;
        final activeVideoTrack =
            preferredVideoTrack ?? incomingVideoTracks.last;
        final changed =
            !identical(previousStream, incoming) ||
            previousVideoTrackId != activeVideoTrack.id ||
            _remoteStreamIsSynthetic;

        if (previousStream != null && _remoteStreamIsSynthetic) {
          try {
            await previousStream.dispose();
          } catch (_) {}
        }
        _remoteStream = incoming;
        _remoteStreamIsSynthetic = false;
        _log(
          'stream:remote native '
          'incoming=${_streamSummary(incoming)} '
          'preferred=${preferredTrack?.kind}:${preferredTrack?.id} '
          'activeVideo=${activeVideoTrack.id} '
          'changed=$changed',
        );
        if (changed) {
          _onRemoteStream(incoming);
        }
        return;
      }
      final renderStream = await _ensureRemoteRenderStream();
      final currentAudioTracks = List<MediaStreamTrack>.from(
        renderStream.getAudioTracks(),
      );
      final currentVideoTracks = List<MediaStreamTrack>.from(
        renderStream.getVideoTracks(),
      );
      final preferredAudioTrack = preferredTrack?.kind == 'audio'
          ? incomingAudioTracks.cast<MediaStreamTrack?>().firstWhere(
              (track) => track?.id == preferredTrack!.id,
              orElse: () => null,
            )
          : null;
      final preferredVideoTrack = preferredTrack?.kind == 'video'
          ? incomingVideoTracks.cast<MediaStreamTrack?>().firstWhere(
              (track) => track?.id == preferredTrack!.id,
              orElse: () => null,
            )
          : null;

      final effectiveTracks = <MediaStreamTrack>[
        if (preferredAudioTrack != null)
          preferredAudioTrack
        else if (incomingAudioTracks.isNotEmpty)
          incomingAudioTracks.last
        else if (currentAudioTracks.isNotEmpty)
          currentAudioTracks.last,
        if (preferredVideoTrack != null)
          preferredVideoTrack
        else if (incomingVideoTracks.isNotEmpty)
          incomingVideoTracks.last
        else if (currentVideoTracks.isNotEmpty)
          currentVideoTracks.last,
      ];

      var activeStream = renderStream;
      var changed = false;
      for (final track in effectiveTracks) {
        final mergeResult = await _mergeRemoteTrack(activeStream, track);
        activeStream = mergeResult.stream;
        changed = changed || mergeResult.changed;
      }
      _log(
        'stream:remote render '
        'incoming=${_streamSummary(incoming)} '
        'render=${_streamSummary(activeStream)} '
        'preferred=${preferredTrack?.kind}:${preferredTrack?.id} '
        'nativeAudio=${incoming.getAudioTracks().length} '
        'nativeVideo=${incoming.getVideoTracks().length} '
        'audio=${activeStream.getAudioTracks().length} '
        'video=${activeStream.getVideoTracks().length}',
      );
      if (changed) {
        _onRemoteStream(activeStream);
      }
    });
  }

  Future<void> attachRemoteTrack(MediaStreamTrack track) async {
    await _serializeRemoteStreamMutation(() async {
      final stream = await _ensureRemoteRenderStream();
      final mergeResult = await _mergeRemoteTrack(stream, track);
      final activeStream = mergeResult.stream;
      _log(
        'stream:remote track=${track.kind} '
        'trackId=${track.id} '
        'render=${_streamSummary(activeStream)} '
        'audio=${activeStream.getAudioTracks().length} '
        'video=${activeStream.getVideoTracks().length}',
      );
      if (mergeResult.changed) {
        _onRemoteStream(activeStream);
      }
    });
  }

  Future<MediaStream> _ensureRemoteRenderStream() async {
    var stream = _remoteStream;
    if (stream != null) {
      return stream;
    }
    stream = await _createRemoteRenderStream('remote');
    _remoteStream = stream;
    _remoteStreamIsSynthetic = true;
    _log('stream:remote created synthetic ${_streamSummary(stream)}');
    return stream;
  }

  Future<({MediaStream stream, bool changed})> _mergeRemoteTrack(
    MediaStream stream,
    MediaStreamTrack track,
  ) async {
    final existingTracks = track.kind == 'video'
        ? List<MediaStreamTrack>.from(stream.getVideoTracks())
        : List<MediaStreamTrack>.from(stream.getAudioTracks());
    final alreadyAttached = existingTracks.any(
      (existing) => existing.id == track.id,
    );
    if (alreadyAttached) {
      return (stream: stream, changed: false);
    }
    for (final existing in existingTracks) {
      try {
        await stream.removeTrack(existing);
      } catch (_) {}
      _log(
        'stream:remote replaced kind=${track.kind} '
        'oldTrack=${existing.id} newTrack=${track.id} '
        'stream=${_streamSummary(stream)}',
      );
    }
    await stream.addTrack(track);
    _log(
      'stream:remote addTrack kind=${track.kind} '
      'track=${track.id} stream=${_streamSummary(stream)}',
    );
    return (stream: stream, changed: true);
  }

  Future<void> _serializeRemoteStreamMutation(
    Future<void> Function() action,
  ) async {
    final previous = _remoteStreamMutationQueue;
    final completer = Completer<void>();
    _remoteStreamMutationQueue = completer.future;
    try {
      await previous;
      await action();
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}
