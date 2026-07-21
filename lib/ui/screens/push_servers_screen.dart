import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/right_swipe_pop_region.dart';
import 'settings_screen_styles.dart';
import 'settings_screen_view.dart';

class PushServersScreen extends StatefulWidget {
  final SettingsController controller;
  final Future<bool> Function(String endpoint) onDeletePush;

  const PushServersScreen({
    super.key,
    required this.controller,
    required this.onDeletePush,
  });

  @override
  State<PushServersScreen> createState() => _PushServersScreenState();
}

class _PushServersScreenState extends State<PushServersScreen> {
  StreamSubscription? _availabilitySubscription;

  SettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _availabilitySubscription = controller.pushAvailabilityStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _availabilitySubscription?.cancel();
    super.dispose();
  }

  Future<bool> _handleDelete(String endpoint) async {
    final deleted = await widget.onDeletePush(endpoint);
    if (deleted && mounted) {
      setState(() {});
    }
    return deleted;
  }

  Future<void> _showAddPushDialog() async {
    final endpoint = await showDialog<String>(
      context: context,
      builder: (_) => const _AddPushServerDialog(),
    );
    if (endpoint == null || !mounted) {
      return;
    }
    await controller.addPushServer(endpoint);
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _showEditPushDialog(String endpoint) async {
    try {
      final result = await showDialog<_EditPushServerDialogResult>(
        context: context,
        builder: (_) => _EditPushServerDialog(
          endpoint: endpoint,
          paused: controller.isPushServerPaused(endpoint),
        ),
      );
      if (result == null || !mounted) {
        return;
      }
      switch (result.action) {
        case _EditPushServerDialogAction.save:
          await controller.updatePushServer(
            endpoint,
            host: result.host!,
            port: result.port,
          );
          break;
        case _EditPushServerDialogAction.pause:
          await controller.pausePushServer(endpoint);
          break;
        case _EditPushServerDialogAction.resume:
          await controller.resumePushServer(endpoint);
          break;
      }
      if (!mounted) {
        return;
      }
      setState(() {});
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final items = List<String>.from(controller.sortedPushServers);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Push servers'),
        actions: [
          IconButton(
            onPressed: _showAddPushDialog,
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: strings.addServerTitle('Push'),
          ),
        ],
      ),
      body: RightSwipePopRegion(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Text(
              strings.pushServersDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  strings.serverListEmpty('push'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              )
            else
              for (final endpoint in items)
                Padding(
                  key: ValueKey('push-$endpoint'),
                  padding: SettingsScreenStyles.listItemMargin,
                  child: SettingsListItem(
                    title: endpoint,
                    subtitle: strings.statusPrefix(
                      controller.pushStatusLabel(endpoint, strings: strings),
                    ),
                    state: controller.pushState(endpoint),
                    trailing: controller.isPushServerPaused(endpoint)
                        ? Icon(
                            Icons.pause_circle_filled_rounded,
                            color: AppTheme.muted,
                            size: 20,
                          )
                        : null,
                    onDeleteRequested: () => _handleDelete(endpoint),
                    onLongPress: () => _showEditPushDialog(endpoint),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _AddPushServerDialog extends StatefulWidget {
  const _AddPushServerDialog();

  @override
  State<_AddPushServerDialog> createState() => _AddPushServerDialogState();
}

class _AddPushServerDialogState extends State<_AddPushServerDialog> {
  late final TextEditingController _endpointCtrl;

  @override
  void initState() {
    super.initState();
    _endpointCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.addServerTitle('push')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _endpointCtrl,
            decoration: const InputDecoration(
              hintText: 'example.com or 203.0.113.10',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _endpointCtrl.text),
          child: Text(strings.add),
        ),
      ],
    );
  }
}

class _EditPushServerDialog extends StatefulWidget {
  final String endpoint;
  final bool paused;

  const _EditPushServerDialog({
    required this.endpoint,
    required this.paused,
  });

  @override
  State<_EditPushServerDialog> createState() => _EditPushServerDialogState();
}

class _EditPushServerDialogState extends State<_EditPushServerDialog> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    final currentUri = Uri.tryParse(widget.endpoint);
    _hostCtrl = TextEditingController(text: currentUri?.host ?? widget.endpoint);
    _portCtrl = TextEditingController(
      text: (currentUri?.hasPort ?? false) ? '${currentUri!.port}' : '',
    );
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    try {
      final portText = _portCtrl.text.trim();
      if (portText.isNotEmpty && int.tryParse(portText) == null) {
        throw const FormatException('Некорректный порт push сервера');
      }
      Navigator.pop(
        context,
        _EditPushServerDialogResult(
          action: _EditPushServerDialogAction.save,
          host: _hostCtrl.text,
          port: portText.isEmpty ? null : int.parse(portText),
        ),
      );
    } on FormatException catch (error) {
      setState(() {
        _errorText = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: const Text('Редактировать push сервер'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _hostCtrl,
            decoration: const InputDecoration(
              labelText: 'Домен или IP',
              hintText: 'example.com',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portCtrl,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Порт',
              hintText: '445',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: () => Navigator.pop(
            context,
            _EditPushServerDialogResult(
              action: widget.paused
                  ? _EditPushServerDialogAction.resume
                  : _EditPushServerDialogAction.pause,
            ),
          ),
          icon: Icon(
            widget.paused
                ? Icons.play_arrow_rounded
                : Icons.pause_rounded,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(strings.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(strings.save)),
      ],
    );
  }
}

enum _EditPushServerDialogAction { save, pause, resume }

class _EditPushServerDialogResult {
  final _EditPushServerDialogAction action;
  final String? host;
  final int? port;

  const _EditPushServerDialogResult({
    required this.action,
    this.host,
    this.port,
  });
}
