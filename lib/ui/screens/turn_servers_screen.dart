import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/turn/turn_server_config.dart';
import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/right_swipe_pop_region.dart';
import 'settings_screen_styles.dart';
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
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.addServerTitle('TURN')),
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
              child: Text(strings.cancel),
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
              child: Text(strings.add),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final items = List<TurnServerConfig>.from(controller.sortedTurnServers);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TURN servers'),
        actions: [
          IconButton(
            onPressed: _showAddTurnDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: strings.addServerTitle('TURN'),
          ),
        ],
      ),
      body: RightSwipePopRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              strings.turnServersDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  strings.serverListEmpty('TURN'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              )
            else
              for (final server in items)
                Padding(
                  key: ValueKey('turn-${server.url}'),
                  padding: SettingsScreenStyles.listItemMargin,
                  child: SettingsListItem(
                    title: server.url,
                    subtitle: _turnSubtitle(server, strings),
                    state: controller.turnState(server.url),
                    onDeleteRequested: () => _handleDelete(server),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  String _turnSubtitle(TurnServerConfig server, AppStrings strings) {
    final status = strings.statusPrefix(
      controller.turnStatusLabel(server.url, strings: strings),
    );
    final username = server.username.isEmpty ? '-' : server.username;
    final maskedPassword = server.password.isEmpty
        ? strings.noPassword
        : strings.maskedPassword('*' * server.password.length.clamp(3, 8));
    return '$status | user: $username | $maskedPassword | priority: ${server.priority}';
  }
}
