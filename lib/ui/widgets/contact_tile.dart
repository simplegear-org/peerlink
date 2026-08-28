// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';
import 'compact_card_tile_styles.dart';
import 'swipe_delete_tile.dart';

class ContactTile extends StatelessWidget {
  final Contact contact;
  final Future<bool> Function() onDeleteRequested;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? avatar;
  final Widget status;
  final Widget? trailing;

  const ContactTile({
    super.key,
    required this.contact,
    required this.onDeleteRequested,
    required this.onTap,
    required this.status,
    this.onLongPress,
    this.avatar,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = contact.name.trim().isNotEmpty
        ? contact.name.trim()
        : contact.shortId();

    return SwipeDeleteTile(
      borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
      onDeleteRequested: onDeleteRequested,
      onTap: onTap,
      onLongPress: onLongPress,
      foreground: Container(
        padding: CompactCardTileStyles.tilePadding,
        decoration: BoxDecoration(
          color: AppTheme.paper,
          borderRadius: BorderRadius.circular(CompactCardTileStyles.tileRadius),
          border: Border.all(color: AppTheme.stroke),
        ),
        child: Row(
          children: [
            SizedBox(
              width: CompactCardTileStyles.avatarSize,
              height: CompactCardTileStyles.avatarSize,
              child:
                  avatar ??
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.pineSoft,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.isEmpty ? '?' : displayName[0].toUpperCase(),
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppTheme.pine,
                      ),
                    ),
                  ),
            ),
            const SizedBox(width: CompactCardTileStyles.horizontalGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: CompactCardTileStyles.textGap),
                  status,
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ],
        ),
      ),
    );
  }
}
