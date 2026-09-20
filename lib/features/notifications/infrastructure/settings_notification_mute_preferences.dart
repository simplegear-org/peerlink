// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/storage_service.dart';
import 'dart:async';
import 'package:peerlink/features/notifications/application/notification_mute_preferences.dart';
import 'package:peerlink/features/notifications/domain/notification_mute_state.dart';

/// Secure-settings adapter for local notification mute preferences.
class SettingsNotificationMutePreferences
    implements NotificationMutePreferences {
  static const storageKey = 'peerlink.notification_mute.v1';

  SettingsNotificationMutePreferences({
    required SecureStorageBox settings,
    Future<void> Function()? onChanged,
  }) : _onChanged = onChanged,
       _settings = settings,
       _state = NotificationMuteState.fromJson(settings.get(storageKey));

  final SecureStorageBox _settings;
  final Future<void> Function()? _onChanged;
  NotificationMuteState _state;

  @override
  NotificationMuteState get state => _state;

  @override
  bool isMuted({required NotificationMuteChannel channel, required String id}) {
    return _state.isMuted(channel: channel, id: id);
  }

  @override
  Future<void> setMuted({
    required NotificationMuteChannel channel,
    required String id,
    required bool muted,
  }) async {
    final previous = _state;
    final next = _state.withMuted(channel: channel, id: id, muted: muted);
    _state = next;
    try {
      await _settings.put(storageKey, next.toJson());
    } catch (_) {
      _state = previous;
      rethrow;
    }
    final onChanged = _onChanged;
    if (onChanged != null) {
      unawaited(onChanged().catchError((_) {}));
    }
  }
}
