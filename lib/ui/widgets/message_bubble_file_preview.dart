// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/runtime/diagnostic_log.dart' as diag;
import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import '../state/chat_media_thumbnail_service.dart';
import 'message_bubble_audio_preview.dart';
import 'message_file_availability_cache.dart';
import 'message_bubble_video_preview.dart';

class MessageFilePreview extends StatefulWidget {
  final Message message;

  const MessageFilePreview({super.key, required this.message});

  @override
  State<MessageFilePreview> createState() => _MessageFilePreviewState();
}

class _MessageFilePreviewState extends State<MessageFilePreview> {
  static final Set<String> _loggedMediaMessages = <String>{};
  bool? _hasLocalFile;
  int _generation = 0;

  Message get message => widget.message;

  @override
  void initState() {
    super.initState();
    _hasLocalFile = MessageFileAvailabilityCache.cached(message.localFilePath);
    _logMediaPreviewState('init');
    unawaited(_resolveLocalFile(++_generation));
  }

  @override
  void didUpdateWidget(covariant MessageFilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.localFilePath == widget.message.localFilePath &&
        oldWidget.message.thumbnailPath == widget.message.thumbnailPath &&
        oldWidget.message.id == widget.message.id) {
      return;
    }
    _hasLocalFile = MessageFileAvailabilityCache.cached(message.localFilePath);
    _logMediaPreviewState('update');
    unawaited(_resolveLocalFile(++_generation));
  }

  Future<void> _resolveLocalFile(int generation) async {
    final exists = await MessageFileAvailabilityCache.exists(
      message.localFilePath,
    );
    if (!mounted || generation != _generation || _hasLocalFile == exists) {
      return;
    }
    setState(() {
      _hasLocalFile = exists;
    });
    if (message.isVideo || message.isImage) {
      diag.log(
        '[chat_media] preview file-exists messageId=${message.id} '
        'type=${_mediaTypeLabel(message)} exists=$exists '
        'local=${message.localFilePath ?? ""} thumb=${message.thumbnailPath ?? ""}',
        name: 'chat',
        level: 900,
      );
    }
  }

  void _logMediaPreviewState(String event) {
    if (!message.isMedia) {
      return;
    }
    final key =
        '$event|${message.id}|${message.localFilePath}|${message.thumbnailPath}';
    if (!_loggedMediaMessages.add(key)) {
      return;
    }
    diag.log(
      '[chat_media] preview $event messageId=${message.id} '
      'type=${_mediaTypeLabel(message)} incoming=${message.incoming} '
      'status=${message.status.name} transfer=${message.transferStatus ?? ""} '
      'cachedLocal=$_hasLocalFile local=${message.localFilePath ?? ""} '
      'thumb=${message.thumbnailPath ?? ""} '
      'embeddedBytes=${message.fileDataBase64?.length ?? 0} '
      'mime=${message.mimeType ?? ""} file=${message.fileName ?? ""}',
      name: 'chat',
      level: 900,
    );
    while (_loggedMediaMessages.length > 600) {
      _loggedMediaMessages.remove(_loggedMediaMessages.first);
    }
  }

  String _mediaTypeLabel(Message message) {
    if (message.isVideo) {
      return 'video';
    }
    if (message.isImage) {
      return 'image';
    }
    if (message.isAudio) {
      return 'audio';
    }
    return 'file';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sizeBytes = message.fileSizeBytes ?? 0;
    final imageCacheWidth = (360 * MediaQuery.devicePixelRatioOf(context))
        .round();
    final sizeLabel = sizeBytes < 1024
        ? '$sizeBytes B'
        : sizeBytes < 1024 * 1024
        ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
        : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    final thumbnailFile = _currentThumbnailFile(message);
    final localImageFile = _hasLocalFile == true ? message.localFile : null;
    if (message.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: thumbnailFile != null
            ? Image.file(
                thumbnailFile,
                width: double.infinity,
                height: 220,
                cacheWidth: imageCacheWidth,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _imagePlaceholder(context, theme, sizeLabel),
              )
            : localImageFile != null
            ? Image.file(
                localImageFile,
                width: double.infinity,
                height: 220,
                cacheWidth: imageCacheWidth,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) =>
                    _imagePlaceholder(context, theme, sizeLabel),
              )
            : _imagePlaceholder(context, theme, sizeLabel),
      );
    }

    if (message.isVideo) {
      final hasEmbeddedBytes = message.fileDataBase64?.isNotEmpty == true;
      return MessageVideoPreview(
        message: message,
        hasLocalFile: _hasLocalFile == true || hasEmbeddedBytes,
      );
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

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  File? _currentThumbnailFile(Message message) {
    final path = _thumbnailPath(message);
    if (path == null ||
        path.isEmpty ||
        !path.endsWith(ChatMediaThumbnailService.thumbnailSuffix)) {
      return null;
    }
    return File(path);
  }

  String? _thumbnailPath(Message message) {
    final path = message.thumbnailPath?.trim();
    if (path == null ||
        path.isEmpty ||
        !path.endsWith(ChatMediaThumbnailService.thumbnailSuffix)) {
      return null;
    }
    return path;
  }

  Widget _imagePlaceholder(
    BuildContext context,
    ThemeData theme,
    String sizeLabel,
  ) {
    return Container(
      width: double.infinity,
      height: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_rounded, size: 42, color: AppTheme.muted),
          const SizedBox(height: 10),
          Text(
            message.fileName ?? context.strings.photo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sizeLabel,
            style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
