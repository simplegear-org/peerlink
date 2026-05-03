import 'package:flutter/material.dart';

import '../../core/runtime/app_storage_stats.dart';
import '../localization/app_strings.dart';
import '../state/avatar_service.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/right_swipe_pop_region.dart';
import '../widgets/swipe_delete_tile.dart';
import 'settings_screen_styles.dart';

class StorageDetailsScreen extends StatefulWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final ChatController chatController;

  const StorageDetailsScreen({
    super.key,
    required this.controller,
    required this.avatarService,
    required this.chatController,
  });

  @override
  State<StorageDetailsScreen> createState() => _StorageDetailsScreenState();
}

class _StorageDetailsScreenState extends State<StorageDetailsScreen> {
  AppStorageBreakdown? _breakdown;
  bool _loading = true;
  AppStorageCategory? _busyCategory;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
    });
    final breakdown = await widget.controller.loadStorageBreakdown();
    if (!mounted) {
      return;
    }
    setState(() {
      _breakdown = breakdown;
      _loading = false;
    });
  }

  Future<bool> _confirmDeleteCategory(AppStorageCategory category) async {
    final strings = context.strings;
    final title = _titleFor(category, strings);
    final warning = _warningFor(category, strings);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.deleteStorageCategoryTitle(title)),
          content: Text(warning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return false;
    }

    setState(() {
      _busyCategory = category;
    });
    try {
      switch (category) {
        case AppStorageCategory.mediaFiles:
          await widget.controller.storage.clearManagedMediaStorage();
          await widget.avatarService.clearAllAvatarMedia();
          await widget.chatController.clearManagedMediaReferencesInMemory();
          break;
        case AppStorageCategory.messagesDatabase:
          await widget.controller.clearMessagesDatabase();
          widget.chatController.clearAllChatsFromMemory();
          break;
        case AppStorageCategory.logs:
          await widget.controller.clearAllLogs();
          break;
        case AppStorageCategory.settingsAndServiceData:
          await widget.controller.clearSettingsAndServiceData();
          widget.chatController.clearAllChatsFromMemory();
          await widget.avatarService.clearAllAvatarMedia();
          break;
      }
      await _refresh();
      if (!mounted) {
        return true;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.deletedStorageCategory(title))),
      );
      return true;
    } finally {
      if (mounted) {
        setState(() {
          _busyCategory = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final breakdown = _breakdown;
    final items = AppStorageCategory.values;

    return Scaffold(
      appBar: AppBar(title: Text(strings.storage)),
      body: RightSwipePopRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              strings.storageDetailsDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final category in items)
                Padding(
                  key: ValueKey('storage-${category.name}'),
                  padding: SettingsScreenStyles.listItemMargin,
                  child: _StorageCategoryTile(
                    title: _titleFor(category, strings),
                    subtitle: _subtitleFor(category, strings),
                    value: _formatBytes(breakdown?.bytesFor(category) ?? 0),
                    deleting: _busyCategory == category,
                    onDeleteRequested: () => _confirmDeleteCategory(category),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _titleFor(AppStorageCategory category, AppStrings strings) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return strings.storageMediaFiles;
      case AppStorageCategory.messagesDatabase:
        return strings.storageMessagesDatabase;
      case AppStorageCategory.logs:
        return strings.storageLogs;
      case AppStorageCategory.settingsAndServiceData:
        return strings.storageSettingsAndServiceData;
    }
  }

  String _subtitleFor(AppStorageCategory category, AppStrings strings) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return strings.storageMediaSubtitle;
      case AppStorageCategory.messagesDatabase:
        return strings.storageMessagesSubtitle;
      case AppStorageCategory.logs:
        return strings.storageLogsSubtitle;
      case AppStorageCategory.settingsAndServiceData:
        return strings.storageSettingsSubtitle;
    }
  }

  String _warningFor(AppStorageCategory category, AppStrings strings) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return strings.storageMediaWarning;
      case AppStorageCategory.messagesDatabase:
        return strings.storageMessagesWarning;
      case AppStorageCategory.logs:
        return strings.storageLogsWarning;
      case AppStorageCategory.settingsAndServiceData:
        return strings.storageSettingsWarning;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final fractionDigits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }
}

class _StorageCategoryTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final bool deleting;
  final Future<bool> Function() onDeleteRequested;

  const _StorageCategoryTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.deleting,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: SettingsScreenStyles.itemHeight,
      child: SwipeDeleteTile(
        borderRadius: BorderRadius.circular(SettingsScreenStyles.itemRadius),
        onDeleteRequested: onDeleteRequested,
        foreground: Container(
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(
              SettingsScreenStyles.itemRadius,
            ),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Padding(
            padding: SettingsScreenStyles.listItemPadding,
            child: Row(
              children: [
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
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  value,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
