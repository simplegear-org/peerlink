import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/runtime/avatar_service.dart';
import '../../core/runtime/self_hosted_deploy_service.dart';
import '../../core/turn/turn_server_config.dart';
import '../localization/app_strings.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import '../widgets/server_config_import_dialog.dart';
import 'account_device_history_screen.dart';
import 'account_devices_screen.dart';
import 'bootstrap_servers_screen.dart';
import 'push_servers_screen.dart';
import 'qr_scan_screen.dart';
import 'relay_servers_screen.dart';
import 'storage_details_screen.dart';
import 'turn_servers_screen.dart';

class SettingsScreenSystemActions {
  final SettingsController controller;
  final AvatarService avatarService;
  final ChatController chatController;
  final SelfHostedDeployService selfHostedDeployService;
  final bool Function() isMounted;
  final VoidCallback refreshUi;

  const SettingsScreenSystemActions({
    required this.controller,
    required this.avatarService,
    required this.chatController,
    required this.selfHostedDeployService,
    required this.isMounted,
    required this.refreshUi,
  });

  Future<bool> confirmDeleteBootstrap(
    BuildContext context,
    String endpoint,
  ) async {
    return _confirmDeleteServer(
      context,
      serverType: 'bootstrap',
      endpoint: endpoint,
      onDelete: () => controller.removeBootstrap(endpoint),
    );
  }

  Future<bool> confirmDeleteRelay(BuildContext context, String endpoint) async {
    return _confirmDeleteServer(
      context,
      serverType: 'relay',
      endpoint: endpoint,
      onDelete: () => controller.removeRelay(endpoint),
    );
  }

  Future<bool> confirmDeleteTurn(
    BuildContext context,
    TurnServerConfig server,
  ) async {
    return _confirmDeleteServer(
      context,
      serverType: 'TURN',
      endpoint: server.url,
      onDelete: () => controller.removeTurnServer(server.url),
    );
  }

  Future<bool> confirmDeletePush(BuildContext context, String endpoint) async {
    return _confirmDeleteServer(
      context,
      serverType: 'Push',
      endpoint: endpoint,
      onDelete: () => controller.removePushServer(endpoint),
    );
  }

