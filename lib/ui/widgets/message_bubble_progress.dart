import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageFileProgress extends StatelessWidget {
  final Message message;

  const MessageFileProgress({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = (message.transferProgress ?? 0).clamp(0.0, 1.0);
    final percent = (value * 100).round();
    final strings = context.strings;
    final isError =
        (message.transferStatus?.toLowerCase().contains('ошибка') ?? false) ||
        message.transferStatus == strings.downloadError ||
        message.transferStatus == strings.sendError ||
        message.transferStatus == 'Relay не настроен' ||
        message.transferStatus == strings.relayNotConfigured ||
        message.transferStatus == 'Relay недоступен' ||
        message.transferStatus == strings.relayUnavailable;

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
