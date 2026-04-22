import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'chats_screen_styles.dart';

class ChatsScreenHeader extends StatelessWidget {
  const ChatsScreenHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: ChatsScreenStyles.headerPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Диалоги',
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Прямые переписки и сообщения через relay в одном списке.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class ChatsEmptyState extends StatelessWidget {
  const ChatsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: ChatsScreenStyles.emptyOuterPadding,
        child: Container(
          padding: ChatsScreenStyles.emptyInnerPadding,
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(ChatsScreenStyles.emptyCardRadius),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: ChatsScreenStyles.emptyIconBoxSize,
                height: ChatsScreenStyles.emptyIconBoxSize,
                decoration: BoxDecoration(
                  color: AppTheme.accentSoft,
                  borderRadius: BorderRadius.circular(ChatsScreenStyles.emptyIconBoxRadius),
                ),
                child: const Icon(Icons.forum_rounded, size: ChatsScreenStyles.iconSize),
              ),
              const SizedBox(height: ChatsScreenStyles.titleSpacing),
              Text(
                'Пока нет диалогов',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: ChatsScreenStyles.subtitleSpacing),
              Text(
                'Открой контакт и отправь первое сообщение.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
