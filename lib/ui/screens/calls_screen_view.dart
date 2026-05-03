import 'package:flutter/material.dart';

import '../../core/calls/call_log_entry.dart';
import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import '../widgets/swipe_delete_tile.dart';
import 'calls_screen_styles.dart';

class CallHistoryTileData {
  final CallLogEntry entry;
  final IconData icon;
  final Color statusColor;
  final bool isCalling;
  final int missedCount;
  final String subtitle;
  final String timeLabel;
  final String durationLabel;

  const CallHistoryTileData({
    required this.entry,
    required this.icon,
    required this.statusColor,
    required this.isCalling,
    required this.missedCount,
    required this.subtitle,
    required this.timeLabel,
    required this.durationLabel,
  });
}

class CallsEmptyState extends StatelessWidget {
  const CallsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = context.strings;
    return Center(
      child: Padding(
        padding: CallsScreenStyles.emptyOuterPadding,
        child: Container(
          padding: CallsScreenStyles.emptyInnerPadding,
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(
              CallsScreenStyles.emptyCardRadius,
            ),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: CallsScreenStyles.iconBoxSize,
                height: CallsScreenStyles.iconBoxSize,
                decoration: BoxDecoration(
                  color: AppTheme.pineSoft,
                  borderRadius: BorderRadius.circular(
                    CallsScreenStyles.emptyIconRadius,
                  ),
                ),
                child: const Icon(
                  Icons.call_rounded,
                  size: CallsScreenStyles.iconSize,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                strings.callHistoryEmptyTitle,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                strings.callHistoryEmptySubtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CallHistoryTile extends StatelessWidget {
  final CallHistoryTileData data;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onCallTap;
  final Future<bool> Function() onDeleteRequested;

  const CallHistoryTile({
    super.key,
    required this.data,
    required this.onTap,
    required this.onLongPress,
    required this.onCallTap,
    required this.onDeleteRequested,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = data.entry;
    return SwipeDeleteTile(
      onDeleteRequested: onDeleteRequested,
      onTap: data.isCalling ? null : onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(CallsScreenStyles.tileRadius),
      foreground: Container(
        padding: CallsScreenStyles.tilePadding,
        decoration: BoxDecoration(
          color: AppTheme.paper,
          borderRadius: BorderRadius.circular(CallsScreenStyles.tileRadius),
          border: Border.all(color: AppTheme.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: CallsScreenStyles.statusIconBoxSize,
              height: CallsScreenStyles.statusIconBoxSize,
              decoration: BoxDecoration(
                color: data.statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(
                  CallsScreenStyles.statusIconRadius,
                ),
              ),
              child: Icon(
                data.icon,
                color: data.statusColor,
                size: CallsScreenStyles.statusIconSize,
              ),
            ),
            const SizedBox(width: CallsScreenStyles.tileHorizontalGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    entry.contactName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (data.missedCount > 1) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: CallsScreenStyles.missedPillPadding,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          CallsScreenStyles.roundPillRadius,
                        ),
                      ),
                      child: Text(
                        context.strings.missedCalls(data.missedCount),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: CallsScreenStyles.textGap),
                  Text(
                    data.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: CallsScreenStyles.tileHorizontalGap),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkResponse(
                  onTap: data.isCalling ? null : onCallTap,
                  radius: 22,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      width: CallsScreenStyles.callActionSize,
                      height: CallsScreenStyles.callActionSize,
                      child: data.isCalling
                          ? CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppTheme.pine,
                            )
                          : Icon(
                              Icons.call_rounded,
                              size: CallsScreenStyles.callActionSize,
                              color: AppTheme.pine,
                            ),
                    ),
                  ),
                ),
                Text(
                  data.timeLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppTheme.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: CallsScreenStyles.textGap),
                Text(
                  data.durationLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
