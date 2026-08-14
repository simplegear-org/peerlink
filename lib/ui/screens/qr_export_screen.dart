// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import 'qr_export_screen_view.dart';

class QrExportScreen extends StatelessWidget {
  final String data;

  const QrExportScreen(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.sharePeer)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: QrExportCard(data: data),
        ),
      ),
    );
  }
}
