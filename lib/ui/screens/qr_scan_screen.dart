// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../localization/app_strings.dart';
import 'qr_scan_screen_view.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.scanQr)),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) async {
              if (_handled) return;
              final barcodes = capture.barcodes;
              final String? code = barcodes.isNotEmpty
                  ? barcodes.first.rawValue
                  : null;

              if (code != null) {
                _handled = true;
                unawaited(_controller.stop());
                if (!mounted) return;
                Navigator.of(context).pop(code);
              }
            },
          ),
          Positioned(
            left: 20,
            right: 20,
            top: 20,
            child: const QrScanHintCard(),
          ),
        ],
      ),
    );
  }
}
