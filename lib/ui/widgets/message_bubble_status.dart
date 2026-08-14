// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../models/message.dart';
import '../theme/app_theme.dart';

class MessageBubbleStatusRow extends StatelessWidget {
  final DateTime timestamp;
  final MessageStatus status;
  final MessageReceiptStatus receiptStatus;
  final bool incoming;

  const MessageBubbleStatusRow({
    super.key,
    required this.timestamp,
    required this.status,
    required this.receiptStatus,
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
          _ReceiptIcon(status: status, receiptStatus: receiptStatus),
        ],
      ],
    );
  }
}

class _ReceiptIcon extends StatelessWidget {
  final MessageStatus status;
  final MessageReceiptStatus receiptStatus;

  const _ReceiptIcon({required this.status, required this.receiptStatus});

  @override
  Widget build(BuildContext context) {
    if (status == MessageStatus.sending) {
      return Icon(Icons.schedule, size: 15, color: AppTheme.accent);
    }
    if (status == MessageStatus.failed) {
      return Icon(Icons.error_outline, size: 15, color: Colors.red.shade400);
    }
    final count = switch (receiptStatus) {
      MessageReceiptStatus.read => 3,
      MessageReceiptStatus.delivered => 2,
      MessageReceiptStatus.sent || MessageReceiptStatus.pending => 1,
    };
    const iconSize = 13.0;
    const overlapOffset = 6.0;
    return SizedBox(
      width: iconSize + (count - 1) * overlapOffset,
      height: iconSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: List<Widget>.generate(
          count,
          (index) => Positioned(
            left: index * overlapOffset,
            top: 0,
            child: Icon(Icons.check, size: iconSize, color: AppTheme.pine),
          ),
        ),
      ),
    );
  }
}

String _formatTime(DateTime timestamp) {
  final hour = timestamp.hour.toString().padLeft(2, '0');
  final minute = timestamp.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
