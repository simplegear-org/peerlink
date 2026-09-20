// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/notifications/domain/notification_mute_state.dart';

/// Application contract for durable, local notification mute preferences.
abstract interface class NotificationMutePreferences {
  NotificationMuteState get state;

  bool isMuted({required NotificationMuteChannel channel, required String id});

  Future<void> setMuted({
    required NotificationMuteChannel channel,
    required String id,
    required bool muted,
  });
}
