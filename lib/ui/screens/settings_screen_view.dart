import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/swipe_delete_tile.dart';
import 'settings_screen_styles.dart';
import '../state/settings_controller.dart';

class SettingsListItemData {
  final Key key;
  final String title;
  final String? subtitle;
  final SettingsServerState state;
  final Future<bool> Function() onDeleteRequested;

  const SettingsListItemData({
    required this.key,
    required this.title,
    this.subtitle,
    required this.state,
    required this.onDeleteRequested,
  });
}

class SettingsSectionLabel extends StatelessWidget {
  final String title;

  const SettingsSectionLabel({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.muted,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
    );
  }
}

class SettingsListSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emptyLabel;
  final VoidCallback? onAdd;
  final List<SettingsListItemData> items;

  const SettingsListSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.emptyLabel,
    this.onAdd,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: SettingsScreenStyles.sectionPadding,
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(SettingsScreenStyles.sectionRadius),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onAdd != null)
                IconButton(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_circle_outline_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: SettingsScreenStyles.emptyLabelPadding,
              child: Text(
                emptyLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            )
          else
            Column(
              children: [
                for (final item in items)
                  Padding(
                    key: item.key,
                    padding: SettingsScreenStyles.listItemMargin,
                    child: SettingsListItem(
                      title: item.title,
                      subtitle: item.subtitle,
                      state: item.state,
                      onDeleteRequested: item.onDeleteRequested,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class SettingsListItem extends StatelessWidget {
  final String title;
  final String? subtitle;
  final SettingsServerState state;
  final Future<bool> Function() onDeleteRequested;

  const SettingsListItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.state,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicatorColor = _indicatorColor();
    return SizedBox(
      height: SettingsScreenStyles.itemHeight,
      child: SwipeDeleteTile(
        borderRadius: BorderRadius.circular(SettingsScreenStyles.itemRadius),
        onDeleteRequested: onDeleteRequested,
        foreground: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: indicatorColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: indicatorColor.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _indicatorColor() {
    switch (state) {
      case SettingsServerState.connected:
        return Colors.green.shade600;
      case SettingsServerState.connecting:
        return Colors.amber.shade700;
      case SettingsServerState.unavailable:
        return Colors.red.shade600;
    }
  }
}
