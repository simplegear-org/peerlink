import 'dart:async';
import 'dart:io';

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
    final hostCtrl = TextEditingController();

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
                  controller: hostCtrl,
                  decoration: const InputDecoration(
                    hintText: 'example.com or 203.0.113.10',
                    labelText: 'Host',
                  ),
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
                final normalizedHost = _normalizeHostOnly(hostCtrl.text);
                if (normalizedHost.isEmpty) {
                  return;
                }
                const username = 'peerlink';
                const password = 'peerlink';
                const basePriority = 100;
                final isIpHost = _isIpAddressHost(normalizedHost);
                final urls = <String>[
                  'turn:$normalizedHost:3478?transport=udp',
                  'turn:$normalizedHost:3478?transport=tcp',
                  if (!isIpHost) 'turns:$normalizedHost:5349?transport=tcp',
                ];
                for (var index = 0; index < urls.length; index++) {
                  final priority = (basePriority - (index * 10)).clamp(
                    0,
                    100000,
                  );
                  await controller.addTurnServer(
                    TurnServerConfig(
                      url: urls[index],
                      username: username,
                      password: password,
                      priority: priority,
                    ),
                  );
                }
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

  String _normalizeHostOnly(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return '';
    }
    final withScheme = raw.contains('://') ? raw : 'turn://$raw';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.trim().isEmpty) {
      return '';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return '';
    }
    if (uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        uri.userInfo.isNotEmpty) {
      return '';
    }
    final host = uri.host.trim();
    if (!_isSafeHost(host)) {
      return '';
    }
    return host;
  }

  bool _isSafeHost(String host) {
    if (host.isEmpty || host.contains('%')) {
      return false;
    }
    try {
      if (InternetAddress.tryParse(host) != null) {
        return true;
      }
    } on FormatException {
      return false;
    }
    final domainPattern = RegExp(r'^[A-Za-z0-9.-]+$');
    return domainPattern.hasMatch(host);
  }

  bool _isIpAddressHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    try {
      return InternetAddress.tryParse(host) != null;
    } on FormatException {
      return false;
    }
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
