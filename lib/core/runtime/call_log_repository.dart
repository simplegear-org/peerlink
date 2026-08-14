// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../calls/call_log_entry.dart';
import 'storage_service.dart';

class CallLogRepository {
  final StorageService storage;

  CallLogRepository({required this.storage});

  Future<List<CallLogEntry>> readAll() async {
    final raw = await storage.readCallLogs();
    return raw.map(CallLogEntry.fromJson).toList(growable: false);
  }

  Future<void> prepend(CallLogEntry entry) {
    return storage.prependCallLog(entry.toJson());
  }

  Future<void> deleteById(String id) {
    return storage.deleteCallLog(id);
  }
}
