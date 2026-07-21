import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import 'settings_screen_formatters.dart';
import 'settings_screen_shared_widgets.dart';
import 'settings_screen_styles.dart';

class SettingsSelfHostedSection extends StatelessWidget {
  final Future<void> Function() onInstallSelfHostedServers;

  const SettingsSelfHostedSection({
    super.key,
    required this.onInstallSelfHostedServers,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return SettingsSectionCard(
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
                  onPressed: () => onInstallSelfHostedServers(),
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: Text(strings.installOwnService),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsServerSummarySection extends StatelessWidget {
  final String title;
  final String description;
  final Future<void> Function() onTap;
  final int availableCount;
  final int unavailableCount;

  const SettingsServerSummarySection({
    super.key,
    required this.title,
    required this.description,
    required this.onTap,
    required this.availableCount,
    required this.unavailableCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsSectionCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(SettingsScreenStyles.sectionRadius),
        onTap: () => onTap(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.muted,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SettingsSummaryChip(
                  color: Colors.green.shade600,
                  value: availableCount,
                ),
                const SizedBox(width: 12),
                SettingsSummaryChip(
                  color: Colors.red.shade600,
                  value: unavailableCount,
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsServerQrSection extends StatelessWidget {
  final SettingsController controller;
  final Future<void> Function() onScanServerConfigQr;
  final Future<void> Function() onShareServerConfigQr;

  const SettingsServerQrSection({
    super.key,
    required this.controller,
    required this.onScanServerConfigQr,
    required this.onShareServerConfigQr,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return SettingsSectionCard(
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
            onPressed: () => onScanServerConfigQr(),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: Text(strings.scanServerQr),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => onShareServerConfigQr(),
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
              child: QrImageView(
                data: controller.exportServerConfigQrPayload(),
                size: 220,
              ),
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
    );
  }
}

class SettingsStorageSection extends StatelessWidget {
  final SettingsController controller;
  final Future<void> Function() onOpenStorageDetails;

  const SettingsStorageSection({
    super.key,
    required this.controller,
    required this.onOpenStorageDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return FutureBuilder(
      future: controller.loadStorageBreakdown(),
      builder: (context, snapshot) {
        final breakdown = snapshot.data;
        final totalBytes = breakdown?.totalBytes ?? 0;
        return SettingsSectionCard(
          child: InkWell(
            borderRadius: BorderRadius.circular(
              SettingsScreenStyles.sectionRadius,
            ),
            onTap: () => onOpenStorageDetails(),
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
                  strings.storageUsed(
                    SettingsScreenFormatters.formatBytes(totalBytes),
                  ),
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
    );
  }
}
