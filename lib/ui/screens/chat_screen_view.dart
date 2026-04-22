import 'dart:async';

import 'package:flutter/material.dart';

import 'chat_screen_helpers.dart';
import '../theme/app_theme.dart';
import 'chat_screen_styles.dart';

class ChatStatusBanner extends StatelessWidget {
  final String statusText;
  final Color statusColor;

  const ChatStatusBanner({
    super.key,
    required this.statusText,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: ChatScreenStyles.statusPadding,
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(ChatScreenStyles.statusRadius),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatComposer extends StatelessWidget {
  final TextEditingController textController;
  final bool isSendingText;
  final bool isRecordingVoice;
  final bool hasStoppedRecording;
  final Duration recordingDuration;
  final String? replySenderLabel;
  final String? replyTextPreview;
  final VoidCallback onAttachPressed;
  final Future<void> Function() onVoicePressed;
  final VoidCallback onSendPressed;
  final VoidCallback onCancelReply;

  const ChatComposer({
    super.key,
    required this.textController,
    required this.isSendingText,
    required this.isRecordingVoice,
    required this.hasStoppedRecording,
    required this.recordingDuration,
    required this.replySenderLabel,
    required this.replyTextPreview,
    required this.onAttachPressed,
    required this.onVoicePressed,
    required this.onSendPressed,
    required this.onCancelReply,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = !isSendingText && textController.text.trim().isNotEmpty;
    return Container(
      padding: ChatScreenStyles.composerContainerPadding,
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(ChatScreenStyles.composerRadius),
        border: Border.all(color: AppTheme.stroke),
        boxShadow: [
          BoxShadow(
            color: AppTheme.ink.withValues(alpha: 0.05),
            blurRadius: ChatScreenStyles.composerShadowBlur,
            offset: ChatScreenStyles.composerShadowOffset,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTextPreview != null && replyTextPreview!.trim().isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(6, 4, 6, 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(18),
                border: Border(
                  left: BorderSide(color: AppTheme.accent, width: 3),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          replySenderLabel?.trim().isNotEmpty == true
                              ? 'Ответ: ${replySenderLabel!}'
                              : 'Ответ на сообщение',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: AppTheme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          replyTextPreview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.ink,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onCancelReply,
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Отменить ответ',
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: isRecordingVoice || hasStoppedRecording
                    ? null
                    : onAttachPressed,
                icon: const Icon(Icons.attach_file_rounded),
              ),
              Expanded(
                child: _buildComposerInput(context, canSend),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  unawaited(onVoicePressed());
                },
                icon: Icon(
                  isRecordingVoice
                      ? Icons.stop_circle_outlined
                      : Icons.mic_none_rounded,
                  color: isRecordingVoice ? Colors.redAccent : null,
                ),
              ),
              FilledButton(
                onPressed: isRecordingVoice
                    ? null
                    : hasStoppedRecording
                        ? onSendPressed
                        : canSend
                            ? onSendPressed
                            : null,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                  shape: const CircleBorder(),
                  backgroundColor: AppTheme.accent,
                ),
                child: const Icon(Icons.north_east_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComposerInput(BuildContext context, bool canSend) {
    if (isRecordingVoice) {
      return Container(
        padding: ChatScreenStyles.composerTextPadding,
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Идёт запись ${ChatScreenHelpers.formatComposerDuration(recordingDuration)}',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (hasStoppedRecording) {
      return Container(
        padding: ChatScreenStyles.composerTextPadding,
        child: Row(
          children: [
            const Icon(Icons.mic),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Голосовое сообщение готово',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return TextField(
      controller: textController,
      minLines: 1,
      maxLines: 5,
      textInputAction: TextInputAction.send,
      onSubmitted: (_) {
        if (canSend) {
          onSendPressed();
        }
      },
      decoration: const InputDecoration(
        hintText: 'Сообщение',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        contentPadding: ChatScreenStyles.composerTextPadding,
      ),
    );
  }
}
