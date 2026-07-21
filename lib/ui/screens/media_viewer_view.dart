import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'media_viewer_styles.dart';

class MediaImageViewer extends StatelessWidget {
  final Message message;

  const MediaImageViewer({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final bytes = message.fileBytes;
    final localFile = message.localFile;
    if (localFile != null && localFile.existsSync()) {
      return InteractiveViewer(
        minScale: MediaViewerStyles.imageMinScale,
        maxScale: MediaViewerStyles.imageMaxScale,
        child: Center(
          child: Image.file(
            localFile,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (context, error, stackTrace) => Text(
              context.strings.imageUnavailable,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ),
      );
    }

    if (bytes == null) {
      return Center(
        child: Text(
          context.strings.imageUnavailable,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return InteractiveViewer(
      minScale: MediaViewerStyles.imageMinScale,
      maxScale: MediaViewerStyles.imageMaxScale,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class MediaVideoPage extends StatefulWidget {
  final Message message;

  const MediaVideoPage({super.key, required this.message});

  @override
  State<MediaVideoPage> createState() => _MediaVideoPageState();
}

class _MediaVideoPageState extends State<MediaVideoPage> {
  VideoPlayerController? _videoController;
  Future<void>? _videoInit;
  File? _tempVideoFile;
  bool _ownsTempVideoFile = false;

  @override
  void initState() {
    super.initState();
    _videoInit = _prepareVideo();
  }

  Future<void> _prepareVideo() async {
    final bytes = widget.message.fileBytes;
    final fileName = widget.message.fileName ?? '${widget.message.id}.mp4';
    final localFile = widget.message.localFile;
    if (localFile != null && await localFile.exists()) {
      final controller = VideoPlayerController.file(localFile);
      _tempVideoFile = localFile;
      _ownsTempVideoFile = false;
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (bytes == null) {
      throw StateError('video_not_loaded');
    }

    final dir = await Directory.systemTemp.createTemp('peerlink-media-');
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    _tempVideoFile = file;
    _ownsTempVideoFile = true;

    final controller = VideoPlayerController.file(file);
    _videoController = controller;
    await controller.initialize();
    await controller.setLooping(true);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    final file = _tempVideoFile;
    if (file != null && _ownsTempVideoFile) {
      unawaited(file.parent.delete(recursive: true));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialization = _videoInit;
    if (initialization == null) {
      return Center(
        child: Text(
          context.strings.videoUnavailable,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return FutureBuilder<void>(
      future: initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Center(
            child: CircularProgressIndicator(color: AppTheme.accentSoft),
          );
        }

        if (snapshot.hasError || _videoController == null) {
          final error = snapshot.error;
          final errorText =
              error is StateError && error.message == 'video_not_loaded'
              ? context.strings.videoNotLoaded
              : error ?? context.strings.videoSourceUnavailable;
          return Center(
            child: Text(
              context.strings.videoOpenError(errorText),
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          );
        }

        final controller = _videoController!;
        return Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? MediaViewerStyles.fallbackAspectRatio
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final playing = value.isPlaying;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (playing) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                    setState(() {});
                  },
                  child: AnimatedOpacity(
                    opacity: playing ? 0 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Container(
                      width: MediaViewerStyles.playOverlaySize,
                      height: MediaViewerStyles.playOverlaySize,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: MediaViewerStyles.playIconSize,
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              left: MediaViewerStyles.controlsPosition.left,
              right: MediaViewerStyles.controlsPosition.right,
              bottom: MediaViewerStyles.controlsPosition.bottom,
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final duration = value.duration;
                  final position = value.position;
                  final totalMs = duration.inMilliseconds;
                  final currentMs = position.inMilliseconds.clamp(
                    0,
                    totalMs <= 0 ? 0 : totalMs,
                  );
                  final sliderMax = totalMs <= 0 ? 1.0 : totalMs.toDouble();
                  final sliderValue = currentMs.toDouble().clamp(
                    0.0,
                    sliderMax,
                  );

                  return Container(
                    padding: MediaViewerStyles.controlsPadding,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(
                        MediaViewerStyles.controlsRadius,
                      ),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.accentSoft,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            overlayColor: AppTheme.accentSoft.withValues(
                              alpha: 0.18,
                            ),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: sliderValue,
                            max: sliderMax,
                            onChanged: totalMs <= 0
                                ? null
                                : (value) {
                                    controller.seekTo(
                                      Duration(milliseconds: value.round()),
                                    );
                                  },
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formatMediaDuration(position),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              formatMediaDuration(duration),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

String formatMediaDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  String twoDigits(int value) => value.toString().padLeft(2, '0');

  if (hours > 0) {
    return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '${twoDigits(minutes)}:${twoDigits(seconds)}';
}
