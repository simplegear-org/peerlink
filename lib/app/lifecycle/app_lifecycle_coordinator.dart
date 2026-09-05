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

class AppLifecycleCoordinator {
  AppLifecycleCoordinator({
    required AppRestrictionStatusRefresh refreshRestrictionStatus,
    IosCallkitService? iosCallkitService,
  }) : _refreshRestrictionStatus = refreshRestrictionStatus,
       _iosCallkitService = iosCallkitService ?? IosCallkitService.instance;

  final AppRestrictionStatusRefresh _refreshRestrictionStatus;
  final IosCallkitService _iosCallkitService;

  void handleLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(_iosCallkitService.refreshVoipRegistration(reason: 'resume'));
    unawaited(_refreshRestrictionStatus(reason: 'resume'));
    unawaited(FirebaseMessagingService.consumePendingOpenedPushIfAny());
  }
}
