// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/profile/application/avatar_service.dart';
import 'package:peerlink/features/profile/application/peer_profile_read_model.dart';
import 'package:peerlink/features/notifications/application/notification_mute_preferences.dart';
import 'package:peerlink/features/notifications/domain/notification_mute_state.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/compact_card_tile_styles.dart';
import '../widgets/peer_avatar.dart';
import '../widgets/swipe_delete_tile.dart';
import 'notification_mute_actions.dart';

class GroupInfoScreen extends StatefulWidget {
  const GroupInfoScreen({
    super.key,
    required this.chat,
    required this.peerProfile,
    required this.avatarService,
    this.notificationMutes,
    this.onMessageNotificationsPressed,
    this.onCallNotificationsPressed,
    this.onParticipantPressed,
    this.canManageParticipants = false,
    this.localPeerId,
    this.onAddParticipantsPressed,
    this.onRemoveParticipantPressed,
  });

  final Chat chat;
  final PeerProfileReadApi peerProfile;
  final AvatarService avatarService;
  final NotificationMutePreferences? notificationMutes;
  final VoidCallback? onMessageNotificationsPressed;
  final VoidCallback? onCallNotificationsPressed;
  final Future<void> Function(String peerId)? onParticipantPressed;
  final bool canManageParticipants;
  final String? localPeerId;
  final Future<void> Function()? onAddParticipantsPressed;
  final Future<void> Function(String peerId)? onRemoveParticipantPressed;

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  Future<void> _addParticipants() async {
    final action = widget.onAddParticipantsPressed;
    if (action == null) return;
    await action();
    if (mounted) setState(() {});
  }

  Future<bool> _removeParticipant(String peerId) async {
    final action = widget.onRemoveParticipantPressed;
    if (action == null) return false;
    final peer = widget.peerProfile.readForPeer(peerId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final strings = dialogContext.strings;
        return AlertDialog(
          title: Text(strings.removeParticipants),
          content: Text(peer.preferredDisplayName),
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
    if (confirmed != true) return false;
    await action(peerId);
    if (mounted) setState(() {});
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final avatarSize = MediaQuery.sizeOf(context).width - 48;
    final memberIds = widget.chat.memberPeerIds.toSet().toList(growable: false)
      ..sort();
    return Scaffold(
      appBar: AppBar(title: Text(strings.groupInfo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        children: [
          Center(
            child: PeerAvatar(
              peerId: widget.chat.peerId,
              displayName: widget.chat.name,
              avatarService: widget.avatarService,
              imagePath: widget.chat.avatarPath,
              size: avatarSize,
              circular: false,
              imageFit: BoxFit.contain,
              fallbackSize: 112,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.chat.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),
          if (widget.notificationMutes case final notificationMutes?)
            NotificationMuteActions(
              targetId: widget.chat.peerId,
              messageChannel: NotificationMuteChannel.groupMessage,
              callChannel: NotificationMuteChannel.groupCall,
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
          const SizedBox(height: 28),
          Row(
            children: [
              Expanded(
                child: Text(
                  strings.groupMembers(memberIds.length),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (widget.canManageParticipants &&
                  widget.onAddParticipantsPressed != null)
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: strings.addParticipants,
                  onPressed: _addParticipants,
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < memberIds.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == memberIds.length - 1
                    ? 0
                    : CompactCardTileStyles.tileSeparatorHeight,
              ),
              child: _ParticipantTile(
                peer: widget.peerProfile.readForPeer(memberIds[index]),
                avatarService: widget.avatarService,
                role: _roleFor(memberIds[index], strings),
                onTap: widget.onParticipantPressed == null
                    ? null
                    : () => widget.onParticipantPressed!(memberIds[index]),
                onDeleteRequested: _canRemoveParticipant(memberIds[index])
                    ? () => _removeParticipant(memberIds[index])
                    : null,
              ),
            ),
        ],
      ),
    );
  }

  String? _roleFor(String peerId, AppStrings strings) {
    if (peerId == widget.chat.ownerPeerId?.trim()) {
      return strings.groupOwner;
    }
    return widget.chat.adminPeerIds.contains(peerId)
        ? strings.groupAdmin
        : null;
  }

  bool _canRemoveParticipant(String peerId) {
    return widget.canManageParticipants &&
        widget.onRemoveParticipantPressed != null &&
        peerId != widget.localPeerId?.trim() &&
        peerId != widget.chat.ownerPeerId?.trim();
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

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.peer,
    required this.avatarService,
    required this.role,
    required this.onTap,
    this.onDeleteRequested,
  });

  final PeerProfileReadModel peer;
  final AvatarService avatarService;
  final String? role;
  final Future<void> Function()? onTap;
  final Future<bool> Function()? onDeleteRequested;

  @override
  Widget build(BuildContext context) {
    final foreground = Container(
      padding: CompactCardTileStyles.tilePadding,
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Row(
        children: [
          PeerAvatar(
            peerId: peer.peerId,
            displayName: peer.preferredDisplayName,
            avatarService: avatarService,
            size: CompactCardTileStyles.avatarSize,
          ),
          const SizedBox(width: CompactCardTileStyles.horizontalGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  peer.preferredDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: CompactCardTileStyles.textGap),
                Text(
                  peer.peerId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.muted),
                ),
              ],
            ),
          ),
          if (role != null) ...[
            const SizedBox(width: CompactCardTileStyles.horizontalGap),
            Text(
              role!,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
    final onDelete = onDeleteRequested;
    if (onDelete != null) {
      return SwipeDeleteTile(
        borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
        foreground: foreground,
        onDeleteRequested: onDelete,
        onTap: onTap == null ? null : () => onTap!(),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
        onTap: onTap == null ? null : () => onTap!(),
        child: foreground,
      ),
    );
  }
}
