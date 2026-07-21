import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'settings_screen_account_widgets.dart';
import 'settings_screen_formatters.dart';
import 'settings_screen_shared_widgets.dart';

class SettingsAccountDevicesSection extends StatelessWidget {
  final SettingsController controller;
  final Future<void> Function() onShowAccountPairingSheet;
  final Future<void> Function() onScanAccountPairingQr;
  final Future<void> Function() onOpenAccountDevices;
  final Future<void> Function() onOpenAccountDeviceHistory;
  final Future<void> Function(IncomingAccountPairingRequest request)
  onApproveIncomingPairingRequest;
  final Future<void> Function(IncomingAccountPairingRequest request)
  onRejectIncomingPairingRequest;

  const SettingsAccountDevicesSection({
    super.key,
    required this.controller,
    required this.onShowAccountPairingSheet,
    required this.onScanAccountPairingQr,
    required this.onOpenAccountDevices,
    required this.onOpenAccountDeviceHistory,
    required this.onApproveIncomingPairingRequest,
    required this.onRejectIncomingPairingRequest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final isPrimaryAccountDevice = controller.isPrimaryAccountDevice;
    final canUsePairingQrControls = controller.canUsePairingQrControls;

    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(strings.accountDevicesTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            strings.accountDevicesDescription,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppTheme.muted,
            ),
          ),
          const SizedBox(height: 12),
          if (isPrimaryAccountDevice)
            Row(
              children: [
                Expanded(
                  child: SettingsAccountInfoPill(
                    label: strings.accountId,
                    value: SettingsScreenFormatters.shortId(controller.accountId),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SettingsAccountInfoPill(
                    label: strings.devices,
                    value: '${controller.accountDeviceCount}',
                    onTap: onOpenAccountDevices,
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsAccountInfoPill(
                  label: strings.accountId,
                  value: SettingsScreenFormatters.shortId(controller.accountId),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.accountDeviceManagementPrimaryOnlyTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        strings.accountDeviceManagementPrimaryOnlyDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canUsePairingQrControls)
                FilledButton.icon(
                  onPressed: () => onShowAccountPairingSheet(),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(strings.showPairingQr),
                ),
              if (canUsePairingQrControls)
                OutlinedButton.icon(
                  onPressed: () => onScanAccountPairingQr(),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(strings.scanPairingQr),
                ),
              if (isPrimaryAccountDevice)
                OutlinedButton.icon(
                  onPressed: () => onOpenAccountDeviceHistory(),
                  icon: const Icon(Icons.history_rounded),
                  label: Text(strings.accountDeviceHistoryButton),
                ),
            ],
          ),
          if (controller.outgoingAccountPairingRequest != null) ...[
            const SizedBox(height: 12),
            Text(
              strings.accountPairingWaitingApproval,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
          ],
          if (isPrimaryAccountDevice &&
              controller.incomingAccountPairingRequests.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              strings.accountPairingRequestsTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              strings.accountPairingRequestsDescription,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 12),
            ...controller.incomingAccountPairingRequests.map((request) {
              final displayName = request.payload.requesterDisplayName.trim();
              final requesterName = displayName.isNotEmpty
                  ? displayName
                  : SettingsScreenFormatters.shortId(
                      request.payload.requesterPeerId,
                    );
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.stroke),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requesterName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.accountPairingRequestFrom(
                          SettingsScreenFormatters.shortId(
                            request.payload.requesterDeviceId,
                          ),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  onRejectIncomingPairingRequest(request),
                              child: Text(strings.reject),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: () =>
                                  onApproveIncomingPairingRequest(request),
                              child: Text(strings.approve),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}
