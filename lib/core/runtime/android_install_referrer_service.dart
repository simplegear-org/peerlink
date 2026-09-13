// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/services.dart';

/// Reads only a validated deferred-invite token from Google Play on Android.
class AndroidInstallReferrerService {
  static const instance = AndroidInstallReferrerService._();

  static const MethodChannel _channel = MethodChannel(
    'peerlink/deep_links/methods',
  );

  const AndroidInstallReferrerService._();

  Future<String?> readInviteToken() async {
    try {
      final token = await _channel.invokeMethod<String>(
        'getInstallReferrerInviteToken',
      );
      if (token == null ||
          !RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(token)) {
        return null;
      }
      return token;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> markInviteTokenHandled(String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(token)) return;
    try {
      await _channel.invokeMethod<void>(
        'markInstallReferrerInviteTokenHandled',
        token,
      );
    } on MissingPluginException {
      // Non-Android platforms have no install-referrer state to acknowledge.
    }
  }
}
