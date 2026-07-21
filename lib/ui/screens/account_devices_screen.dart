import 'package:flutter/material.dart';

import '../../core/security/account_identity.dart';
import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';

class AccountDevicesScreen extends StatefulWidget {
  final SettingsController controller;

  const AccountDevicesScreen({super.key, required this.controller});

  @override
  State<AccountDevicesScreen> createState() => _AccountDevicesScreenState();
}

class _AccountDevicesScreenState extends State<AccountDevicesScreen> {
  SettingsController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final isPrimary = controller.isPrimaryAccountDevice;
    final devices = controller.accountIdentity.devices.toList(growable: false)
      ..sort((a, b) {
        if (a.isCurrentDevice == b.isCurrentDevice) {
          return a.createdAtMs.compareTo(b.createdAtMs);
        }
        return a.isCurrentDevice ? -1 : 1;
      });
    final otherDevices = devices.where((device) => !device.isCurrentDevice);
    return Scaffold(
      appBar: AppBar(title: Text(strings.accountDevicesManageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            isPrimary
                ? strings.accountDevicesManageDescription
                : strings.accountDeviceManagementPrimaryOnlyDescription,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          if (!isPrimary) ...[
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
                strings.accountDeviceManagementPrimaryOnlyNotice,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: !isPrimary || otherDevices.isEmpty
                  ? null
                  : () => _confirmRevokeAllOtherDevices(),
              icon: const Icon(Icons.devices_other_rounded),
              label: Text(strings.revokeAllOtherDevices),
            ),
          ),
          const SizedBox(height: 16),
          if (devices.isEmpty)
            Text(
              strings.accountDevicesEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            )
          else
            ...devices.map(_buildDeviceCard),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(AccountDeviceIdentity device) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final isCurrent = device.isCurrentDevice;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortId(device.deviceId),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.pineSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      strings.currentDeviceBadge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              device.peerId,
              style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
            ),
            if (!isCurrent) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: controller.isPrimaryAccountDevice
                      ? () => _confirmRevokeDevice(device)
                      : null,
                  icon: const Icon(Icons.person_remove_outlined),
                  label: Text(strings.revokeDevice),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRevokeDevice(AccountDeviceIdentity device) async {
    final strings = context.strings;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.revokeDeviceTitle),
          content: Text(
            strings.revokeDeviceDescription(_shortId(device.deviceId)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.revokeDevice),
            ),
          ],
        );
      },
    );
    if (approved != true) {
      return;
    }
    await controller.revokeAccountDevice(device.deviceId);
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.deviceRevokedNotice)));
  }

  Future<void> _confirmRevokeAllOtherDevices() async {
    final strings = context.strings;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(strings.revokeAllOtherDevicesTitle),
          content: Text(strings.revokeAllOtherDevicesDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(strings.revokeAllOtherDevices),
            ),
          ],
        );
      },
    );
    if (approved != true) {
      return;
    }
    await controller.revokeAllOtherAccountDevices();
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.otherDevicesRevokedNotice)));
  }

  String _shortId(String value) {
    final normalized = value.trim();
    if (normalized.length <= 12) {
      return normalized;
    }
    return '${normalized.substring(0, 6)}…${normalized.substring(normalized.length - 4)}';
  }
}
