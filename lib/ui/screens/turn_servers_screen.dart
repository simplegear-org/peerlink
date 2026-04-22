import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/turn/turn_server_config.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'settings_screen_view.dart';

class TurnServersScreen extends StatefulWidget {
  final SettingsController controller;
  final Future<bool> Function(TurnServerConfig server) onDeleteTurn;

  const TurnServersScreen({
    super.key,
    required this.controller,
    required this.onDeleteTurn,
  });

  @override
  State<TurnServersScreen> createState() => _TurnServersScreenState();
}

class _TurnServersScreenState extends State<TurnServersScreen> {
  StreamSubscription? _availabilitySubscription;
  StreamSubscription? _connectionSubscription;

  SettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _availabilitySubscription = controller.turnAvailabilityStream.listen((_) {
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

  Future<bool> _handleDelete(TurnServerConfig server) async {
    final deleted = await widget.onDeleteTurn(server);
    if (deleted && mounted) {
      setState(() {});
    }
    return deleted;
  }

  Future<void> _showAddTurnDialog() async {
    final urlCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final priorityCtrl = TextEditingController(text: '100');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Добавить TURN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    hintText: 'turn:host:3478?transport=tcp',
                    labelText: 'URL',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priorityCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Priority'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addTurnServer(
                  TurnServerConfig(
                    url: urlCtrl.text,
                    username: usernameCtrl.text.trim(),
                    password: passwordCtrl.text,
                    priority: int.tryParse(priorityCtrl.text.trim()) ?? 100,
                  ),
                );
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
    final items = List<TurnServerConfig>.from(controller.sortedTurnServers);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TURN servers'),
        actions: [
          IconButton(
            onPressed: _showAddTurnDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Добавить TURN',
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
                Text('TURN servers', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Нужны для fallback-маршрутизации звонков и WebRTC, когда прямое соединение не устанавливается. Сначала показаны доступные сервера, ниже недоступные.',
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
            emptyLabel: 'Список TURN пуст.',
            items: items
                .map((server) {
                  final maskedPassword = server.password.isEmpty
                      ? 'без пароля'
                      : 'пароль: ${'*' * server.password.length.clamp(3, 8)}';
                  return SettingsListItemData(
                    key: ValueKey('turn-${server.url}'),
                    title: server.url,
                    subtitle:
                        'Статус: ${controller.turnStatusLabel(server.url)}\nuser: ${server.username.isEmpty ? '-' : server.username} | $maskedPassword | priority: ${server.priority}',
                    state: controller.turnState(server.url),
                    onDeleteRequested: () => _handleDelete(server),
                  );
                })
                .toList(),
          ),
        ],
      ),
    );
  }
}
