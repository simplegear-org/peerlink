// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import 'package:peerlink/features/notifications/application/notification_mute_preferences.dart';
import 'package:peerlink/features/notifications/domain/notification_mute_state.dart';

import '../localization/app_strings.dart';

class NotificationMuteActions extends StatefulWidget {
  const NotificationMuteActions({
    super.key,
    required this.targetId,
    required this.messageChannel,
    required this.callChannel,
    required this.preferences,
  });

  final String targetId;
  final NotificationMuteChannel messageChannel;
  final NotificationMuteChannel callChannel;
  final NotificationMutePreferences preferences;

  @override
  State<NotificationMuteActions> createState() =>
      _NotificationMuteActionsState();
}

class _NotificationMuteActionsState extends State<NotificationMuteActions> {
  NotificationMuteChannel? _savingChannel;

  Future<void> _setMuted(NotificationMuteChannel channel, bool muted) async {
    if (_savingChannel != null) return;
    setState(() => _savingChannel = channel);
    try {
      await widget.preferences.setMuted(
        channel: channel,
        id: widget.targetId,
        muted: muted,
      );
    } finally {
      if (mounted) {
        setState(() => _savingChannel = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MuteActionTile(
          icon: Icons.chat_bubble_outline_rounded,
          title: context.strings.messageNotifications,
          enabled: !widget.preferences.isMuted(
            channel: widget.messageChannel,
            id: widget.targetId,
          ),
          saving: _savingChannel == widget.messageChannel,
          onChanged: (enabled) => _setMuted(widget.messageChannel, !enabled),
        ),
        _MuteActionTile(
          icon: Icons.call_outlined,
          title: context.strings.callNotifications,
          enabled: !widget.preferences.isMuted(
            channel: widget.callChannel,
            id: widget.targetId,
          ),
          saving: _savingChannel == widget.callChannel,
          onChanged: (enabled) => _setMuted(widget.callChannel, !enabled),
        ),
      ],
    );
  }
}

class _MuteActionTile extends StatelessWidget {
  const _MuteActionTile({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.saving,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool enabled;
  final bool saving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final status = enabled
        ? context.strings.notificationsOn
        : context.strings.notificationsMuted;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(status),
      trailing: saving
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(value: enabled, onChanged: onChanged),
      onTap: saving ? null : () => onChanged(!enabled),
    );
  }
}
