// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../../features/profile/application/avatar_service.dart';
import '../../features/profile/application/peer_profile_read_model.dart';
import '../../features/notifications/application/notification_mute_preferences.dart';
import '../../features/notifications/domain/notification_mute_state.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/peer_avatar.dart';
import 'notification_mute_actions.dart';

class PeerProfileScreen extends StatefulWidget {
  const PeerProfileScreen({
    super.key,
    required this.peerId,
    required this.profile,
    required this.avatarService,
    this.notificationMutes,
    this.onMessageNotificationsPressed,
    this.onCallNotificationsPressed,
    this.onAddContact,
  });

  final String peerId;
  final PeerProfileReadApi profile;
  final AvatarService avatarService;
  final NotificationMutePreferences? notificationMutes;
  final VoidCallback? onMessageNotificationsPressed;
  final VoidCallback? onCallNotificationsPressed;
  final Future<void> Function(String peerId)? onAddContact;

  @override
  State<PeerProfileScreen> createState() => _PeerProfileScreenState();
}

class _PeerProfileScreenState extends State<PeerProfileScreen> {
  bool _addingContact = false;

  Future<void> _addContact() async {
    final action = widget.onAddContact;
    if (action == null || _addingContact) return;
    setState(() => _addingContact = true);
    try {
      await action(widget.peerId);
    } finally {
      if (mounted) {
        setState(() => _addingContact = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final peer = widget.profile.readForPeer(widget.peerId);
    final avatarSize = MediaQuery.sizeOf(context).width - 48;
    return Scaffold(
      appBar: AppBar(title: Text(strings.peerProfile)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Center(
            child: PeerAvatar(
              peerId: peer.peerId,
              displayName: peer.preferredDisplayName,
              avatarService: widget.avatarService,
              size: avatarSize,
              circular: false,
              imageFit: BoxFit.contain,
              fallbackSize: 112,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            peer.preferredDisplayName,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            strings.aboutUser,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            peer.hasAbout ? peer.about : strings.notSpecified,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: peer.hasAbout ? null : AppTheme.muted,
            ),
          ),
          if (!peer.isLocalPeer) ...[
            const SizedBox(height: 28),
            if (widget.notificationMutes case final notificationMutes?)
              NotificationMuteActions(
                targetId: peer.peerId,
                messageChannel: NotificationMuteChannel.directMessage,
                callChannel: NotificationMuteChannel.directCall,
                preferences: notificationMutes,
              )
            else ...[
              _ActionTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: strings.messageNotifications,
                onTap: widget.onMessageNotificationsPressed,
              ),
              _ActionTile(
                icon: Icons.call_outlined,
                title: strings.callNotifications,
                onTap: widget.onCallNotificationsPressed,
              ),
            ],
            const SizedBox(height: 12),
            if (peer.isContact)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_rounded),
                title: Text(strings.inContacts),
              )
            else
              FilledButton.icon(
                onPressed: _addingContact || widget.onAddContact == null
                    ? null
                    : _addContact,
                icon: _addingContact
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(strings.addContact),
              ),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
