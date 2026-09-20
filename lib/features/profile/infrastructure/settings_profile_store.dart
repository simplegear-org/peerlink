// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/profile/application/profile_store.dart';
import 'package:peerlink/features/profile/domain/profile.dart';

/// Settings-backed persistence adapter for local Profile metadata.
class SettingsProfileStore implements ProfileStore {
  static const String profileKey = 'peerlink.profile.v1';
  static const String legacyInviteUsernameKey =
      'peerlink.profile.invite_username.v1';

  final SecureStorageBox _settings;
  late Profile _profile;
  late final Future<void> migration;

  SettingsProfileStore({required StorageService storage})
    : _settings = storage.getSettings() {
    _profile = _readProfile();
    migration = _migrateLegacyDisplayName();
    unawaited(migration);
  }

  @override
  Profile get profile => _profile;

  @override
  Future<void> save(Profile profile) async {
    _profile = Profile(
      displayName: Profile.normalizeDisplayName(profile.displayName),
      about: Profile.normalizeAbout(profile.about),
    );
    await _settings.put(profileKey, _profile.toJson());
    await _settings.delete(legacyInviteUsernameKey);
  }

  Profile _readProfile() {
    final raw = _settings.get(profileKey);
    if (raw is Map) {
      try {
        return Profile.fromJson(Map<String, dynamic>.from(raw));
      } on FormatException {
        return const Profile();
      }
    }
    try {
      return Profile(
        displayName: Profile.normalizeDisplayName(
          _settings.get(legacyInviteUsernameKey),
        ),
      );
    } on FormatException {
      return const Profile();
    }
  }

  Future<void> _migrateLegacyDisplayName() async {
    if (_settings.get(profileKey) is Map ||
        _settings.get(legacyInviteUsernameKey) == null) {
      return;
    }
    await _settings.put(profileKey, _profile.toJson());
    await _settings.delete(legacyInviteUsernameKey);
  }
}
