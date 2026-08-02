import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import 'message_bubble_audio_preview.dart';
import 'message_bubble_video_preview.dart';

class MessageFilePreview extends StatelessWidget {
  final Message message;

  const MessageFilePreview({super.key, required this.message});

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
      return MessageVideoPreview(message: message);
    }

    if (message.isAudio) {
      return MessageAudioPreview(message: message);
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
