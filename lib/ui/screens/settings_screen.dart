import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/turn/turn_server_config.dart';
import '../../core/runtime/self_hosted_deploy_service.dart';
import 'qr_scan_screen.dart';
import 'avatar_capture_screen.dart';
import 'avatar_crop_screen.dart';
import 'bootstrap_servers_screen.dart';
import 'relay_servers_screen.dart';
import 'storage_details_screen.dart';
import 'settings_screen_styles.dart';
import 'settings_screen_view.dart';
import 'turn_servers_screen.dart';
import '../state/avatar_service.dart';
import '../state/app_appearance_controller.dart';
import '../state/app_locale_controller.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import '../localization/app_language.dart';
import '../localization/app_strings.dart';
import '../theme/app_appearance.dart';
import '../theme/app_theme.dart';
import '../widgets/peer_avatar.dart';
import '../widgets/server_config_import_dialog.dart';

/// Экран системных настроек: peer id и список bootstrap-серверов.
class SettingsScreen extends StatefulWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final ChatController chatController;
  final SelfHostedDeployService selfHostedDeployService;
  final AppAppearanceController appearanceController;
  final AppLocaleController localeController;

  const SettingsScreen({
    super.key,
    required this.controller,
    required this.avatarService,
    required this.chatController,
    required this.selfHostedDeployService,
    required this.appearanceController,
    required this.localeController,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StreamSubscription? _connectionStatusSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription<String>? _avatarSubscription;
  StreamSubscription? _bootstrapAvailabilitySubscription;
  StreamSubscription? _relayAvailabilitySubscription;
  StreamSubscription? _turnAvailabilitySubscription;

  SettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    });
    _connectionStatusSubscription = controller.connectionStatusStream.listen((
      _,
    ) {
      if (!mounted) return;
      setState(() {});
    });
    _errorSubscription = controller.lastErrorStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
    _avatarSubscription = widget.avatarService.updatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _bootstrapAvailabilitySubscription = controller.bootstrapAvailabilityStream
        .listen((_) {
          if (!mounted) {
            return;
          }
          setState(() {});
        });
    _relayAvailabilitySubscription = controller.relayAvailabilityStream.listen((
      _,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _turnAvailabilitySubscription = controller.turnAvailabilityStream.listen((
      _,
    ) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  /// Показывает диалог добавления bootstrap endpoint.
  void addBootstrap() {
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        final strings = context.strings;
        return AlertDialog(
          title: Text(strings.addServerTitle('bootstrap')),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'wss://example'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addBootstrap(ctrl.text);
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context);
              },
              child: Text(strings.add),
            ),
          ],
        );
      },
    );
  }

  /// Показывает диалог добавления relay endpoint.
  void addRelay() {
    final ctrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        final strings = context.strings;
        return AlertDialog(
          title: Text(strings.addServerTitle('relay')),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'http://host:8080'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addRelay(ctrl.text);
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context);
              },
              child: Text(strings.add),
            ),
          ],
        );
      },
    );
  }

  void addTurn() {
    final urlCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final priorityCtrl = TextEditingController(text: '100');

    showDialog(
      context: context,
      builder: (_) {
        final strings = context.strings;
        return AlertDialog(
          title: Text(strings.addServerTitle('TURN')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    hintText:
                        'turn:host:3478?transport=tcp;turn:host:3478?transport=udp',
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
              onPressed: () => Navigator.pop(context),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await controller.addTurnServer(
                    TurnServerConfig(
                      url: urlCtrl.text,
                      username: usernameCtrl.text.trim(),
                      password: passwordCtrl.text,
                      priority: int.tryParse(priorityCtrl.text.trim()) ?? 100,
                    ),
                  );
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('$error')));
                  return;
                }
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context);
              },
              child: Text(strings.add),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmDeleteBootstrap(String endpoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteServerTitle('bootstrap')),
          content: Text(strings.deleteServerContent('bootstrap', endpoint)),
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
    await controller.removeBootstrap(endpoint);
    if (!mounted) {
      return true;
    }
    setState(() {});
    return true;
  }

  Future<bool> _confirmDeleteRelay(String endpoint) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteServerTitle('relay')),
          content: Text(strings.deleteServerContent('relay', endpoint)),
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
    await controller.removeRelay(endpoint);
    if (!mounted) {
      return true;
    }
    setState(() {});
    return true;
  }

  Future<bool> _confirmDeleteTurn(TurnServerConfig server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteServerTitle('TURN')),
          content: Text(strings.deleteServerContent('TURN', server.url)),
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
    await controller.removeTurnServer(server.url);
    if (!mounted) {
      return true;
    }
    setState(() {});
    return true;
  }

  Future<void> _scanServerConfigQr() async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (!mounted || result is! String || result.isEmpty) {
      return;
    }

    ServerConfigImportMode? mode;
    try {
      final payload = controller.parseServerConfigQrPayload(result);
      mode = await showServerConfigImportDialog(
        context,
        controller: controller,
        payload: payload,
      );
      if (!mounted || mode == null) {
        return;
      }

      await controller.importServerConfigPayload(payload, mode: mode);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.qrReadError(error))),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mode == ServerConfigImportMode.replace
              ? context.strings.serverSettingsReplaced
              : context.strings.serverSettingsMerged,
        ),
      ),
    );
  }

  Future<void> _shareServerConfigQr() async {
    await SharePlus.instance.share(
      ShareParams(text: controller.exportServerConfigQrPayload()),
    );
  }

  Future<void> _showAppLogPreview() async {
    final log = await controller.readAppLog();
    if (!mounted) {
      return;
    }
    final strings = context.strings;
    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: Text(strings.appLog),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(
                log.isEmpty ? strings.logEmpty : log,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(strings.close),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareAppLog() async {
    final path = await controller.appLogFilePath();
    if (!mounted || path == null || path.isEmpty) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'PeerLink app log'),
    );
  }

  Future<void> _clearAppLog() async {
    await controller.clearAppLog();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.logCleared)));
  }

  Future<void> _openStorageDetails() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StorageDetailsScreen(
          controller: controller,
          avatarService: widget.avatarService,
          chatController: widget.chatController,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openBootstrapServers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BootstrapServersScreen(
          controller: controller,
          onDeleteBootstrap: _confirmDeleteBootstrap,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openRelayServers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RelayServersScreen(
          controller: controller,
          onDeleteRelay: _confirmDeleteRelay,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _openTurnServers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TurnServersScreen(
          controller: controller,
          onDeleteTurn: _confirmDeleteTurn,
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _captureAvatar() async {
    final rawBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => const AvatarCaptureScreen()),
    );
    if (!mounted || rawBytes == null || rawBytes.isEmpty) {
      return;
    }
    await _processAvatarBytes(rawBytes, mimeType: 'image/png');
  }

  Future<void> _pickAvatarFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }
    final selected = result.files.first;
    Uint8List? bytes = selected.bytes;
    if (bytes == null || bytes.isEmpty) {
      final path = selected.path;
      if (path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      }
    }
    if (!mounted || bytes == null || bytes.isEmpty) {
      return;
    }
    await _processAvatarBytes(bytes, mimeType: _mimeTypeForPath(selected.name));
  }

  Future<void> _processAvatarBytes(
    Uint8List sourceBytes, {
    required String mimeType,
  }) async {
    final croppedBytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(sourceBytes: sourceBytes),
      ),
    );
    if (!mounted || croppedBytes == null || croppedBytes.isEmpty) {
      return;
    }
    try {
      await widget.avatarService.setLocalAvatar(
        croppedBytes,
        mimeType: mimeType,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.avatarUpdated)));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.avatarSaveError(error))),
      );
    }
  }

  String _mimeTypeForPath(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  Future<void> _confirmDeleteAvatar() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteAvatarTitle),
          content: Text(strings.deleteAvatarDescription),
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
      return;
    }
    await widget.avatarService.clearLocalAvatar();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.avatarDeleted)));
  }

  Future<void> _showAvatarActions() async {
    final hasAvatar = (widget.avatarService.localAvatarPath ?? '').isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: Text(context.strings.takePhoto),
                onTap: () => Navigator.of(context).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(context.strings.chooseFromGallery),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              if (hasAvatar)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: Text(context.strings.deleteAvatar),
                  onTap: () => Navigator.of(context).pop('delete'),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) {
      return;
    }
    if (action == 'camera') {
      await _captureAvatar();
      return;
    }
    if (action == 'gallery') {
      await _pickAvatarFromGallery();
      return;
    }
    if (action == 'delete') {
      await _confirmDeleteAvatar();
    }
  }

  Future<void> _installSelfHostedServers() async {
    final hostCtrl = TextEditingController();
    final loginCtrl = TextEditingController(text: 'root');
    final passwordCtrl = TextEditingController();

    final request =
        await showDialog<({String host, String login, String password})>(
          context: context,
          builder: (dialogContext) {
            final strings = dialogContext.strings;
            return AlertDialog(
              title: Text(strings.installOwnService),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: hostCtrl,
                    decoration: InputDecoration(
                      labelText: strings.serverHostLabel,
                      hintText: '203.0.113.10',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: loginCtrl,
                    decoration: InputDecoration(labelText: strings.login),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordCtrl,
                    obscureText: true,
                    decoration: InputDecoration(labelText: strings.password),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(strings.cancel),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop((
                      host: hostCtrl.text.trim(),
                      login: loginCtrl.text.trim(),
                      password: passwordCtrl.text,
                    ));
                  },
                  child: Text(strings.install),
                ),
              ],
            );
          },
        );

    if (!mounted || request == null) {
      return;
    }
    if (request.host.isEmpty ||
        request.login.isEmpty ||
        request.password.isEmpty) {
      final strings = context.strings;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.fillServerLoginPassword)));
      return;
    }

    final strings = context.strings;
    final logs = <String>[strings.preparingInstall];
    var completed = false;
    String? completionError;
    var started = false;
    final stopwatch = Stopwatch();
    Timer? elapsedTimer;
    final logScrollController = ScrollController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void appendLog(String message) {
              setDialogState(() {
                logs.add(message);
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!logScrollController.hasClients) {
                  return;
                }
                logScrollController.animateTo(
                  logScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                );
              });
            }

            if (!started) {
              started = true;
              Future<void>.microtask(() async {
                stopwatch.start();
                elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
                  if (!mounted || completed) {
                    return;
                  }
                  setDialogState(() {});
                });
                try {
                  final result = await widget.selfHostedDeployService.deploy(
                    host: request.host,
                    username: request.login,
                    password: request.password,
                    onProgress: (message) {
                      if (!mounted) {
                        return;
                      }
                      appendLog(message);
                    },
                  );

                  await controller.addSelfHostedServersFirst(
                    bootstrapEndpoint: result.bootstrapEndpoint,
                    relayEndpoint: result.relayEndpoint,
                    turnServers: result.turnServers,
                  );
                  if (!mounted) {
                    return;
                  }
                  appendLog(strings.servicesAddedToConfig);
                  setDialogState(() {
                    completed = true;
                  });
                } catch (error) {
                  completionError = '$error';
                  appendLog(strings.deployErrorLog(error));
                  setDialogState(() {
                    completed = true;
                  });
                } finally {
                  elapsedTimer?.cancel();
                  stopwatch.stop();
                }
              });
            }

            final contentText = logs.join('\n');
            final elapsed = stopwatch.elapsed;
            final elapsedText =
                '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
                '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
            return AlertDialog(
              title: Text(strings.deployingService(elapsedText)),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  controller: logScrollController,
                  child: SelectableText(
                    contentText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              actions: [
                if (!completed)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                TextButton(
                  onPressed: completed
                      ? () => Navigator.of(dialogContext).pop()
                      : null,
                  child: Text(completed ? strings.close : strings.running),
                ),
              ],
            );
          },
        );
      },
    );
    elapsedTimer?.cancel();
    logScrollController.dispose();

    if (!mounted) {
      return;
    }

    setState(() {});
    if (completionError == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.ownServersDeployed)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.deployFailed(completionError!))),
      );
    }
  }

  @override
  void dispose() {
    _connectionStatusSubscription?.cancel();
    _errorSubscription?.cancel();
    _avatarSubscription?.cancel();
    _bootstrapAvailabilitySubscription?.cancel();
    _relayAvailabilitySubscription?.cancel();
    _turnAvailabilitySubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final qrPayload = controller.exportServerConfigQrPayload();
    final userQrPayload = controller.exportUserQrPayload();
    return Scaffold(
      appBar: AppBar(title: Text(strings.settings)),
      body: ListView(
        padding: SettingsScreenStyles.screenPadding,
        children: [
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsSectionLabel(title: 'Peer ID'),
                const SizedBox(height: 8),
                SelectableText(controller.peerId),
                const SizedBox(height: 14),
                Row(
                  children: [
                    InkWell(
                      onTap: _showAvatarActions,
                      borderRadius: BorderRadius.circular(999),
                      child: PeerAvatar(
                        peerId: controller.peerId,
                        displayName: controller.peerId,
                        avatarService: widget.avatarService,
                        size: 56,
                        showInitialWhenNoAvatar: false,
                        backgroundColor: AppTheme.pineSoft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        strings.avatarHint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(data: userQrPayload, size: 190),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.rocket_launch_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.installOwnServerStack,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.installOwnServerStackDescription,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _installSelfHostedServers,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: Text(strings.installOwnService),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              onTap: _openBootstrapServers,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Bootstrap servers',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.bootstrapSummary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildBootstrapSummaryChip(
                        color: Colors.green.shade600,
                        value: controller.bootstrapAvailableCount,
                      ),
                      const SizedBox(width: 12),
                      _buildBootstrapSummaryChip(
                        color: Colors.red.shade600,
                        value: controller.bootstrapUnavailableCount,
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              onTap: _openRelayServers,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Relay servers',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.relaySummary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildBootstrapSummaryChip(
                        color: Colors.green.shade600,
                        value: controller.relayAvailableCount,
                      ),
                      const SizedBox(width: 12),
                      _buildBootstrapSummaryChip(
                        color: Colors.red.shade600,
                        value: controller.relayUnavailableCount,
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              onTap: _openTurnServers,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'TURN servers',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    strings.turnSummary,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildBootstrapSummaryChip(
                        color: Colors.green.shade600,
                        value: controller.turnAvailableCount,
                      ),
                      const SizedBox(width: 12),
                      _buildBootstrapSummaryChip(
                        color: Colors.red.shade600,
                        value: controller.turnUnavailableCount,
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.serverQrTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  strings.serverQrDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _scanServerConfigQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(strings.scanServerQr),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _shareServerConfigQr,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(strings.shareConfig),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(data: qrPayload, size: 220),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  strings.serverConfigFormat,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          FutureBuilder(
            future: controller.loadStorageBreakdown(),
            builder: (context, snapshot) {
              final breakdown = snapshot.data;
              final totalBytes = breakdown?.totalBytes ?? 0;
              return Container(
                padding: SettingsScreenStyles.sectionPadding,
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(
                    SettingsScreenStyles.sectionRadius,
                  ),
                  border: Border.all(color: AppTheme.stroke),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(
                    SettingsScreenStyles.sectionRadius,
                  ),
                  onTap: _openStorageDetails,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              strings.storage,
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.storageUsed(_formatBytes(totalBytes)),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.storageDescription,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          AnimatedBuilder(
            animation: widget.appearanceController,
            builder: (context, child) {
              final current = widget.appearanceController.current;
              return Container(
                padding: SettingsScreenStyles.sectionPadding,
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(
                    SettingsScreenStyles.sectionRadius,
                  ),
                  border: Border.all(color: AppTheme.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.appAppearance,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      strings.appAppearanceDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final appearance in AppAppearance.values)
                          _buildAppearanceOption(
                            appearance: appearance,
                            selected: appearance == current,
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          AnimatedBuilder(
            animation: widget.localeController,
            builder: (context, child) {
              final strings = context.strings;
              final current = widget.localeController.current;
              return Container(
                padding: SettingsScreenStyles.sectionPadding,
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(
                    SettingsScreenStyles.sectionRadius,
                  ),
                  border: Border.all(color: AppTheme.stroke),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.language, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      strings.languageDescription,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppTheme.muted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final language in AppLanguage.values)
                          _buildLanguageButton(
                            language: language,
                            selected: language == current,
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Container(
            padding: SettingsScreenStyles.sectionPadding,
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(
                SettingsScreenStyles.sectionRadius,
              ),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.appLog, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  strings.appLogDescription,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _showAppLogPreview,
                      icon: const Icon(Icons.article_outlined),
                      label: Text(strings.showLog),
                    ),
                    OutlinedButton.icon(
                      onPressed: _shareAppLog,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: Text(strings.shareLog),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearAppLog,
                      icon: const Icon(Icons.delete_outline),
                      label: Text(strings.clearLog),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: SettingsScreenStyles.cardSeparatorHeight),
          Center(
            child: Text(
              strings.version(controller.appVersionLabel),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.muted,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _buildAppearanceOption({
    required AppAppearance appearance,
    required bool selected,
  }) {
    final palette = appearance.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () async {
        await widget.appearanceController.select(appearance);
        if (!mounted) {
          return;
        }
        setState(() {});
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.surfaceRaised : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.stroke,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.accent.withValues(alpha: 0.22),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [palette.accent, palette.accentSoft],
                ),
                border: Border.all(
                  color: palette.stroke.withValues(alpha: 0.8),
                ),
                boxShadow: [
                  BoxShadow(
                    color: palette.accent.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: palette.paper.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.palette_outlined,
                    size: 16,
                    color: palette.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageButton({
    required AppLanguage language,
    required bool selected,
  }) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: () async {
        if (selected) {
          return;
        }
        await widget.localeController.select(language);
        if (!mounted) {
          return;
        }
        setState(() {});
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        foregroundColor: selected ? AppTheme.accent : AppTheme.ink,
        side: BorderSide(color: selected ? AppTheme.accent : AppTheme.stroke),
        backgroundColor: selected ? AppTheme.accentSoft : AppTheme.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      child: Text(
        language.shortLabel,
        style: theme.textTheme.labelLarge?.copyWith(
          color: selected ? AppTheme.accent : AppTheme.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildBootstrapSummaryChip({
    required Color color,
    required int value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 10,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$value',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
