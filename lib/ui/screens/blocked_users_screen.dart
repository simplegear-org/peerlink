// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../state/settings_controller.dart';
import '../theme/app_theme.dart';

class BlockedUsersScreen extends StatefulWidget {
  final SettingsController controller;

  const BlockedUsersScreen({super.key, required this.controller});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final blockedPeers = widget.controller.blockedPeers;
    return Scaffold(
      appBar: AppBar(title: Text(strings.blockedUsers)),
      body: blockedPeers.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.blockedUsersEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: blockedPeers.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final peer = blockedPeers[index];
                final displayName = widget.controller.blockedPeerDisplayName(
                  peer.peerId,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.block_rounded,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(displayName),
                  subtitle: Text(_shortPeerId(peer.peerId)),
                  trailing: TextButton(
                    onPressed: () async {
                      await widget.controller.unblockPeer(peer.peerId);
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    child: Text(strings.unblockUser),
                  ),
                );
              },
            ),
    );
  }

  String _shortPeerId(String peerId) {
    if (peerId.length <= 18) {
      return peerId;
    }
    return '${peerId.substring(0, 8)}...${peerId.substring(peerId.length - 6)}';
  }
}
