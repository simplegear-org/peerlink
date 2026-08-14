// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../localization/app_strings.dart';
import '../theme/app_theme.dart';
import 'qr_export_screen_styles.dart';

class QrExportCard extends StatelessWidget {
  final String data;

  const QrExportCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: QrExportScreenStyles.cardPadding,
      decoration: BoxDecoration(
        color: AppTheme.paper,
        borderRadius: BorderRadius.circular(QrExportScreenStyles.cardRadius),
        border: Border.all(color: AppTheme.stroke),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: QrExportScreenStyles.qrContainerPadding,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(
                QrExportScreenStyles.qrContainerRadius,
              ),
            ),
            child: QrImageView(data: data, size: QrExportScreenStyles.qrSize),
          ),
          const SizedBox(height: 18),
          Text(context.strings.nodeQrCode, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          SelectableText(
            data,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
