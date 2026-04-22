import 'package:flutter/material.dart';
import 'dart:async';

import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'settings_screen_view.dart';

class BootstrapServersScreen extends StatefulWidget {
  final SettingsController controller;
  final Future<bool> Function(String endpoint) onDeleteBootstrap;

  const BootstrapServersScreen({
    super.key,
    required this.controller,
    required this.onDeleteBootstrap,
  });

  @override
  State<BootstrapServersScreen> createState() => _BootstrapServersScreenState();
}

class _BootstrapServersScreenState extends State<BootstrapServersScreen> {
  StreamSubscription? _availabilitySubscription;
  StreamSubscription? _connectionSubscription;

  SettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _availabilitySubscription = controller.bootstrapAvailabilityStream.listen((_) {
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
    final deleted = await widget.onDeleteBootstrap(endpoint);
    if (deleted && mounted) {
      setState(() {});
    }
    return deleted;
  }

  Future<void> _showAddBootstrapDialog() async {
    final ctrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Добавить bootstrap'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'wss://example'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addBootstrap(ctrl.text);
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
    final items = List<String>.from(controller.bootstrapPeers)
      ..sort((a, b) {
        final aConnected = controller.bootstrapState(a) == SettingsServerState.connected ? 0 : 1;
        final bConnected = controller.bootstrapState(b) == SettingsServerState.connected ? 0 : 1;
        if (aConnected != bConnected) {
          return aConnected.compareTo(bConnected);
        }
        return a.compareTo(b);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bootstrap servers'),
        actions: [
          IconButton(
            onPressed: _showAddBootstrapDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Добавить bootstrap',
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
                Text('Bootstrap servers', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Нужны для первичного входа в сеть, обнаружения peers и signaling-связи. Сначала показаны доступные сервера, ниже недоступные.',
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
            emptyLabel: 'Список bootstrap пуст.',
            items: items
                .map((peer) => SettingsListItemData(
                      key: ValueKey('bootstrap-$peer'),
                      title: peer,
                      subtitle: 'Статус: ${controller.connectionStatusLabel(peer)}',
                      state: controller.bootstrapState(peer),
                      onDeleteRequested: () => _handleDelete(peer),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}
