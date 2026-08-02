import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_theme.dart';
import 'message_bubble_file_preview.dart';
import 'message_bubble_progress.dart';
import 'message_bubble_reply_preview.dart';
import 'message_bubble_status.dart';
import 'message_bubble_text.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final String? senderLabel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onQueueCancel;
  final VoidCallback? onReplySwipe;
  final VoidCallback? onReplyTap;
  final String? replySenderLabel;
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
    this.replySenderLabel,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emojiPresentation = MessageEmojiPresentation.tryParse(message);
    final isEmojiOnly = emojiPresentation != null;
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
                    padding: isEmojiOnly
                        ? const EdgeInsets.fromLTRB(2, 6, 2, 4)
                        : const EdgeInsets.fromLTRB(14, 12, 14, 10),
                    decoration: BoxDecoration(
                      color: isEmojiOnly ? Colors.transparent : bubbleColor,
                      borderRadius: BorderRadius.circular(22),
                      border: isEmojiOnly
                          ? null
                          : Border.all(
                              color: effectiveBorderColor,
                              width: isHighlighted ? 2 : 1,
                            ),
                      boxShadow: isEmojiOnly
                          ? null
                          : [
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
                          MessageReplyPreview(
                            senderLabel: replySenderLabel,
                            textPreview: message.replyToTextPreview!,
                            onTap: onReplyTap,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (message.kind == MessageKind.file)
                          MessageFilePreview(message: message)
                        else
                          emojiPresentation == null
                              ? Text(
                                  message.text,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: AppTheme.ink,
                                    height: 1.35,
                                  ),
                                )
                              : MessageAnimatedEmojiText(
                                  text: message.text.trim(),
                                  emojiCount: emojiPresentation.emojiCount,
                                ),
                        const SizedBox(height: 8),
                        if (showProgress) ...[
                          MessageFileProgress(message: message),
                          const SizedBox(height: 8),
                        ],
                        MessageBubbleStatusRow(
                          timestamp: message.timestamp,
                          status: message.status,
                          incoming: message.incoming,
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
}
