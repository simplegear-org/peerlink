import 'package:flutter/material.dart';
import '../models/chat.dart';
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
                      if (unreadCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: CompactCardTileStyles.badgePadding,
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadCount > 99 ? '99+' : unreadCount.toString(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: CompactCardTileStyles.textGap),
                  Text(
                    last.isEmpty ? strings.noMessages : last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
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
