// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:peerlink/core/firebase/firebase_messaging_service.dart';
import 'package:peerlink/features/calls/platform/ios_callkit_service.dart';

typedef AppRestrictionStatusRefresh =
    Future<void> Function({required String reason});
typedef ModerationLifecycleResume = void Function();
typedef PendingInviteResume = Future<void> Function();

class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    required AppRestrictionStatusRefresh refreshRestrictionStatus,
    ModerationLifecycleResume? retryModerationReports,
    PendingInviteResume? retryPendingInvite,
    IosCallkitService? iosCallkitService,
  }) : _refreshRestrictionStatus = refreshRestrictionStatus,
       _retryModerationReports = retryModerationReports,
       _retryPendingInvite = retryPendingInvite,
       _iosCallkitService = iosCallkitService ?? IosCallkitService.instance;

  final AppRestrictionStatusRefresh _refreshRestrictionStatus;
  final ModerationLifecycleResume? _retryModerationReports;
  final PendingInviteResume? _retryPendingInvite;
  final IosCallkitService _iosCallkitService;

  void handleLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_iosCallkitService.refreshVoipRegistration(reason: 'resume'));
    unawaited(_refreshRestrictionStatus(reason: 'resume'));
    _retryModerationReports?.call();
    if (_retryPendingInvite != null) {
      unawaited(_retryPendingInvite());
    }
    unawaited(FirebaseMessagingService.consumePendingOpenedPushIfAny());
  }
}
