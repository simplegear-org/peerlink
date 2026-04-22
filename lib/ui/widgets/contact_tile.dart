import 'package:flutter/material.dart';
import '../models/contact.dart';
import '../theme/app_theme.dart';
import 'swipe_delete_tile.dart';

class ContactTile extends StatelessWidget {
  final Contact contact;
  final Future<bool> Function() onDeleteRequested;
  final VoidCallback onTap;
  final Widget? statusIcon;
  final Widget? avatar;
  final String lastSeenText;

  const ContactTile({
    super.key,
    required this.contact,
    required this.onDeleteRequested,
    required this.onTap,
    required this.lastSeenText,
    this.avatar,
    this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 122,
      child: SwipeDeleteTile(
        onDeleteRequested: onDeleteRequested,
        onTap: onTap,
        foreground: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                SizedBox(
                  width: 50,
                  height: 50,
                  child: avatar ??
                      Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.pineSoft,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: statusIcon ??
                            Text(
                              contact.name.isEmpty
                                  ? '?'
                                  : contact.name[0].toUpperCase(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AppTheme.pine,
                              ),
                            ),
                      ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.name,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        contact.shortId(),
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lastSeenText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
