// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class ContactNameResolver {
  static String resolveFromEntry(
    Object? raw, {
    required String peerId,
    String? fallback,
  }) {
    if (raw is Map) {
      final name = raw['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return fallback ?? peerId;
  }

  static String resolveFromMap(
    Map<String, dynamic>? contacts, {
    required String peerId,
    String? fallback,
  }) {
    return resolveFromEntry(
      contacts?[peerId],
      peerId: peerId,
      fallback: fallback,
    );
  }
}
