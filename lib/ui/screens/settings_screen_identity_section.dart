import 'dart:io';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/runtime/avatar_service.dart';
import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/peer_avatar.dart';
import 'settings_screen_shared_widgets.dart';

class SettingsIdentitySection extends StatelessWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final Future<void> Function() onShowAvatarActions;

  const SettingsIdentitySection({
    super.key,
    required this.controller,
    required this.avatarService,
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
    final peerIdLabel = _shortId(controller.peerId);
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
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: QrImageView(
                data: controller.exportUserQrPayload(),
                size: 190,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortOptionalId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '—';
    }
    return _shortId(trimmed);
  }

  String _shortId(String value) {
    final trimmed = value.trim();
    if (trimmed.length <= 8) {
      return trimmed;
    }
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
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
