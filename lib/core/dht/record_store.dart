// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class RecordStore {
  final Map<String, String> _records = {};

  void put(String key, String value) {
    _records[key] = value;
  }

  String? get(String key) => _records[key];
}