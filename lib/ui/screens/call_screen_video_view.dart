import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/runtime/app_file_logger.dart';

class VideoStreamView extends StatefulWidget {
  final MediaStream? stream;
  final String? trackId;
  final bool active;
  final bool mirrored;
  final Widget placeholder;

  const VideoStreamView({
    super.key,
    required this.stream,
    this.trackId,
    required this.active,
    required this.mirrored,
    required this.placeholder,
  });

  @override
  State<VideoStreamView> createState() => _VideoStreamViewState();
}

class _VideoStreamViewState extends State<VideoStreamView> {
  final RTCVideoRenderer _renderer = RTCVideoRenderer();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void didUpdateWidget(covariant VideoStreamView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSignature = _streamSignature(oldWidget.stream);
    final newSignature = _streamSignature(widget.stream);
    final becameActive = !oldWidget.active && widget.active;
    if (oldSignature != newSignature ||
        becameActive ||
        oldWidget.trackId != widget.trackId ||
        oldWidget.stream?.id != widget.stream?.id ||
        oldWidget.active != widget.active) {
      AppFileLogger.log(
        '[call_screen] renderer:update active=${widget.active} '
        'streamId=${widget.stream?.id} '
        'streamVideo=${widget.stream?.getVideoTracks().length ?? 0} '
        'trackId=${widget.trackId}',
        name: 'App',
      );
    }
    if (oldSignature != newSignature || becameActive) {
      unawaited(_applyRendererSource());
    }
  }

  Future<void> _init() async {
    await _renderer.initialize();
    await _applyRendererSource();
    if (!mounted) {
      return;
    }
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    unawaited(_renderer.setSrcObject(stream: null));
    _renderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || !widget.active || !_hasVideo(widget.stream)) {
      return widget.placeholder;
    }
    return RTCVideoView(
      _renderer,
      mirror: widget.mirrored,
      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
    );
  }

  bool _hasVideo(MediaStream? stream) {
    if (widget.trackId != null && stream != null) {
      return true;
    }
    return (stream?.getVideoTracks().isNotEmpty ?? false);
  }

  Future<void> _applyRendererSource() async {
    final stream = widget.stream;
    final trackId = widget.trackId ?? _selectedVideoTrackId(stream);
    AppFileLogger.log(
      '[call_screen] renderer:apply active=${widget.active} '
      'streamId=${stream?.id} '
      'streamVideo=${stream?.getVideoTracks().length ?? 0} '
      'selectedTrackId=$trackId',
      name: 'App',
    );
    if (trackId == null) {
      await _renderer.setSrcObject(stream: null);
      return;
    }
    final currentSrc = _renderer.srcObject;
    final currentTrackId = currentSrc == null
        ? null
        : _selectedVideoTrackId(currentSrc);
    if (currentSrc?.id == stream?.id && currentTrackId != trackId) {
      await _renderer.setSrcObject(stream: null);
    }
    await _renderer.setSrcObject(
      stream: stream,
      trackId: trackId,
    );
  }

  String? _selectedVideoTrackId(MediaStream? stream) {
    if (stream == null) {
      return null;
    }
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) {
      return null;
    }
    return tracks.last.id;
  }

  String _streamSignature(MediaStream? stream) {
    if (stream == null) {
      return 'null';
    }
    final videoTracks = stream.getVideoTracks();
    final videoIds = videoTracks.map((track) => track.id).join(',');
    final selectedTrackId = widget.trackId ?? _selectedVideoTrackId(stream) ?? 'none';
    return '${stream.id}|$videoIds|${videoTracks.length}|$selectedTrackId';
  }
}
