import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../notification/notification_service.dart';
import '../runtime/app_file_logger.dart';
import 'firebase_push_callback_registry.dart';
import 'firebase_push_payload.dart';
import 'firebase_push_payload_processor.dart';
import 'firebase_push_servers_merge_orchestrator.dart';

class FirebasePushPresentationHandler {
  FirebasePushPresentationHandler({
    required FirebasePushPayloadProcessor payloadProcessor,
  }) : _payloadProcessor = payloadProcessor;

  static const MethodChannel _iosPushPayloadMethodChannel = MethodChannel(
    'peerlink/push_payload/methods',
  );

  final FirebasePushPayloadProcessor _payloadProcessor;
  static const FirebasePushServersMergeOrchestrator _serversMergeOrchestrator =
      FirebasePushServersMergeOrchestrator();

  Future<void> configureForegroundPresentation(
    FirebaseMessaging messaging,
  ) async {
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> handleForegroundMessage(RemoteMessage message) async {
    developer.log(
      '[fcm] foreground message id=${message.messageId}',
      name: 'FirebaseMessagingService',
    );
    _payloadProcessor.logIncomingPush(message, source: 'foreground');
    await showNotificationFromPush(message);
    if (_shouldTriggerPushCallback(message.data)) {
      await _serversMergeOrchestrator.applyIfPresent(
        message.data,
        source: 'foreground',
      );
      await FirebasePushCallbackRegistry.emitPushOpened(
        Map<String, dynamic>.from(message.data),
        source: 'foreground',
      );
    }
  }

  Future<void> handleOpenedMessage(RemoteMessage message) async {
    developer.log(
      '[fcm] opened message id=${message.messageId}',
      name: 'FirebaseMessagingService',
    );
    _payloadProcessor.logIncomingPush(message, source: 'opened');
    await _serversMergeOrchestrator.applyIfPresent(
      message.data,
      source: 'opened',
    );
    await FirebasePushCallbackRegistry.emitPushOpened(
      Map<String, dynamic>.from(message.data),
      source: 'opened',
    );
  }

  Future<void> handleInitialOpen(FirebaseMessaging messaging) async {
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      AppFileLogger.log(
        '[fcm] initialMessage id=${initialMessage.messageId}',
        name: 'FirebaseMessagingService',
      );
      await handleOpenedMessage(initialMessage);
    } else {
      AppFileLogger.log(
        '[fcm] initialMessage none',
        name: 'FirebaseMessagingService',
      );
      await handlePendingIosPushFallback();
    }
  }

  Future<void> handlePendingIosPushFallback() async {
    if (kIsWeb) {
      return;
    }
    if (!Platform.isIOS) {
      return;
    }
    final payload = await _consumePendingIosPushPayload();
    if (payload == null) {
      AppFileLogger.log(
        '[fcm] pending ios push payload none',
        name: 'FirebaseMessagingService',
      );
      return;
    }
    AppFileLogger.log(
      '[fcm] pending ios push payload restored keys=${payload.keys.length}',
      name: 'FirebaseMessagingService',
    );
    final serversRaw = payload['servers'];
    if (serversRaw != null) {
      final encoded = serversRaw.toString();
      final shortened = encoded.length > 1500
          ? '${encoded.substring(0, 1500)}...(truncated)'
          : encoded;
      AppFileLogger.log(
        '[fcm][incoming][native-fallback] servers=$shortened',
        name: 'FirebaseMessagingService',
      );
    }
    final normalized = payload.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    await _serversMergeOrchestrator.applyIfPresent(
      normalized,
      source: 'native-fallback',
    );
    await FirebasePushCallbackRegistry.emitPushOpened(
      normalized,
      source: 'native-fallback',
    );
  }

  Future<void> showNotificationFromPush(RemoteMessage message) async {
    _payloadProcessor.logIncomingPush(message, source: 'display');
    await _serversMergeOrchestrator.applyIfPresent(
      message.data,
      source: 'display',
    );
    final isAccountMembershipUpdate = await _payloadProcessor
        .applyAccountMembershipUpdateFromPush(message.data, source: 'display');
    if (isAccountMembershipUpdate) {
      return;
    }
    final isGroupMembersUpdate = await _payloadProcessor
        .applyGroupMembersUpdateFromPush(message.data, source: 'display');
    if (isGroupMembersUpdate) {
      return;
    }
    final notification = message.notification;
    final data = message.data;
    final payload = FirebasePushPayload.fromMap(data);
    final fromPeerId = payload.senderPeerId.isNotEmpty
        ? payload.senderPeerId
        : 'unknown';

    if (payload.isCallInvite) {
      await NotificationService.instance.showIncomingCallNotification(
        fromPeerId: fromPeerId,
        isVideo: payload.mediaType == 'video',
      );
      return;
    }

    final body = notification?.body ?? payload.notificationText;
    if (body.isNotEmpty) {
      await NotificationService.instance.showMessageNotification(
        fromPeerId: fromPeerId.toString(),
        message: body,
      );
    }
  }

  Future<Map<String, dynamic>?> _consumePendingIosPushPayload() async {
    try {
      final raw = await _iosPushPayloadMethodChannel.invokeMethod<String>(
        'consumeLatestPushPayload',
      );
      if (raw == null || raw.trim().isEmpty) {
        return null;
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } on PlatformException catch (error, stackTrace) {
      AppFileLogger.log(
        '[fcm] pending ios push payload unavailable error=$error',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[fcm] pending ios push payload parse failed error=$error',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  bool _isCallPushPayload(Map<String, dynamic> data) {
    return FirebasePushPayload.fromMap(data).isCallPayload;
  }

  bool _shouldTriggerPushCallback(Map<String, dynamic> data) {
    final payload = FirebasePushPayload.fromMap(data);
    if (_isCallPushPayload(data)) {
      return true;
    }
    if (payload.isMessageLike) {
      return true;
    }
    if (!payload.hasRelayHint) {
      return false;
    }
    if (payload.isGroupMembersUpdate || payload.isAccountMembershipUpdate) {
      return false;
    }
    return true;
  }
}
