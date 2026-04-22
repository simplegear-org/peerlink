import 'package:flutter/material.dart';

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
        color: AppTheme.ink.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(QrScanScreenStyles.hintRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Наведи камеру на QR',
            style: theme.textTheme.titleLarge?.copyWith(
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Код будет считан автоматически и подставлен в контакт.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }
}
