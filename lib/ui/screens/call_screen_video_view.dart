import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

bool shouldRefreshVideoRenderer({
  required String oldSignature,
  required String newSignature,
  required String? oldTrackId,
  required String? newTrackId,
  required String? oldStreamId,
  required String? newStreamId,
  required bool oldActive,
  required bool newActive,
}) {
  return oldSignature != newSignature ||
      oldTrackId != newTrackId ||
      oldStreamId != newStreamId ||
      oldActive != newActive;
}

String? resolveRendererTrackId({
  required List<String> availableTrackIds,
  required String? requestedTrackId,
}) {
  if (availableTrackIds.isEmpty) {
    return null;
  }
  if (requestedTrackId != null &&
      availableTrackIds.contains(requestedTrackId)) {
    return requestedTrackId;
  }
  return availableTrackIds.last;
}

bool hasRenderableVideo({
  required List<String> availableTrackIds,
  required String? requestedTrackId,
}) {
  return resolveRendererTrackId(
        availableTrackIds: availableTrackIds,
        requestedTrackId: requestedTrackId,
      ) !=
      null;
}

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
    final oldSignature = _streamSignature(oldWidget.stream, oldWidget.trackId);
    final newSignature = _streamSignature(widget.stream, widget.trackId);
    if (shouldRefreshVideoRenderer(
      oldSignature: oldSignature,
      newSignature: newSignature,
      oldTrackId: oldWidget.trackId,
      newTrackId: widget.trackId,
      oldStreamId: oldWidget.stream?.id,
      newStreamId: widget.stream?.id,
      oldActive: oldWidget.active,
      newActive: widget.active,
    )) {
      unawaited(_applyRendererSource());
    }
  }

  Future<void> _init() async {
    await _renderer.initialize();
    if (!mounted) {
      return;
    }
    _initialized = true;
    await _applyRendererSource();
    if (!mounted) {
      return;
    }
    setState(() {});
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
    final availableTrackIds =
        stream
            ?.getVideoTracks()
            .map((track) => track.id)
            .whereType<String>()
            .toList() ??
        const <String>[];
    return hasRenderableVideo(
      availableTrackIds: availableTrackIds,
      requestedTrackId: widget.trackId,
    );
  }

  Future<void> _applyRendererSource() async {
    final stream = widget.stream;
    if (!_initialized && _renderer.textureId == null) {
      return;
    }
    final currentSrc = _renderer.srcObject;
    if (!widget.active) {
      if (currentSrc != null) {
        await _renderer.setSrcObject(stream: null);
      }
      return;
    }
    final availableTrackIds =
        stream
            ?.getVideoTracks()
            .map((track) => track.id)
            .whereType<String>()
            .toList() ??
        const <String>[];
    final requestedTrackId = widget.trackId;
    final selectedTrackId = resolveRendererTrackId(
      availableTrackIds: availableTrackIds,
      requestedTrackId: requestedTrackId,
    );
    if (selectedTrackId == null) {
      if (currentSrc != null) {
        await _renderer.setSrcObject(stream: null);
      }
      return;
    }
    final currentTrackId = currentSrc == null
        ? null
        : _selectedVideoTrackId(currentSrc);
    if (currentSrc?.id == stream?.id && currentTrackId == selectedTrackId) {
      return;
    }
    if (currentSrc?.id == stream?.id &&
        currentTrackId != null &&
        currentTrackId != selectedTrackId) {
      await _renderer.setSrcObject(stream: null);
    }
    try {
      await _renderer.setSrcObject(stream: stream, trackId: selectedTrackId);
    } catch (_) {
      if (stream == null) {
        rethrow;
      }
      await _renderer.setSrcObject(stream: null);
      await _renderer.setSrcObject(stream: stream);
    }
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

  String _streamSignature(MediaStream? stream, String? trackId) {
    if (stream == null) {
      return 'null';
    }
    final videoTracks = stream.getVideoTracks();
    final videoIds = videoTracks.map((track) => track.id).join(',');
    final selectedTrackId = trackId ?? _selectedVideoTrackId(stream) ?? 'none';
    return '${stream.id}|$videoIds|${videoTracks.length}|$selectedTrackId';
  }
}
