import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/right_swipe_pop_region.dart';
import 'settings_screen_styles.dart';
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
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.addServerTitle('relay')),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'https://example'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
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
    final items = List<String>.from(controller.sortedRelayServers);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relay servers'),
        actions: [
          IconButton(
            onPressed: _showAddRelayDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: strings.addServerTitle('relay'),
          ),
        ],
      ),
      body: RightSwipePopRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              strings.relayServersDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  strings.serverListEmpty('relay'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              )
            else
              for (final endpoint in items)
                Padding(
                  key: ValueKey('relay-$endpoint'),
                  padding: SettingsScreenStyles.listItemMargin,
                  child: SettingsListItem(
                    title: endpoint,
                    subtitle: strings.statusPrefix(
                      controller.relayStatusLabel(endpoint, strings: strings),
                    ),
                    state: controller.relayState(endpoint),
                    onDeleteRequested: () => _handleDelete(endpoint),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
