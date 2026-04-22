import 'package:flutter/material.dart';

import 'qr_export_screen_view.dart';

class QrExportScreen extends StatelessWidget {
  final String data;

  const QrExportScreen(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Поделиться peer')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: QrExportCard(data: data),
        ),
      ),
    );
  }
}
