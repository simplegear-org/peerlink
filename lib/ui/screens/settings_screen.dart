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
import 'settings_screen_view.dart';
import 'turn_servers_screen.dart';
import '../state/avatar_service.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/peer_avatar.dart';
import '../widgets/server_config_import_dialog.dart';

/// Экран системных настроек: peer id и список bootstrap-серверов.
class SettingsScreen extends StatefulWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final ChatController chatController;
  final SelfHostedDeployService selfHostedDeployService;

  const SettingsScreen({
    super.key,
    required this.controller,
    required this.avatarService,
    required this.chatController,
    required this.selfHostedDeployService,
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
    _connectionStatusSubscription = controller.connectionStatusStream.listen((_) {
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
    _bootstrapAvailabilitySubscription = controller.bootstrapAvailabilityStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _relayAvailabilitySubscription = controller.relayAvailabilityStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
    _turnAvailabilitySubscription = controller.turnAvailabilityStream.listen((_) {
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
        return AlertDialog(
          title: const Text('Добавить bootstrap'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'wss://example'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addBootstrap(ctrl.text);
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('Добавить'),
            )
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
        return AlertDialog(
          title: const Text('Добавить relay'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(hintText: 'http://host:8080'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () async {
                await controller.addRelay(ctrl.text);
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('Добавить'),
            )
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
        return AlertDialog(
          title: const Text('Добавить TURN'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    hintText: 'turn:host:3478?transport=tcp;turn:host:3478?transport=udp',
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
              child: const Text('Отмена'),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$error')),
                  );
                  return;
                }
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context);
              },
              child: const Text('Добавить'),
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
        return AlertDialog(
          title: const Text('Удалить bootstrap?'),
          content: Text(
            'Сервер $endpoint будет удален из списка bootstrap.',
          ),
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
        return AlertDialog(
          title: const Text('Удалить relay?'),
          content: Text(
            'Сервер $endpoint будет удален из списка relay.',
          ),
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
        return AlertDialog(
          title: const Text('Удалить TURN?'),
          content: Text(
            'Сервер ${server.url} будет удален из списка TURN.',
          ),
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
    await controller.removeTurnServer(server.url);
    if (!mounted) {
      return true;
    }
    setState(() {});
    return true;
  }

  Future<void> _scanServerConfigQr() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const QrScanScreen(),
      ),
    );
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
        SnackBar(content: Text('Не удалось прочитать QR: $error')),
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
              ? 'Серверные параметры заменены из QR'
              : 'Серверные параметры объединены с данными из QR',
        ),
      ),
    );
  }

  Future<void> _shareServerConfigQr() async {
    await SharePlus.instance.share(
      ShareParams(
        text: controller.exportServerConfigQrPayload(),
      ),
    );
  }

  Future<void> _showAppLogPreview() async {
    final log = await controller.readAppLog();
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Лог приложения'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: SelectableText(
                log.isEmpty ? 'Лог пока пуст.' : log,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Закрыть'),
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
      ShareParams(
        files: [XFile(path)],
        text: 'PeerLink app log',
      ),
    );
  }

  Future<void> _clearAppLog() async {
    await controller.clearAppLog();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Лог приложения очищен')),
    );
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
      MaterialPageRoute(
        builder: (_) => const AvatarCaptureScreen(),
      ),
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
    await _processAvatarBytes(
      bytes,
      mimeType: _mimeTypeForPath(selected.name),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар обновлен')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить аватар: $error')),
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
        return AlertDialog(
          title: const Text('Удалить аватар?'),
          content: const Text('Аватар будет удален на этом и других устройствах.'),
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
      return;
    }
    await widget.avatarService.clearLocalAvatar();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Аватар удален')),
    );
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
                title: const Text('Сделать фото'),
                onTap: () => Navigator.of(context).pop('camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Выбрать из галереи'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              if (hasAvatar)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Удалить аватар'),
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

    final request = await showDialog<({String host, String login, String password})>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Установка своего сервиса'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: hostCtrl,
                decoration: const InputDecoration(
                  labelText: 'Сервер (IP/домен)',
                  hintText: '203.0.113.10',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: loginCtrl,
                decoration: const InputDecoration(labelText: 'Логин'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Пароль'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  (
                    host: hostCtrl.text.trim(),
                    login: loginCtrl.text.trim(),
                    password: passwordCtrl.text,
                  ),
                );
              },
              child: const Text('Установить'),
            ),
          ],
        );
      },
    );

    if (!mounted || request == null) {
      return;
    }
    if (request.host.isEmpty || request.login.isEmpty || request.password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните адрес сервера, логин и пароль')),
      );
      return;
    }

    final logs = <String>['Подготовка к установке...'];
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
                  appendLog('Сервисы добавлены в конфигурацию и подняты в начало списка.');
                  setDialogState(() {
                    completed = true;
                  });
                } catch (error) {
                  completionError = '$error';
                  appendLog('Ошибка: $error');
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
              title: Text('Развертывание сервиса • $elapsedText'),
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
                  onPressed: completed ? () => Navigator.of(dialogContext).pop() : null,
                  child: Text(completed ? 'Закрыть' : 'Выполняется...'),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Собственные серверы успешно развернуты и добавлены')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Развертывание не удалось: $completionError')),
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
    final qrPayload = controller.exportServerConfigQrPayload();
    final userQrPayload = controller.exportUserQrPayload();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Узел и маршрутизация',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Управление идентификатором, bootstrap, relay и TURN-серверами.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(28),
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
                        'Нажмите на кружок: фото, галерея или удаление аватара',
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
                    child: QrImageView(
                      data: userQrPayload,
                      size: 190,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(28),
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
                        'Установить свой серверный стек',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Развернет bootstrap, relay и TURN на вашем сервере, проверит доступность и добавит их в конфигурацию.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _installSelfHostedServers,
                        icon: const Icon(Icons.download_for_offline_outlined),
                        label: const Text('Инсталляция своего сервиса'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 0),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
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
                    'Сводка по доступности bootstrap-серверов. Нажмите, чтобы открыть полный список.',
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
          const SizedBox(height: 0),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
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
                    'Сводка по доступности relay-серверов. Нажмите, чтобы открыть полный список.',
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
          const SizedBox(height: 0),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.paper,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.stroke),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
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
                    'Сводка по доступности TURN-серверов. Нажмите, чтобы открыть полный список.',
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
          const SizedBox(height: 0),
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
                Text(
                  'QR конфигурации серверов',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Содержит bootstrap, relay и TURN-параметры. Этим QR можно поделиться, чтобы у товарища все серверы заполнились без ручного ввода.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _scanServerConfigQr,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Сканировать QR конфигурации'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _shareServerConfigQr,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Поделиться конфигурацией'),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: QrImageView(
                      data: qrPayload,
                      size: 220,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Формат: peerlink_server_config v1',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 0),
          FutureBuilder(
            future: controller.loadStorageBreakdown(),
            builder: (context, snapshot) {
              final breakdown = snapshot.data;
              final totalBytes = breakdown?.totalBytes ?? 0;
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.paper,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.stroke),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: _openStorageDetails,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Хранилище',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Занято: ${_formatBytes(totalBytes)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Разбивка по категориям данных и ручное удаление выбранных типов хранения.',
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
          const SizedBox(height: 0),
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
                Text(
                  'Лог приложения',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Полный runtime-лог для диагностики на реальном устройстве без Xcode.',
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
                      label: const Text('Показать лог'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _shareAppLog,
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Поделиться логом'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _clearAppLog,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Очистить лог'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 0),
          Center(
            child: Text(
              'Версия ${controller.appVersionLabel}',
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

  Widget _buildBootstrapSummaryChip({
    required Color color,
    required int value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.stroke),
      ),
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
