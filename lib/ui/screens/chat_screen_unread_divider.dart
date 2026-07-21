import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'chat_screen_unread_divider_styles.dart';

class ChatScreenUnreadDivider extends StatelessWidget {
  const ChatScreenUnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: ChatScreenUnreadDividerStyles.outerPadding,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: ChatScreenUnreadDividerStyles.lineHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent.withValues(alpha: 0),
                    AppTheme.accent.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ),
          Container(
            margin: ChatScreenUnreadDividerStyles.badgeMargin,
            padding: ChatScreenUnreadDividerStyles.badgePadding,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft,
              borderRadius: BorderRadius.circular(
                ChatScreenUnreadDividerStyles.badgeRadius,
              ),
              border: Border.all(
                color: AppTheme.accent.withValues(alpha: 0.14),
              ),
            ),
            child: Text(
              context.strings.unread,
              style: theme.textTheme.labelMedium?.copyWith(
                color: AppTheme.accent,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: ChatScreenUnreadDividerStyles.lineHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.55),
                    AppTheme.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
