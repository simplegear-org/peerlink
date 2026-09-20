// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/profile/application/profile_peer_metadata_store.dart';

class SettingsProfilePeerMetadataStore implements ProfilePeerMetadataStore {
  static const String _usernameUpdatedAtKey =
      'peer_profile_username_updated_at_v1';

  SettingsProfilePeerMetadataStore({required StorageService storage})
    : _settings = storage.getSettings();

  final SecureStorageBox _settings;

  @override
  int usernameUpdatedAtMs(String peerId) {
    final raw = _settings.get(_usernameUpdatedAtKey);
    if (raw is! Map) return 0;
    final value = raw[peerId];
    return value is int ? value : int.tryParse('${value ?? 0}') ?? 0;
  }

  @override
  Future<void> saveUsernameUpdatedAtMs(String peerId, int updatedAtMs) async {
    final raw = _settings.get(_usernameUpdatedAtKey);
    final updates = <String, dynamic>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = '${entry.key}'.trim();
        if (key.isNotEmpty) updates[key] = entry.value;
      }
    }
    updates[peerId] = updatedAtMs;
    await _settings.put(_usernameUpdatedAtKey, updates);
  }
}