  Future<void> scanServerConfigQr(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (!isMounted() || result is! String || result.isEmpty) {
      return;
    }
    ServerConfigImportMode? mode;
    try {
      final payload = controller.parseServerConfigQrPayload(result);
      if (!context.mounted) {
        return;
      }
      mode = await showServerConfigImportDialog(
        context,
        controller: controller,
        payload: payload,
      );
      if (!isMounted() || !context.mounted || mode == null) {
        return;
      }
      await controller.importServerConfigPayload(payload, mode: mode);
    } catch (error) {
      if (!isMounted() || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.qrReadError(error))),
      );
      return;
    }
    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
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

  Future<void> shareServerConfigQr() async {
    await SharePlus.instance.share(
      ShareParams(text: controller.exportServerConfigShareText()),
    );
  }

  Future<void> showAppLogPreview(BuildContext context) async {
    final log = await controller.readAppLog();
    if (!isMounted() || !context.mounted) {
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

  Future<void> shareAppLog(BuildContext context) async {
    final path = await controller.appLogFilePath();
    if (!isMounted() || path == null || path.isEmpty) {
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(path)], text: 'PeerLink app log'),
    );
  }

  Future<void> clearAppLog(BuildContext context) async {
    await controller.clearAppLog();
    if (!isMounted() || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.logCleared)));
  }

  Future<void> confirmResetLocalAccount(BuildContext context) async {
    await _confirmAndRunReset(
      context,
      title: context.strings.resetLocalAccountTitle,
      description: context.strings.resetLocalAccountDescription,
      actionLabel: context.strings.resetLocalAccount,
      onConfirm: () async {
        await controller.resetLocalAccount();
        await avatarService.clearAllAvatarMedia();
        chatController.clearAllChatsFromMemory();
      },
    );
  }

  Future<void> confirmResetDeviceCompletely(BuildContext context) async {
    await _confirmAndRunReset(
      context,
      title: context.strings.resetDeviceCompletelyTitle,
      description: context.strings.resetDeviceCompletelyDescription,
      actionLabel: context.strings.resetDeviceCompletely,
      onConfirm: () async {
        await controller.resetDeviceCompletely();
        await avatarService.clearAllAvatarMedia();
        chatController.clearAllChatsFromMemory();
      },
    );
  }

  Future<void> openStorageDetails(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StorageDetailsScreen(
          controller: controller,
          avatarService: avatarService,
          chatController: chatController,
        ),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> openBootstrapServers(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BootstrapServersScreen(
          controller: controller,
          onDeleteBootstrap: (endpoint) =>
              confirmDeleteBootstrap(context, endpoint),
        ),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> openRelayServers(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RelayServersScreen(
          controller: controller,
          onDeleteRelay: (endpoint) => confirmDeleteRelay(context, endpoint),
        ),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> openTurnServers(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TurnServersScreen(
          controller: controller,
          onDeleteTurn: (server) => confirmDeleteTurn(context, server),
        ),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> openPushServers(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PushServersScreen(
          controller: controller,
          onDeletePush: (endpoint) => confirmDeletePush(context, endpoint),
        ),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> openAccountDevices(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountDevicesScreen(controller: controller),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> openAccountDeviceHistory(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountDeviceHistoryScreen(controller: controller),
      ),
    );
    if (isMounted() && context.mounted) {
      refreshUi();
    }
  }

  Future<void> installSelfHostedServers(BuildContext context) async {
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: hostCtrl,
                      decoration: InputDecoration(
                        labelText: strings.serverHostLabel,
                        hintText: '203.0.113.10 or peerlink.example.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: hostCtrl,
                      builder: (context, value, _) {
                        final preview = selfHostedDeployService.previewForHost(
                          value.text,
                        );
                        if (preview == null) {
                          return const SizedBox.shrink();
                        }
                        final previewLines = <String>[
                          'Preview',
                          'Bootstrap: ${preview.bootstrapEndpoint}',
                          'Relay: ${preview.relayEndpoint}',
                          ...preview.turnServers.map(
                            (server) => 'TURN: ${server.url}',
                          ),
                        ];
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            previewLines.join('\n'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      },
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
    if (!isMounted() || !context.mounted || request == null) {
      return;
    }
    if (request.host.isEmpty ||
        request.login.isEmpty ||
        request.password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.fillServerLoginPassword),
        ),
      );
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
                  if (!isMounted() || completed) {
                    return;
                  }
                  setDialogState(() {});
                });
                try {
                  final result = await selfHostedDeployService.deploy(
                    host: request.host,
                    username: request.login,
                    password: request.password,
                    onProgress: appendLog,
                  );
                  await controller.addSelfHostedServersFirst(
                    bootstrapEndpoint: result.bootstrapEndpoint,
                    relayEndpoint: result.relayEndpoint,
                    turnServers: result.turnServers,
                  );
                  if (!isMounted() || !context.mounted) {
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
                    logs.join('\n'),
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

    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
    if (completionError == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.ownServersDeployed)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.deployFailed(completionError!))),
    );
  }

  Future<bool> _confirmDeleteServer(
    BuildContext context, {
    required String serverType,
    required String endpoint,
    required Future<void> Function() onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.deleteServerTitle(serverType)),
          content: Text(strings.deleteServerContent(serverType, endpoint)),
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
    await onDelete();
    if (isMounted() && context.mounted) {
      refreshUi();
    }
    return true;
  }

  Future<void> _confirmAndRunReset(
    BuildContext context, {
    required String title,
    required String description,
    required String actionLabel,
    required Future<void> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(title),
          content: Text(description),
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
              child: Text(actionLabel),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await onConfirm();
    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.resetRestartRequiredNotice)),
    );
  }
}
