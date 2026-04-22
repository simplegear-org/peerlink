import 'package:flutter/material.dart';
import '../models/chat.dart';
import '../theme/app_theme.dart';
import 'swipe_delete_tile.dart';

class ChatTile extends StatelessWidget {
  final Chat chat;
  final VoidCallback onTap;
  final Future<bool> Function() onDeleteRequested;
  final String? lastSeenText;
  final Widget? avatar;

  const ChatTile({
    super.key,
    required this.chat,
    required this.onTap,
    required this.onDeleteRequested,
    this.lastSeenText,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final last = chat.lastMessage?.text ?? "";
    final theme = Theme.of(context);
    final unreadCount = chat.unreadCount;

    return SwipeDeleteTile(
      onDeleteRequested: onDeleteRequested,
      onTap: onTap,
      foreground: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                height: 52,
                child: avatar ??
                    Container(
                      decoration: const BoxDecoration(
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
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
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
                    const SizedBox(height: 4),
                    Text(
                      last.isEmpty ? 'Нет сообщений' : last,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                    if (lastSeenText != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        lastSeenText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                Icons.arrow_outward_rounded,
                color: AppTheme.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
