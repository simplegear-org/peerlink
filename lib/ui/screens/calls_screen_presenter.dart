// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../../core/calls/call_log_entry.dart';
import '../models/contact.dart';

class CallsScreenPresenter {
  const CallsScreenPresenter();

  String displayNameFor(CallLogEntry entry, Iterable<Contact> contacts) {
    final peerId = entry.peerId.trim();
    if (peerId.isEmpty) {
      final storedName = entry.contactName.trim();
      return storedName.isNotEmpty ? storedName : entry.contactName;
    }

    for (final contact in contacts) {
      if (contact.peerId.trim() != peerId) {
        continue;
      }
      final name = contact.name.trim();
      if (name.isNotEmpty) {
        return name;
      }
      break;
    }

    return shortPeerId(peerId);
  }

  String shortPeerId(String peerId) {
    final normalized = peerId.trim();
    if (normalized.length <= 8) {
      return normalized;
    }
    return '${normalized.substring(0, 4)}...${normalized.substring(normalized.length - 4)}';
  }
}
