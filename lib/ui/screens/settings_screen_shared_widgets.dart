import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'settings_screen_styles.dart';

class SettingsSectionCard extends StatelessWidget {
  final Widget child;

  const SettingsSectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: SettingsScreenStyles.cardSeparatorHeight,
      ),
      padding: SettingsScreenStyles.sectionPadding,
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(SettingsScreenStyles.sectionRadius),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: child,
    );
  }
}

class SettingsSummaryChip extends StatelessWidget {
  final Color color;
  final int value;

  const SettingsSummaryChip({
    super.key,
    required this.color,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
