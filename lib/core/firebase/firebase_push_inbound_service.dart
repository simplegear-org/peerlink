import 'package:firebase_messaging/firebase_messaging.dart';

import '../notification/app_badge_service.dart';
import 'firebase_push_payload_processor.dart';
import 'firebase_push_presentation_handler.dart';

class FirebasePushInboundService {
  FirebasePushInboundService({
    FirebasePushPayloadProcessor payloadProcessor =
        const FirebasePushPayloadProcessor(),
  }) : _payloadProcessor = payloadProcessor,
       _presentationHandler = FirebasePushPresentationHandler(
         payloadProcessor: payloadProcessor,
       );

  final FirebasePushPayloadProcessor _payloadProcessor;
  final FirebasePushPresentationHandler _presentationHandler;
  final AppBadgeService _appBadgeService = AppBadgeService();

  Future<void> configureForegroundPresentation(FirebaseMessaging messaging) {
    return _presentationHandler.configureForegroundPresentation(messaging);
  }

  Future<void> handleBackgroundMessage(RemoteMessage message) async {
    _payloadProcessor.logIncomingPush(message, source: 'background');
    await _payloadProcessor.applyAccountMembershipUpdateFromPush(
      message.data,
      source: 'background',
    );
    await _payloadProcessor.applyGroupMembersUpdateFromPush(
      message.data,
      source: 'background',
    );
    await _presentationHandler.showNotificationFromPush(message);
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
