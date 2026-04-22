import 'dart:async';

import 'package:flutter/material.dart';

import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'settings_screen_view.dart';

class RelayServersScreen extends StatefulWidget {
  final SettingsController controller;
  final Future<bool> Function(String endpoint) onDeleteRelay;

  const RelayServersScreen({
    super.key,
    required this.controller,
    required this.onDeleteRelay,
  });

  @override
  State<RelayServersScreen> createState() => _RelayServersScreenState();
}

class _RelayServersScreenState extends State<RelayServersScreen> {
  StreamSubscription? _availabilitySubscription;
  StreamSubscription? _connectionSubscription;

  SettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _availabilitySubscription = controller.relayAvailabilityStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _connectionSubscription = controller.connectionStatusStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _availabilitySubscription?.cancel();
    _connectionSubscription?.cancel();
    super.dispose();
  }

  Future<bool> _handleDelete(String endpoint) async {
    final deleted = await widget.onDeleteRelay(endpoint);
    if (deleted && mounted) {
      setState(() {});
    }
    return deleted;
  }

  Future<void> _showAddRelayDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Добавить relay'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'https://example'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addRelay(ctrl.text);
                if (!mounted || !dialogContext.mounted) {
                  return;
                }
                setState(() {});
                Navigator.pop(dialogContext);
              },
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = List<String>.from(controller.sortedRelayServers);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay servers'),
        actions: [
          IconButton(
            onPressed: _showAddRelayDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Добавить relay',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Relay servers', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Нужны для асинхронной доставки сообщений и медиаданных, когда получатель не в онлайне. Сначала показаны доступные сервера, ниже недоступные.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SettingsListSection(
            title: 'Все серверы',
            subtitle: 'Удаление выполняется свайпом влево с подтверждением.',
            emptyLabel: 'Список relay пуст.',
            items: items
                .map(
                  (endpoint) => SettingsListItemData(
                    key: ValueKey('relay-$endpoint'),
                    title: endpoint,
                    subtitle: 'Статус: ${controller.relayStatusLabel(endpoint)}',
                    state: controller.relayState(endpoint),
                    onDeleteRequested: () => _handleDelete(endpoint),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
