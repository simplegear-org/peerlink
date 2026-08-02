import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageAudioPreview extends StatefulWidget {
  final Message message;

  const MessageAudioPreview({super.key, required this.message});

  @override
  State<MessageAudioPreview> createState() => MessageAudioPreviewState();
}

class MessageAudioPreviewState extends State<MessageAudioPreview> {
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
