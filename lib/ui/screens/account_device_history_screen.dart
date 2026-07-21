import 'package:flutter/material.dart';

import '../../core/runtime/account_device_event.dart';
import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';

class AccountDeviceHistoryScreen extends StatelessWidget {
  final SettingsController controller;

  const AccountDeviceHistoryScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final events = controller.accountDeviceEvents;
    return Scaffold(
      appBar: AppBar(title: Text(strings.accountDeviceHistoryTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!controller.isPrimaryAccountDevice) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.stroke),
              ),
              child: Text(
                strings.accountDeviceManagementPrimaryOnlyDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (events.isEmpty)
            Text(
              strings.accountDeviceHistoryEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            )
          else
            ...events.map((event) {
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
                        _accountDeviceEventTitle(event, strings),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatDateTime(event.timestampMs),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  String _shortId(String value) {
    final normalized = value.trim();
    if (normalized.length <= 12) {
      return normalized;
    }
    return '${normalized.substring(0, 6)}…${normalized.substring(normalized.length - 4)}';
  }

  String _formatDateTime(int timestampMs) {
    if (timestampMs <= 0) {
      return '—';
    }
    final value = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  String _accountDeviceEventTitle(
    AccountDeviceEvent event,
    AppStrings strings,
  ) {
    final shortDeviceId = _shortId(event.deviceId ?? '');
    switch (event.type) {
      case AccountDeviceEventType.pairingRequestSent:
        return strings.accountDeviceEventPairRequestSent(shortDeviceId);
      case AccountDeviceEventType.pairingApproved:
        return strings.accountDeviceEventPairApproved(shortDeviceId);
      case AccountDeviceEventType.pairingRejected:
        return strings.accountDeviceEventPairRejected(shortDeviceId);
      case AccountDeviceEventType.deviceAdded:
        return strings.accountDeviceEventAdded(shortDeviceId);
      case AccountDeviceEventType.deviceRemoved:
        return strings.accountDeviceEventRemoved(shortDeviceId);
    }
  }
}
