import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'qr_scan_screen_styles.dart';

class QrScanHintCard extends StatelessWidget {
  const QrScanHintCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: QrScanScreenStyles.hintPadding,
      decoration: BoxDecoration(
        color: AppTheme.surfaceRaised.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(QrScanScreenStyles.hintRadius),
        border: Border.all(color: AppTheme.stroke.withValues(alpha: 0.9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.strings.scanQrHintTitle,
            style: theme.textTheme.titleLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            context.strings.scanQrHintSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
