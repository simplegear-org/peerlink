import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageBubbleStatusRow extends StatelessWidget {
  final DateTime timestamp;
  final MessageStatus status;
  final bool incoming;

  const MessageBubbleStatusRow({
    super.key,
    required this.timestamp,
    required this.status,
    required this.incoming,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(timestamp),
          style: theme.textTheme.labelMedium?.copyWith(
            color: AppTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (!incoming) ...[
          const SizedBox(width: 8),
          Icon(_statusIcon(status), size: 15, color: _statusColor(status)),
        ],
      ],
    );
  }
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
