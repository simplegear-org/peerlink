import 'package:flutter/material.dart';

import '../../core/runtime/diagnostic_log.dart' as diag;
import '../models/message.dart';

class MessageVideoPreview extends StatelessWidget {
  static final Set<String> _loggedFrames = <String>{};

  final Message message;
  final bool hasLocalFile;

  const MessageVideoPreview({
    super.key,
    required this.message,
    required this.hasLocalFile,
  });

  @override
  Widget build(BuildContext context) {
    _logFrameState('black-placeholder');
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: AspectRatio(
        aspectRatio: 1,
        child: SizedBox(
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              const ColoredBox(color: Colors.black),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.38),
                    ),
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
      ),
    );
  }

  void _logFrameState(String event, {Object? error}) {
    final key = '$event|${message.id}|${message.thumbnailPath ?? ""}';
    if (!_loggedFrames.add(key)) {
      return;
    }
    diag.log(
      '[chat_media] video-preview $event messageId=${message.id} '
      'hasLocalFile=$hasLocalFile local=${message.localFilePath ?? ""} '
      'thumbMessage=${message.thumbnailPath ?? ""} '
      'mime=${message.mimeType ?? ""} file=${message.fileName ?? ""} '
      'error=${error ?? ""}',
      name: 'chat',
      level: 900,
    );
    while (_loggedFrames.length > 600) {
      _loggedFrames.remove(_loggedFrames.first);
    }
  }
}
