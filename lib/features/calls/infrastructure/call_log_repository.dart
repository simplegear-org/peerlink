// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/calls/call_log_entry.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

class CallLogRepository {
  static const _itemsKey = 'items';
  static const _maxEntries = 200;

  final StorageService storage;

  CallLogRepository({required this.storage});

  Future<List<CallLogEntry>> readAll() async {
    final raw = storage.getCalls().get(_itemsKey);
    if (raw is! List) {
      return <CallLogEntry>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => CallLogEntry.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> prepend(CallLogEntry entry) async {
    final box = storage.getCalls();
    final existingRaw = box.get(_itemsKey);
    final items = existingRaw is List
        ? existingRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: true)
        : <Map<String, dynamic>>[];

    items.removeWhere((item) => item['id'] == entry.id);
    items.insert(0, entry.toJson());
    if (items.length > _maxEntries) {
      items.removeRange(_maxEntries, items.length);
    }

    await box.put(_itemsKey, items);
  }

  Future<void> deleteById(String id) async {
    if (id.trim().isEmpty) {
      return;
    }

    final box = storage.getCalls();
    final existingRaw = box.get(_itemsKey);
    if (existingRaw is! List) {
      return;
    }

    final items = existingRaw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: true);
    items.removeWhere((item) => item['id'] == id);
    await box.put(_itemsKey, items);
  }
}
