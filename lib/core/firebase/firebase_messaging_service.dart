import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../notification/notification_service.dart';
import '../runtime/storage_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized in the background isolate.
  }

  final notification = message.notification;
  final data = message.data;
  final fromPeerId = data['fromPeerId'] ?? data['peerId'] ?? 'unknown';
  final body = notification?.body ?? data['message'] ?? data['text'];

  if (body is String && body.isNotEmpty) {
    await NotificationService.instance.showMessageNotification(
      fromPeerId: fromPeerId.toString(),
      message: body,
    );
  }
}

class FirebaseMessagingService {
  FirebaseMessagingService({
    FirebaseMessaging? messaging,
    StorageService? storage,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _storage = storage ?? StorageService();

  static const _fcmTokenKey = 'fcm_token';

  final FirebaseMessaging _messaging;
  final StorageService _storage;
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;

  Stream<String> get tokenStream => _tokenController.stream;

  String? get cachedToken =>
      _storage.getSettings().get(_fcmTokenKey) as String?;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    FirebaseMessaging.onBackgroundMessage(
      firebaseMessagingBackgroundHandler,
    );

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    developer.log(
      '[fcm] permission=${settings.authorizationStatus.name}',
      name: 'FirebaseMessagingService',
    );

    await _waitForApnsTokenIfNeeded();

    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _persistToken(token);
      }
    } catch (error) {
      developer.log(
        '[fcm] getToken failed error=$error',
        name: 'FirebaseMessagingService',
      );
    }

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _handleForegroundMessage,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleOpenedMessage,
    );
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) async {
        await _persistToken(token);
      },
    );

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      await _handleOpenedMessage(initialMessage);
    }

    _initialized = true;
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
    await _tokenController.close();
  }

  Future<void> _persistToken(String token) async {
    await _storage.getSettings().put(_fcmTokenKey, token);
    _tokenController.add(token);
    developer.log(
      '[fcm] token updated',
      name: 'FirebaseMessagingService',
    );
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    developer.log(
      '[fcm] foreground message id=${message.messageId}',
      name: 'FirebaseMessagingService',
    );

    final notification = message.notification;
    final data = message.data;
    final fromPeerId = data['fromPeerId'] ?? data['peerId'] ?? 'unknown';
    final body = notification?.body ?? data['message'] ?? data['text'];

    if (body is String && body.isNotEmpty) {
      await NotificationService.instance.showMessageNotification(
        fromPeerId: fromPeerId.toString(),
        message: body,
      );
    }
  }

  Future<void> _handleOpenedMessage(RemoteMessage message) async {
    developer.log(
      '[fcm] opened message id=${message.messageId}',
      name: 'FirebaseMessagingService',
    );
  }

  Future<void> _waitForApnsTokenIfNeeded() async {
    if (kIsWeb) {
      return;
    }

    if (!Platform.isIOS && !Platform.isMacOS) {
      return;
    }

    for (var attempt = 0; attempt < 10; attempt += 1) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        developer.log(
          '[fcm] apns token ready',
          name: 'FirebaseMessagingService',
        );
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    developer.log(
      '[fcm] apns token not ready',
      name: 'FirebaseMessagingService',
    );
  }
}
