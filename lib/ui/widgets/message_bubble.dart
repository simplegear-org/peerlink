import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final String? senderLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onQueueCancel;
  final VoidCallback? onReplySwipe;
  final VoidCallback? onReplyTap;
  final bool isHighlighted;

  const MessageBubble({
    super.key,
    required this.message,
    this.senderLabel,
    this.onTap,
    this.onLongPress,
    this.onQueueCancel,
    this.onReplySwipe,
    this.onReplyTap,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseBubbleColor = message.incoming
        ? AppTheme.paper
        : AppTheme.accentSoft;
    final bubbleColor = isHighlighted
        ? Color.alphaBlend(
            AppTheme.accent.withValues(alpha: 0.10),
            baseBubbleColor,
          )
        : baseBubbleColor;
    final borderColor = message.incoming
        ? AppTheme.stroke
        : AppTheme.accent.withValues(alpha: 0.22);
    final effectiveBorderColor = isHighlighted ? AppTheme.accent : borderColor;
    final alignment = message.incoming
        ? Alignment.centerLeft
        : Alignment.centerRight;
    final statusColor = _statusColor(message.status);
    final showProgress =
        message.kind == MessageKind.file &&
        (message.transferStatus != null ||
            message.transferProgress != null ||
            message.status == MessageStatus.sending);

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: onReplySwipe == null
                    ? null
                    : (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -250) {
                          onReplySwipe?.call();
                        }
                      },
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: BorderRadius.circular(22),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      color: bubbleColor,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: effectiveBorderColor,
                        width: isHighlighted ? 2 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isHighlighted
                              ? AppTheme.accent.withValues(alpha: 0.18)
                              : AppTheme.ink.withValues(alpha: 0.05),
                          blurRadius: isHighlighted ? 22 : 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (senderLabel != null &&
                            senderLabel!.trim().isNotEmpty) ...[
                          Text(
                            senderLabel!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        if (message.replyToTextPreview != null &&
                            message.replyToTextPreview!.trim().isNotEmpty) ...[
                          _ReplyPreview(
                            senderLabel: message.replyToSenderLabel,
                            textPreview: message.replyToTextPreview!,
                            onTap: onReplyTap,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (message.kind == MessageKind.file)
                          _FilePreview(message: message)
                        else
                          Text(
                            message.text,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: AppTheme.ink,
                              height: 1.35,
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (showProgress) ...[
                          _FileProgress(message: message),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatTime(message.timestamp),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppTheme.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!message.incoming) ...[
                              const SizedBox(width: 8),
                              Icon(
                                _statusIcon(message.status),
                                size: 15,
                                color: statusColor,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (message.isQueuedOutgoingTransfer && onQueueCancel != null)
              Positioned(
                top: -2,
                right: -2,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onQueueCancel,
                    customBorder: const CircleBorder(),
                    child: Ink(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.paper,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.stroke),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.ink.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _statusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return Icons.schedule;
      case MessageStatus.sent:
        return Icons.check;
      case MessageStatus.failed:
        return Icons.error_outline;
    }
  }

  Color _statusColor(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return AppTheme.accent;
      case MessageStatus.sent:
        return AppTheme.pine;
      case MessageStatus.failed:
        return Colors.red.shade400;
    }
  }

  String _formatTime(DateTime timestamp) {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ReplyPreview extends StatelessWidget {
  final String? senderLabel;
  final String textPreview;
  final VoidCallback? onTap;

  const _ReplyPreview({
    required this.senderLabel,
    required this.textPreview,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border(left: BorderSide(color: AppTheme.accent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (senderLabel != null && senderLabel!.trim().isNotEmpty)
                Text(
                  senderLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: AppTheme.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                textPreview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilePreview extends StatelessWidget {
  final Message message;

  const _FilePreview({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeBytes = message.fileSizeBytes ?? message.fileBytes?.length ?? 0;
    final sizeLabel = sizeBytes < 1024
        ? '$sizeBytes B'
        : sizeBytes < 1024 * 1024
        ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
        : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    final localFile = message.localFile;
    if (message.isImage &&
        ((localFile != null && localFile.existsSync()) ||
            message.fileBytes != null)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: localFile != null && localFile.existsSync()
            ? Image.file(
                localFile,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _unavailablePreview(context, theme, sizeLabel),
              )
            : Image.memory(
                message.fileBytes!,
                width: double.infinity,
                height: 220,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
      );
    }

    if (message.isVideo) {
      return _VideoPreview(message: message);
    }

    if (message.isAudio) {
      return _AudioPreview(message: message);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.attach_file_rounded),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.fileName ?? message.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sizeLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _unavailablePreview(
    BuildContext context,
    ThemeData theme,
    String sizeLabel,
  ) {
    return Container(
      width: double.infinity,
      height: 220,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Text(
        '${context.strings.fileUnavailableOpen}\n$sizeLabel',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppTheme.muted,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VideoPreview extends StatefulWidget {
  final Message message;

  const _VideoPreview({required this.message});

  @override
  State<_VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<_VideoPreview> {
  VideoPlayerController? _controller;
  Directory? _tempDirectory;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare(++_generation));
  }

  @override
  void didUpdateWidget(covariant _VideoPreview oldWidget) {
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
    _VideoPreviewSource? source;
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

  Future<_VideoPreviewSource?> _resolveVideoSource() async {
    final localFile = widget.message.localFile;
    if (localFile != null && await localFile.exists()) {
      return _VideoPreviewSource(file: localFile);
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
    return _VideoPreviewSource(file: file, tempDirectory: directory);
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

class _VideoPreviewSource {
  final File file;
  final Directory? tempDirectory;

  const _VideoPreviewSource({required this.file, this.tempDirectory});
}

class _AudioPreview extends StatefulWidget {
  final Message message;

  const _AudioPreview({required this.message});

  @override
  State<_AudioPreview> createState() => _AudioPreviewState();
}

class _AudioPreviewState extends State<_AudioPreview> {
  late final AudioPlayer _player;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.onDurationChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _duration = value;
      });
    });
    _player.onPositionChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _position = value;
      });
    });
    _player.onPlayerStateChanged.listen((value) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playerState = value;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final file = widget.message.localFile;
    if (file == null || !file.existsSync()) {
      return;
    }

    if (_playerState == PlayerState.playing) {
      await _player.pause();
      return;
    }

    if (_playerState == PlayerState.paused) {
      await _player.resume();
      return;
    }

    await _player.play(DeviceFileSource(file.path));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final file = widget.message.localFile;
    final hasFile = file != null && file.existsSync();
    final progressMax = _duration.inMilliseconds <= 0
        ? 1.0
        : _duration.inMilliseconds.toDouble();
    final progressValue = _position.inMilliseconds.toDouble().clamp(
      0.0,
      progressMax,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                onPressed: hasFile ? _togglePlayback : null,
                icon: Icon(
                  _playerState == PlayerState.playing
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.fileName ?? strings.voiceMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasFile ? strings.voiceMessage : strings.mediaUnavailable,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _formatAudioDuration(
                _duration > Duration.zero ? _duration : _position,
              ),
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: AppTheme.accent,
            inactiveTrackColor: AppTheme.stroke,
            thumbColor: AppTheme.accent,
            trackHeight: 3,
          ),
          child: Slider(
            value: progressValue,
            max: progressMax,
            onChanged: hasFile && _duration > Duration.zero
                ? (value) {
                    _player.seek(Duration(milliseconds: value.round()));
                  }
                : null,
          ),
        ),
      ],
    );
  }
}

String _formatAudioDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

class _FileProgress extends StatelessWidget {
  final Message message;

  const _FileProgress({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (message.transferProgress ?? 0).clamp(0.0, 1.0);
    final percent = (value * 100).round();
    final strings = context.strings;
    final isError =
        (message.transferStatus?.toLowerCase().contains('ошибка') ?? false) ||
        message.transferStatus == strings.downloadError ||
        message.transferStatus == strings.sendError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: isError ? 0 : (value == 0 ? null : value),
            minHeight: 6,
            backgroundColor: AppTheme.paper,
            valueColor: AlwaysStoppedAnimation<Color>(
              isError ? Colors.red.shade400 : AppTheme.accent,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${strings.translateTransferStatus(message.transferStatus)}${value > 0 ? " $percent%" : ""}',
          style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
        ),
      ],
    );
  }
}
