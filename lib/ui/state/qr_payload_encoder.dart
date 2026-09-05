// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

/// Helper for encoding QR payloads and building deep links.
class QrPayloadEncoder {
  /// Encode JSON string to base64url without padding.
  static String encodeToBase64Url(String json) {
    final bytes = utf8.encode(json);
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Build a simple deep link with payload query parameter.
  static String buildDeepLink({
    required String scheme,
    required String host,
    required String payload,
  }) {
    return Uri(
      scheme: scheme,
      host: host,
      queryParameters: <String, String>{'payload': payload},
    ).toString();
  }
}
