// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'storage_service.dart';

class PushTokenService {
  static const _fcmTokenKey = 'fcm_token';
  static const _apnsTokenKey = 'apns_token';
  static const _voipTokenKey = 'voip_token';

  final StorageService _storage;

  PushTokenService({StorageService? storage})
    : _storage = storage ?? StorageService();

  Future<void> saveFcmToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _storage.getSettings().put(_fcmTokenKey, normalized);
  }

  Future<void> saveApnsToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _storage.getSettings().put(_apnsTokenKey, normalized);
  }

  Future<void> saveVoipToken(String token) async {
    final normalized = token.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _storage.getSettings().put(_voipTokenKey, normalized);
  }

  String? get fcmToken => _storage.getSettings().get(_fcmTokenKey) as String?;
  String? get apnsToken => _storage.getSettings().get(_apnsTokenKey) as String?;
  String? get voipToken => _storage.getSettings().get(_voipTokenKey) as String?;
}

