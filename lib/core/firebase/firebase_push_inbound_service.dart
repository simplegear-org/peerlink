// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:firebase_messaging/firebase_messaging.dart';

import '../notification/app_badge_service.dart';
import '../runtime/moderation_policy_service.dart';
import '../runtime/storage_service.dart';
import 'firebase_push_payload_processor.dart';
import 'firebase_push_presentation_handler.dart';

class FirebasePushInboundService {
  FirebasePushInboundService({
    FirebasePushPayloadProcessor? payloadProcessor,
    required StorageService storage,
  }) {
    final processor =
        payloadProcessor ??
        FirebasePushPayloadProcessor(
          storage: storage,
          moderationPolicyService: ModerationPolicyService.forStorage(storage),
        );
    _payloadProcessor = processor;
    _presentationHandler = FirebasePushPresentationHandler(
      payloadProcessor: processor,
      storage: storage,
    );
    _appBadgeService = AppBadgeService(storage: storage);
  }

  late final FirebasePushPayloadProcessor _payloadProcessor;
  late final FirebasePushPresentationHandler _presentationHandler;
  late final AppBadgeService _appBadgeService;

  Future<void> configureForegroundPresentation(FirebaseMessaging messaging) {
    return _presentationHandler.configureForegroundPresentation(messaging);
  }

  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    _payloadProcessor.logIncomingPush(message, source: 'background');
    final moderation = await _payloadProcessor.applyModerationGate(
      message.data,
      source: 'background',
    );
    if (moderation.shouldDropBecauseBanned) {
      return;
    }
    await _payloadProcessor.applyAccountMembershipUpdateFromPush(
      message.data,
      source: 'background',
    );
    await _payloadProcessor.applyGroupMembersUpdateFromPush(
      message.data,
      source: 'background',
    );
    await _presentationHandler.showNotificationFromPush(
      message,
      moderationPolicyAlreadyApplied: moderation.isModerationPolicy,
    );
    await _appBadgeService.applyBackgroundPushHint(message.data);
  }

  Future<void> handleForegroundMessage(RemoteMessage message) {
    return _presentationHandler.handleForegroundMessage(message);
  }

  Future<void> handleOpenedMessage(RemoteMessage message) {
    return _presentationHandler.handleOpenedMessage(message);
  }

  Future<void> handleInitialOpen(FirebaseMessaging messaging) {
    return _presentationHandler.handleInitialOpen(messaging);
  }

  Future<void> handlePendingIosPushFallback() {
    return _presentationHandler.handlePendingIosPushFallback();
  }
}
