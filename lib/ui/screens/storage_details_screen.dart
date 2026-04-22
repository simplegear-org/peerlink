import 'package:flutter/material.dart';

import '../../core/runtime/app_storage_stats.dart';
import '../state/avatar_service.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
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
    final title = _titleFor(category);
    final warning = _warningFor(category);
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Удалить $title?'),
          content: Text(warning),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
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
        SnackBar(content: Text('Удалено: $title')),
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
    final breakdown = _breakdown;
    final items = AppStorageCategory.values;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Хранилище'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(SettingsScreenStyles.sectionRadius),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Категории данных', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Размер считается по реальным файлам приложения на устройстве. Свайп влево по строке удаляет выбранную категорию данных.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Column(
                    children: [
                      for (final category in items)
                        Padding(
                          key: ValueKey('storage-${category.name}'),
                          padding: SettingsScreenStyles.listItemMargin,
                          child: _StorageCategoryTile(
                            title: _titleFor(category),
                            subtitle: _subtitleFor(category),
                            warning: _inlineWarningFor(category),
                            value: _formatBytes(breakdown?.bytesFor(category) ?? 0),
                            deleting: _busyCategory == category,
                            onDeleteRequested: () => _confirmDeleteCategory(category),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _titleFor(AppStorageCategory category) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return 'Media files';
      case AppStorageCategory.messagesDatabase:
        return 'Messages database';
      case AppStorageCategory.logs:
        return 'Logs';
      case AppStorageCategory.settingsAndServiceData:
        return 'Settings and service data';
    }
  }

  String _subtitleFor(AppStorageCategory category) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return 'Фото, видео, локальные вложения и аватары.';
      case AppStorageCategory.messagesDatabase:
        return 'SQLite с чатами, сообщениями и summaries.';
      case AppStorageCategory.logs:
        return 'Текущий лог приложения и архивы ротации.';
      case AppStorageCategory.settingsAndServiceData:
        return 'Контакты, серверные настройки, ключи и служебные данные.';
    }
  }

  String _warningFor(AppStorageCategory category) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return 'Будут удалены локальные медиафайлы и аватары, сохраненные приложением на устройстве.';
      case AppStorageCategory.messagesDatabase:
        return 'Будут удалены локальные чаты и сообщения из базы приложения. Это действие необратимо.';
      case AppStorageCategory.logs:
        return 'Будут удалены текущий лог и архивы логов.';
      case AppStorageCategory.settingsAndServiceData:
        return 'Будут удалены контакты, серверные настройки, ключи и другие служебные данные приложения. Может потребоваться заново настроить приложение.';
    }
  }

  String _inlineWarningFor(AppStorageCategory category) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return 'Удалит локальные медиа и аватары, сохраненные приложением.';
      case AppStorageCategory.messagesDatabase:
        return 'Удалит локальные чаты и сообщения из базы.';
      case AppStorageCategory.logs:
        return 'Удалит текущий лог и архивы ротации.';
      case AppStorageCategory.settingsAndServiceData:
        return 'Удалит контакты, настройки, ключи и служебные данные.';
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
  final String warning;
  final String value;
  final bool deleting;
  final Future<bool> Function() onDeleteRequested;

  const _StorageCategoryTile({
    required this.title,
    required this.subtitle,
    required this.warning,
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
        foreground: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                      const SizedBox(height: 2),
                      Text(
                        warning,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w600,
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
