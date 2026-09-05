// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:peerlink/core/calls/call_log_entry.dart';

class AndroidCallLogService {
  static const MethodChannel _channel = MethodChannel(
    'peerlink/android_call_log/methods',
  );

  const AndroidCallLogService();

  Future<bool> record(CallLogEntry entry) async {
    if (!Platform.isAndroid) {
      return false;
    }
    try {
      return await _channel.invokeMethod<bool>('recordCall', <String, Object?>{
            'peerId': entry.peerId,
            'contactName': entry.contactName,
            'direction': entry.direction.name,
            'status': entry.status.name,
            'startedAtMs': entry.startedAt.millisecondsSinceEpoch,
            'durationSeconds': entry.durationSeconds,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
