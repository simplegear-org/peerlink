// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class MessageCache {
  final Map<String, int> _cache = {};

  bool contains(String id) {
    return _cache.containsKey(id);
  }

  void store(String id) {
    _cache[id] = DateTime.now().millisecondsSinceEpoch;

    if (_cache.length > 5000) {
      _cleanup();
    }
  }

  void _cleanup() {
    final now = DateTime.now().millisecondsSinceEpoch;

    _cache.removeWhere((key, value) => now - value > 60000);
  }
}
