// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/profile/application/peer_profile_store.dart';
import 'package:peerlink/features/profile/domain/peer_profile.dart';

class SettingsPeerProfileStore implements PeerProfileStore {
  static const String _storageKey = 'peerlink.remote_profiles.v1';

  SettingsPeerProfileStore({required StorageService storage})
    : _settings = storage.getSettings();

  final SecureStorageBox _settings;

  @override
  PeerProfile? profileForPeer(String peerId) {
    final normalized = peerId.trim();
    final raw = _settings.get(_storageKey);
    if (normalized.isEmpty || raw is! Map || raw[normalized] is! Map) {
      return null;
    }
    try {
      return PeerProfile.fromJson(
        normalized,
        Map<String, dynamic>.from(raw[normalized] as Map),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(PeerProfile profile) async {
    final profiles = <String, dynamic>{};
    final raw = _settings.get(_storageKey);
    if (raw is Map) {
      for (final entry in raw.entries) {
        final peerId = '${entry.key}'.trim();
        if (peerId.isNotEmpty && entry.value is Map) {
          profiles[peerId] = Map<String, dynamic>.from(entry.value as Map);
        }
      }
    }
    profiles[profile.peerId] = profile.toJson();
    await _settings.put(_storageKey, profiles);
  }
}
