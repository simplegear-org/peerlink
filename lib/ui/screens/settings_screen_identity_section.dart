// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../features/profile/application/avatar_service.dart';
import '../../core/runtime/moderation_policy_service.dart';
import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/peer_avatar.dart';
import 'settings_screen_formatters.dart';
import 'settings_screen_shared_widgets.dart';

class SettingsIdentitySection extends StatelessWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final ModerationPolicySnapshot moderationPolicy;
  final Future<void> Function() onShowAvatarActions;

  const SettingsIdentitySection({
    super.key,
    required this.controller,
    required this.avatarService,
    required this.moderationPolicy,
    required this.onShowAvatarActions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isApplePlatform = Platform.isIOS || Platform.isMacOS;
    final pushTokenLabel = isApplePlatform ? 'APNS token' : 'FCM token';
    final pushTokenValue =
        (isApplePlatform ? controller.apnsToken : controller.fcmToken)?.trim();
    final voipTokenValue = controller.voipToken?.trim();
    final peerIdLabel = SettingsScreenFormatters.shortId(
      controller.peerId,
      maxLength: 8,
      prefixLength: 4,
      separator: '...',
    );
    final pushTokenLabelValue = _shortOptionalId(pushTokenValue);
    final voipTokenLabelValue = _shortOptionalId(voipTokenValue);

    return SettingsSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SettingsIdentityValueRow(label: 'Peer ID', value: peerIdLabel),
          const SizedBox(height: 12),
          _SettingsIdentityValueRow(
            label: pushTokenLabel,
            value: pushTokenLabelValue,
          ),
          if (isApplePlatform) ...[
            const SizedBox(height: 12),
            _SettingsIdentityValueRow(
              label: 'VoIP token',
              value: voipTokenLabelValue,
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              InkWell(
                onTap: () => onShowAvatarActions(),
                borderRadius: BorderRadius.circular(999),
                child: PeerAvatar(
                  peerId: controller.peerId,
                  displayName: controller.peerId,
                  avatarService: avatarService,
                  size: 56,
                  showInitialWhenNoAvatar: false,
                  backgroundColor: AppTheme.pineSoft,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.strings.avatarHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _SettingsUserQrCode(controller: controller),
          if (moderationPolicy.isWarning || moderationPolicy.isBanned) ...[
            const SizedBox(height: 12),
            _SettingsModerationStatus(policy: moderationPolicy),
          ],
        ],
      ),
    );
  }

  String _shortOptionalId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '—';
    }
    return SettingsScreenFormatters.shortId(
      trimmed,
      maxLength: 8,
      prefixLength: 4,
      separator: '...',
    );
  }
}

class _SettingsModerationStatus extends StatelessWidget {
  final ModerationPolicySnapshot policy;

  const _SettingsModerationStatus({required this.policy});

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final message = policy.isBanned
        ? strings.moderationBanMessage(
            reportCount: policy.reportCount,
            reporterCount: policy.reporterCount,
          )
        : strings.moderationWarningMessage(
            reportCount: policy.reportCount,
            reporterCount: policy.reporterCount,
          );
    return Text(
      message,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.error,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SettingsUserQrCode extends StatefulWidget {
  final SettingsController controller;

  const _SettingsUserQrCode({required this.controller});

  @override
  State<_SettingsUserQrCode> createState() => _SettingsUserQrCodeState();
}

class _SettingsUserQrCodeState extends State<_SettingsUserQrCode> {
  late String _signature;
  late String _payload;

  @override
  void initState() {
    super.initState();
    _refreshPayload();
  }

  @override
  void didUpdateWidget(covariant _SettingsUserQrCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _buildSignature();
    if (signature != _signature) {
      _signature = signature;
      _payload = widget.controller.exportUserQrPayload();
    }
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
          child: QrImageView(data: _payload, size: 190),
        ),
      ),
    );
  }

  void _refreshPayload() {
    _signature = _buildSignature();
    _payload = widget.controller.exportUserQrPayload();
  }

  String _buildSignature() {
    final controller = widget.controller;
    return '${controller.peerId}|${controller.endpointId ?? ''}|'
        '${controller.fcmTokenHash ?? ''}';
  }
}

class _SettingsIdentityValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _SettingsIdentityValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: SelectableText(
              value,
              maxLines: 1,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}
