import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/runtime/account_pairing_payload.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../state/settings_controller.dart';
import 'qr_scan_screen.dart';
import 'settings_screen_formatters.dart';

class SettingsScreenPairingActions {
  final SettingsController controller;
  final bool Function() isMounted;
  final VoidCallback refreshUi;

  const SettingsScreenPairingActions({
    required this.controller,
    required this.isMounted,
    required this.refreshUi,
  });

  Future<void> scanAccountPairingQr(BuildContext context) async {
    if (!controller.canUsePairingQrControls) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.accountPairingScanBlockedManagedDevices,
          ),
        ),
      );
      return;
    }
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const QrScanScreen()));
    if (!isMounted() || result is! String || result.isEmpty) {
      return;
    }
    try {
      final payload = controller.parseAccountPairingDeepLink(result);
      if (!isMounted() || !context.mounted) {
        return;
      }
      await _showAccountPairingRequestDialog(context, result, payload);
    } catch (error) {
      if (!isMounted() || !context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.qrReadError(error))),
      );
    }
  }

  Future<void> tryApplyApprovedPairing(BuildContext context) async {
    final expired = await controller.expireStaleOutgoingAccountPairingIfNeeded();
    if (isMounted() && context.mounted && expired) {
      refreshUi();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.accountPairingRequestExpiredNotice),
        ),
      );
      return;
    }
    final rejected = await controller.consumeRejectedAccountPairingIfAvailable();
    if (isMounted() && context.mounted && rejected) {
      refreshUi();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.accountPairingRejectedNotice)),
      );
      return;
    }
    final identity = await controller.applyApprovedAccountPairingIfAvailable();
    if (!isMounted() || !context.mounted || identity == null) {
      return;
    }
    refreshUi();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.strings.accountPairingImported(identity.devices.length),
        ),
      ),
    );
  }

  Future<bool> showPendingPairingPromptIfNeeded(
    BuildContext context, {
    required bool promptShown,
  }) async {
    if (promptShown || controller.pendingAccountPairingRequest == null) {
      return promptShown;
    }
    final request = controller.pendingAccountPairingRequest!;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!isMounted()) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      await _showAccountPairingApprovalDialog(context, request);
    });
    return true;
  }

  Future<void> approveIncomingPairingRequest(
    BuildContext context,
    IncomingAccountPairingRequest request,
  ) async {
    if (!controller.isPrimaryAccountDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.accountDeviceManagementPrimaryOnlyNotice,
          ),
        ),
      );
      return;
    }
    await controller.approveIncomingAccountPairingRequest(request);
    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.accountPairingApprovedNotice)),
    );
  }

  Future<void> rejectIncomingPairingRequest(
    BuildContext context,
    IncomingAccountPairingRequest request,
  ) async {
    if (!controller.isPrimaryAccountDevice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.accountDeviceManagementPrimaryOnlyNotice,
          ),
        ),
      );
      return;
    }
    await controller.rejectIncomingAccountPairingRequest(
      request.payload.requestId,
    );
    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
  }

  Future<void> showAccountPairingSheet(BuildContext context) async {
    if (!controller.canUsePairingQrControls) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.accountPairingScanBlockedManagedDevices,
          ),
        ),
      );
      return;
    }
    if (!controller.hasWorkingPairingTransport) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.strings.accountPairingTransportUnavailable),
        ),
      );
      return;
    }
    await controller.initialize();
    if (!isMounted() || !context.mounted) {
      return;
    }
    final pairingLink = controller.exportAccountPairingDeepLink();
    final pairingShareLink = controller.exportAccountPairingShareLink();
    final pairingPayload = controller.parseAccountPairingDeepLink(pairingLink);
    final accountId = controller.accountId;
    final deviceId = controller.deviceId;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      clipBehavior: Clip.none,
      builder: (sheetContext) {
        final strings = sheetContext.strings;
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.paper,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppTheme.stroke),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          strings.accountPairingTitle,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    strings.accountPairingDescription,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceMuted,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppTheme.stroke),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.accountPairingWarning,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppTheme.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        StreamBuilder<int>(
                          initialData: pairingPayload.expiresAtMs,
                          stream: Stream<int>.periodic(
                            const Duration(seconds: 1),
                            (_) => pairingPayload.expiresAtMs,
                          ),
                          builder: (context, snapshot) {
                            return Text(
                              strings.accountPairingAvailableFor(
                                SettingsScreenFormatters.formatRemainingTime(
                                  snapshot.data!,
                                ),
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.muted,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.accountPairingQrSwitchWarning,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: QrImageView(data: pairingLink, size: 220),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    strings.accountId,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    accountId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    strings.currentDevice,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    deviceId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        unawaited(
                          SharePlus.instance.share(
                            ShareParams(
                              text: strings.accountPairingShareText(
                                accountId,
                                pairingShareLink,
                              ),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(strings.accountPairingLinkLabel),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAccountPairingApprovalDialog(
    BuildContext context,
    PendingAccountPairingRequest request,
  ) async {
    final payload = request.payload;
    final strings = context.strings;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(strings.accountPairingApproveTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.accountPairingApproveDescription),
              const SizedBox(height: 16),
              Text(
                strings.accountPairingExpiresAt(
                  SettingsScreenFormatters.formatDateTime(payload.expiresAtMs),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 12),
              Text(strings.accountId, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(payload.accountId),
              if (payload.displayName.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(strings.name, style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(payload.displayName),
              ],
              const SizedBox(height: 12),
              Text(strings.currentDevice, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(payload.targetDeviceId),
              const SizedBox(height: 12),
              Text(
                'Bootstrap / Relay / TURN',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${payload.serverConfig.bootstrap.length} / ${payload.serverConfig.relay.length} / ${payload.serverConfig.turn.length}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.accountPairingApproveAction),
            ),
          ],
        );
      },
    );
    if (!isMounted() || !context.mounted) {
      return;
    }
    if (approved == true) {
      await controller.approvePendingAccountPairing();
      if (!isMounted() || !context.mounted) {
        return;
      }
      refreshUi();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.accountPairingRequestSent)),
      );
      return;
    }
    await controller.clearPendingAccountPairingRequest();
    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
  }

  Future<void> _showAccountPairingRequestDialog(
    BuildContext context,
    String raw,
    AccountPairingPayload payload,
  ) async {
    final strings = context.strings;
    final currentAccountId = controller.activeAccountId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        return AlertDialog(
          title: Text(strings.accountPairingApproveTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.accountPairingRequestDescription),
              const SizedBox(height: 16),
              Text(
                strings.accountPairingExpiresAt(
                  SettingsScreenFormatters.formatDateTime(payload.expiresAtMs),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.stroke),
                ),
                child: Text(
                  strings.accountPairingSwitchAccountWarning(
                    currentAccountId,
                    payload.accountId,
                  ),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.accountPairingCurrentAccountLabel,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(currentAccountId),
              const SizedBox(height: 12),
              Text(
                strings.accountPairingTargetAccountLabel,
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(payload.accountId),
              if (payload.displayName.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(strings.name, style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(payload.displayName),
              ],
              const SizedBox(height: 12),
              Text(strings.currentDevice, style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              SelectableText(payload.targetDeviceId),
              const SizedBox(height: 12),
              Text(
                'Bootstrap / Relay / TURN',
                style: theme.textTheme.labelMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${payload.serverConfig.bootstrap.length} / ${payload.serverConfig.relay.length} / ${payload.serverConfig.turn.length}',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.accountPairingRequestAction),
            ),
          ],
        );
      },
    );
    if (!isMounted() || !context.mounted || approved != true) {
      return;
    }
    await controller.requestAccountPairingDeepLink(raw);
    if (!isMounted() || !context.mounted) {
      return;
    }
    refreshUi();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.accountPairingRequestSent)),
    );
  }
}
