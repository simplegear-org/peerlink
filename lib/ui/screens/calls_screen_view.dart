import 'package:flutter/material.dart';

import '../../core/calls/call_log_entry.dart';
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
    return Center(
      child: Padding(
        padding: CallsScreenStyles.emptyOuterPadding,
        child: Container(
          padding: CallsScreenStyles.emptyInnerPadding,
          decoration: BoxDecoration(
            color: AppTheme.paper,
            borderRadius: BorderRadius.circular(CallsScreenStyles.emptyCardRadius),
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
                  borderRadius: BorderRadius.circular(CallsScreenStyles.emptyIconRadius),
                ),
                child: const Icon(Icons.call_rounded, size: CallsScreenStyles.iconSize),
              ),
              const SizedBox(height: 18),
              Text(
                'История звонков пуста',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь появятся завершенные, пропущенные и отклоненные вызовы.',
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
      backgroundBuilder: (onDeleteTap) => Card(
        color: Colors.red.shade500,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CallsScreenStyles.tileRadius),
        ),
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: 92,
            child: IconButton(
              onPressed: onDeleteTap,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
              ),
              tooltip: 'Удалить',
            ),
          ),
        ),
      ),
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
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: data.statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(
                  CallsScreenStyles.statusIconRadius,
                ),
              ),
              child: Icon(data.icon, color: data.statusColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.contactName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (data.missedCount > 1) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: CallsScreenStyles.missedPillPadding,
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(
                          CallsScreenStyles.roundPillRadius,
                        ),
                      ),
                      child: Text(
                        '${data.missedCount} пропущенных',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.orange.shade900,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    data.subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                InkResponse(
                  onTap: data.isCalling ? null : onCallTap,
                  radius: 22,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: data.isCalling
                          ? CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: AppTheme.pine,
                            )
                          : Icon(
                              Icons.call_rounded,
                              size: 18,
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
                const SizedBox(height: 4),
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
