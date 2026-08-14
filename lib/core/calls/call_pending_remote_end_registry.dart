// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class CallPendingRemoteEndRegistry {
  CallPendingRemoteEndRegistry({required Duration ttl}) : _ttl = ttl;

  final Duration _ttl;
  final Map<String, DateTime> _entries = <String, DateTime>{};

  void remember({required String peerId, required String callId}) {
    _prune();
    final key = _buildKey(peerId: peerId, callId: callId);
    if (key == null) {
      return;
    }
    _entries[key] = DateTime.now();
  }

  bool contains({required String peerId, required String callId}) {
    _prune();
    final key = _buildKey(peerId: peerId, callId: callId);
    if (key == null) {
      return false;
    }
    return _entries.containsKey(key);
  }

  String? _buildKey({required String peerId, required String callId}) {
    final normalizedPeerId = peerId.trim();
    final normalizedCallId = callId.trim();
    if (normalizedPeerId.isEmpty || normalizedCallId.isEmpty) {
      return null;
    }
    return '$normalizedPeerId|$normalizedCallId';
  }

  void _prune() {
    if (_entries.isEmpty) {
      return;
    }
    final now = DateTime.now();
    _entries.removeWhere((_, createdAt) => now.difference(createdAt) > _ttl);
  }
}
