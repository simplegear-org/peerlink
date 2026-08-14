// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/runtime/app_storage_stats.dart';
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

class SettingsPushServerSharingSection extends StatelessWidget {
  final SettingsController controller;
  final Future<void> Function(bool value) onSetShareServersInPush;
  final Future<void> Function(bool value) onSetReceiveServersFromPush;

  const SettingsPushServerSharingSection({
    super.key,
    required this.controller,
    required this.onSetShareServersInPush,
    required this.onSetReceiveServersFromPush,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    final shareEnabled = controller.shareServersInPush;
    final receiveEnabled = controller.receiveServersFromPush;
    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.pushServerSharingTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            strings.pushServerSharingDescription,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.shareServersInPush),
            value: shareEnabled,
            onChanged: (value) => onSetShareServersInPush(value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(strings.receiveServersFromPush),
            value: shareEnabled && receiveEnabled,
            onChanged: shareEnabled
                ? (value) => onSetReceiveServersFromPush(value)
                : null,
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

class SettingsServerSummaryStreamSection extends StatelessWidget {
  final String title;
  final String description;
  final Future<void> Function() onTap;
  final Stream<dynamic> updates;
  final int Function() availableCount;
  final int Function() unavailableCount;

  const SettingsServerSummaryStreamSection({
    super.key,
    required this.title,
    required this.description,
    required this.onTap,
    required this.updates,
    required this.availableCount,
    required this.unavailableCount,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<dynamic>(
      stream: updates,
      builder: (context, _) {
        return SettingsServerSummarySection(
          title: title,
          description: description,
          onTap: onTap,
          availableCount: availableCount(),
          unavailableCount: unavailableCount(),
        );
      },
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
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
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
          _SettingsServerConfigQrCode(controller: controller),
          const SizedBox(height: 12),
          Text(
            strings.serverConfigFormat,
            style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}

class _SettingsServerConfigQrCode extends StatefulWidget {
  final SettingsController controller;

  const _SettingsServerConfigQrCode({required this.controller});

  @override
  State<_SettingsServerConfigQrCode> createState() =>
      _SettingsServerConfigQrCodeState();
}

class _SettingsServerConfigQrCodeState
    extends State<_SettingsServerConfigQrCode> {
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _refreshDebounce;
  late String _payload;

  @override
  void initState() {
    super.initState();
    _payload = widget.controller.exportServerConfigQrPayload();
    _bindStreams();
  }

  @override
  void didUpdateWidget(covariant _SettingsServerConfigQrCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) {
      return;
    }
    _clearSubscriptions();
    _payload = widget.controller.exportServerConfigQrPayload();
    _bindStreams();
  }

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    _clearSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: RepaintBoundary(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: QrImageView(data: _payload, size: 220),
        ),
      ),
    );
  }

  void _bindStreams() {
    _subscriptions
      ..add(widget.controller.bootstrapAvailabilityStream.listen(_queueRefresh))
      ..add(widget.controller.relayAvailabilityStream.listen(_queueRefresh))
      ..add(widget.controller.turnAvailabilityStream.listen(_queueRefresh))
      ..add(widget.controller.pushAvailabilityStream.listen(_queueRefresh));
  }

  void _queueRefresh(dynamic _) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) {
        return;
      }
      final payload = widget.controller.exportServerConfigQrPayload();
      if (payload == _payload) {
        return;
      }
      setState(() {
        _payload = payload;
      });
    });
  }

  void _clearSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}

class SettingsStorageSection extends StatefulWidget {
  final SettingsController controller;
  final Future<void> Function() onOpenStorageDetails;

  const SettingsStorageSection({
    super.key,
    required this.controller,
    required this.onOpenStorageDetails,
  });

  @override
  State<SettingsStorageSection> createState() => _SettingsStorageSectionState();
}

class _SettingsStorageSectionState extends State<SettingsStorageSection> {
  late Future<AppStorageBreakdown> _breakdownFuture;

  @override
  void initState() {
    super.initState();
    _breakdownFuture = widget.controller.loadStorageBreakdown();
  }

  @override
  void didUpdateWidget(covariant SettingsStorageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _breakdownFuture = widget.controller.loadStorageBreakdown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return FutureBuilder(
      future: _breakdownFuture,
      builder: (context, snapshot) {
        final breakdown = snapshot.data;
        final totalBytes = breakdown?.totalBytes ?? 0;
        return SettingsSectionCard(
          child: InkWell(
            borderRadius: BorderRadius.circular(
              SettingsScreenStyles.sectionRadius,
            ),
            onTap: () => widget.onOpenStorageDetails(),
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
