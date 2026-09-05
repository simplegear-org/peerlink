// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/services.dart';

class AndroidCallNotificationService {
  const AndroidCallNotificationService();

  static const MethodChannel _channel = MethodChannel(
    'peerlink/android_call_notifications/methods',
  );

  Future<void> cancelAllCallNotifications() async {
    try {
      await _channel.invokeMethod<void>('cancelAllCallNotifications');
    } on MissingPluginException {
      // Non-Android platforms do not expose this bridge.
    }
  }
}
