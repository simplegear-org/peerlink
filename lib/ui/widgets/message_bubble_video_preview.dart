import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/message.dart';

class MessageVideoPreview extends StatefulWidget {
  final Message message;

  const MessageVideoPreview({super.key, required this.message});

  @override
  State<MessageVideoPreview> createState() => MessageVideoPreviewState();
}

class MessageVideoPreviewState extends State<MessageVideoPreview> {
  VideoPlayerController? _controller;
  Directory? _tempDirectory;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare(++_generation));
  }

  @override
  void didUpdateWidget(covariant MessageVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sourceKey(oldWidget.message) == _sourceKey(widget.message)) {
      return;
    }
    _generation++;
    unawaited(_disposeControllerAndTemp());
    unawaited(_prepare(_generation));
  }

  String _sourceKey(Message message) {
    return [
      message.id,
      message.localFilePath ?? '',
      message.fileDataBase64?.length ?? 0,
    ].join('|');
  }

  Future<void> _prepare(int generation) async {
    MessageVideoPreviewSource? source;
    VideoPlayerController? controller;

    try {
      source = await _resolveVideoSource();
      if (source == null || !await source.file.exists()) {
        await _deleteTempDirectory(source?.tempDirectory);
        return;
      }

      controller = VideoPlayerController.file(source.file);
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(0);
      await controller.seekTo(_previewPosition(controller.value.duration));
      await controller.pause();
    } catch (_) {
      await controller?.dispose();
      await _deleteTempDirectory(source?.tempDirectory);
      return;
    }

    final initializedController = controller;
    final initializedSource = source;

    if (!mounted || generation != _generation) {
      await initializedController.dispose();
      await _deleteTempDirectory(initializedSource.tempDirectory);
      return;
    }

    setState(() {
      _controller = initializedController;
      _tempDirectory = initializedSource.tempDirectory;
    });
  }

  Future<MessageVideoPreviewSource?> _resolveVideoSource() async {
    final localFile = widget.message.localFile;
    if (localFile != null && await localFile.exists()) {
      return MessageVideoPreviewSource(file: localFile);
    }

    final bytes = widget.message.fileBytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final extension = widget.message.fileExtension ?? 'mp4';
    final directory = await Directory.systemTemp.createTemp(
      'peerlink-video-preview-',
    );
    final file = File('${directory.path}/preview.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return MessageVideoPreviewSource(file: file, tempDirectory: directory);
  }

  Duration _previewPosition(Duration duration) {
    if (duration <= const Duration(milliseconds: 700)) {
      return Duration.zero;
    }
    return const Duration(milliseconds: 500);
  }

  Future<void> _disposeControllerAndTemp() async {
    final controller = _controller;
    final tempDirectory = _tempDirectory;
    _controller = null;
    _tempDirectory = null;
    if (controller != null) {
      await controller.dispose();
    }

    await _deleteTempDirectory(tempDirectory);
  }

  Future<void> _deleteTempDirectory(Directory? tempDirectory) async {
    if (tempDirectory != null) {
      try {
        if (await tempDirectory.exists()) {
          await tempDirectory.delete(recursive: true);
        }
      } catch (_) {
        // Temporary previews are best-effort cleanup only.
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    unawaited(_disposeControllerAndTemp());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        width: double.infinity,
        height: 220,
        child: Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [
            _buildVideoFrame(),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Color(0x00000000),
                    Color(0x8A000000),
                  ],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 46,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoFrame() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return _videoFallback();
    }

    final size = controller.value.size;
    if (size.width <= 0 || size.height <= 0) {
      return _videoFallback();
    }

    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(controller),
      ),
    );
  }

  Widget _videoFallback() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F2D3A), Color(0xFF0F1720)],
        ),
      ),
    );
  }
}

class MessageVideoPreviewSource {
  final File file;
  final Directory? tempDirectory;

  const MessageVideoPreviewSource({required this.file, this.tempDirectory});
}
