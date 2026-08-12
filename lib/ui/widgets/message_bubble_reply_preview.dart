import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class MessageReplyPreview extends StatelessWidget {
  final String? senderLabel;
  final String textPreview;
  final VoidCallback? onTap;

  const MessageReplyPreview({
    super.key,
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
