// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/notification/app_badge_service.dart';
import 'package:peerlink/features/calls/platform/android_call_notification_service.dart';
import 'package:peerlink/ui/state/calls_controller.dart';

class AppBadgeCoordinator {
  AppBadgeCoordinator({
    required AppBadgeService appBadgeService,
    required CallsController callsController,
    AndroidCallNotificationService androidCallNotifications =
        const AndroidCallNotificationService(),
    int Function()? unreadMessagesCount,
    void Function(int count)? onMissedCallsBadgeCountChanged,
  }) : _appBadgeService = appBadgeService,
       _callsController = callsController,
       _androidCallNotifications = androidCallNotifications,
       _unreadMessagesCount = unreadMessagesCount,
       _onMissedCallsBadgeCountChanged = onMissedCallsBadgeCountChanged;

  final AppBadgeService _appBadgeService;
  final CallsController _callsController;
  final AndroidCallNotificationService _androidCallNotifications;
  int Function()? _unreadMessagesCount;
  void Function(int count)? _onMissedCallsBadgeCountChanged;
  int _missedCallsCount = 0;

  int get missedCallsCount => _missedCallsCount;

  set unreadMessagesCount(int Function() callback) {
    _unreadMessagesCount = callback;
  }

  set onMissedCallsBadgeCountChanged(void Function(int count) callback) {
    _onMissedCallsBadgeCountChanged = callback;
  }

  Future<void> refreshMissedCallsBadge({required bool markSeen}) async {
    if (markSeen) {
      await _callsController.markMissedCallsSeenNow();
      await _androidCallNotifications.cancelAllCallNotifications();
    }
    final count = await _callsController.loadMissedCallsBadgeCount();
    _missedCallsCount = count;
    _onMissedCallsBadgeCountChanged?.call(count);
    syncAppIconBadge(missedCallsOverride: count);
  }

  void syncAppIconBadge({
    int? missedCallsOverride,
    int? unreadMessagesOverride,
  }) {
    final unreadMessages =
        unreadMessagesOverride ?? _unreadMessagesCount?.call() ?? 0;
    unawaited(
      _appBadgeService.syncFromUi(
        unreadMessages: unreadMessages,
        missedCalls: missedCallsOverride ?? _missedCallsCount,
      ),
    );
  }
}
