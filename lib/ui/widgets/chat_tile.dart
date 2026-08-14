// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'compact_card_tile_styles.dart';
import 'swipe_delete_tile.dart';

class ChatTile extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;
  final Future<bool> Function() onDeleteRequested;
  final Widget? avatar;

  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    required this.onDeleteRequested,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final last = chat.lastMessage?.text ?? "";
    final lastMessage = chat.lastMessage;
    final theme = Theme.of(context);
    final strings = context.strings;
    final unreadCount = chat.unreadCount;

    return SwipeDeleteTile(
      borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
      onDeleteRequested: onDeleteRequested,
      onTap: onTap,
      foreground: Container(
        padding: CompactCardTileStyles.tilePadding,
        decoration: BoxDecoration(
          color: AppTheme.paper,
          borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
          border: Border.all(color: AppTheme.stroke),
        ),
        child: Row(
          children: [
            SizedBox(
              width: CompactCardTileStyles.avatarSize,
              height: CompactCardTileStyles.avatarSize,
              child:
                  avatar ??
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      chat.name.isEmpty ? '?' : chat.name[0].toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
            ),
            const SizedBox(width: CompactCardTileStyles.horizontalGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chat.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (lastMessage != null) ...[
                        const SizedBox(width: 8),
                        _ChatLastMessageMeta(message: lastMessage),
                      ],
                    ],
                  ),
                  const SizedBox(height: CompactCardTileStyles.textGap),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          last.isEmpty ? strings.noMessages : last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadBadge(unreadCount: unreadCount),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: CompactCardTileStyles.horizontalGap),
            Icon(
              Icons.arrow_outward_rounded,
              color: AppTheme.muted,
              size: CompactCardTileStyles.trailingIconSize,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLastMessageMeta extends StatelessWidget {
  final Message message;

  const _ChatLastMessageMeta({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!message.incoming) ...[
          _ReceiptChecks(
            status: message.status,
            receiptStatus: message.receiptStatus,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          _formatChatTimestamp(message.timestamp),
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ReceiptChecks extends StatelessWidget {
  final MessageStatus status;
  final MessageReceiptStatus receiptStatus;

  const _ReceiptChecks({required this.status, required this.receiptStatus});

  @override
  Widget build(BuildContext context) {
    if (status == MessageStatus.sending) {
      return Icon(Icons.schedule, size: 13, color: AppTheme.accent);
    }
    if (status == MessageStatus.failed) {
      return Icon(Icons.error_outline, size: 13, color: Colors.red.shade400);
    }
    final count = switch (receiptStatus) {
      MessageReceiptStatus.read => 3,
      MessageReceiptStatus.delivered => 2,
      MessageReceiptStatus.sent || MessageReceiptStatus.pending => 1,
    };
    const iconSize = 12.0;
    const overlapOffset = 5.5;
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

class _UnreadBadge extends StatelessWidget {
  final int unreadCount;

  const _UnreadBadge({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: CompactCardTileStyles.badgePadding,
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        unreadCount > 99 ? '99+' : unreadCount.toString(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _formatChatTimestamp(DateTime timestamp) {
  final local = timestamp.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return '${_two(local.hour)}:${_two(local.minute)}';
  }
  if (local.year == now.year) {
    return '${_two(local.day)}:${_two(local.month)}';
  }
  return '${_two(local.day)}:${_two(local.month)}:${_two(local.year % 100)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
