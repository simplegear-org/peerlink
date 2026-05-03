import 'package:flutter/material.dart';
import 'dart:async';

import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/right_swipe_pop_region.dart';
import 'settings_screen_styles.dart';
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
    _availabilitySubscription = controller.bootstrapAvailabilityStream.listen((
      _,
    ) {
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
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.addServerTitle('bootstrap')),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'wss://example'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(strings.cancel),
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
    final items = List<String>.from(controller.bootstrapPeers)
      ..sort((a, b) {
        final aConnected =
            controller.bootstrapState(a) == SettingsServerState.connected
            ? 0
            : 1;
        final bConnected =
            controller.bootstrapState(b) == SettingsServerState.connected
            ? 0
            : 1;
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
            tooltip: strings.addServerTitle('bootstrap'),
          ),
        ],
      ),
      body: RightSwipePopRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              strings.bootstrapServersDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  strings.serverListEmpty('bootstrap'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              )
            else
              for (final peer in items)
                Padding(
                  key: ValueKey('bootstrap-$peer'),
                  padding: SettingsScreenStyles.listItemMargin,
                  child: SettingsListItem(
                    title: peer,
                    subtitle: strings.statusPrefix(
                      controller.connectionStatusLabel(peer, strings: strings),
                    ),
                    state: controller.bootstrapState(peer),
                    onDeleteRequested: () => _handleDelete(peer),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
