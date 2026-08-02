import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../runtime/app_file_logger.dart';
import '../runtime/push_token_service.dart';

class FirebasePushTokenLifecycle {
  FirebasePushTokenLifecycle({
    required FirebaseMessaging messaging,
    required PushTokenService pushTokens,
  }) : _messaging = messaging,
       _pushTokens = pushTokens;

  final FirebaseMessaging _messaging;
  final PushTokenService _pushTokens;
  final StreamController<String> _tokenController =
      StreamController<String>.broadcast();

  StreamSubscription<String>? _tokenRefreshSubscription;

  Stream<String> get tokenStream => _tokenController.stream;

  String? get cachedToken => _pushTokens.fcmToken;

  Future<void> initialize() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    _log(
      'permission authorization=${settings.authorizationStatus.name} '
      'alert=${settings.alert} badge=${settings.badge} sound=${settings.sound}',
    );

    developer.log(
      '[fcm] permission=${settings.authorizationStatus.name}',
      name: 'FirebaseMessagingService',
    );

    await _waitForApnsTokenIfNeeded();
    await _persistInitialFcmToken();

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) async {
        _log('onTokenRefresh tokenLength=${token.length}');
        await _persistToken(token);
      },
      onError: (Object error, StackTrace stackTrace) {
        _log(
          'onTokenRefresh stream error=$error',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _tokenController.close();
  }

  Future<void> _persistInitialFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await _persistToken(token);
      } else {
        _log('getToken returned empty');
      }
    } catch (error, stackTrace) {
      developer.log(
        '[fcm] getToken failed error=$error',
        name: 'FirebaseMessagingService',
      );
      _log(
        'getToken failed error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _waitForApnsTokenIfNeeded() async {
    if (kIsWeb) {
      return;
    }

    if (!Platform.isIOS && !Platform.isMacOS) {
      return;
    }

    for (var attempt = 0; attempt < 20; attempt += 1) {
      final apnsToken = await _messaging.getAPNSToken();
      if (apnsToken != null && apnsToken.isNotEmpty) {
        await _persistApnsToken(apnsToken);
        _log('apns token ready attempt=${attempt + 1}');
        developer.log(
          '[fcm] apns token ready',
          name: 'FirebaseMessagingService',
        );
        return;
      }
      _log('apns token not ready attempt=${attempt + 1}');
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    developer.log(
      '[fcm] apns token not ready',
      name: 'FirebaseMessagingService',
    );
    _log('apns token final status=not_ready');
  }

  Future<void> _persistToken(String token) async {
    await _pushTokens.saveFcmToken(token);
    _tokenController.add(token);
    _log('token persisted length=${token.length}');
    developer.log('[fcm] token updated', name: 'FirebaseMessagingService');
  }

  Future<void> _persistApnsToken(String token) async {
    await _pushTokens.saveApnsToken(token);
    _log('apns token persisted length=${token.length}');
  }

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    AppFileLogger.log(
      '[fcm] $message',
      name: 'FirebaseMessagingService',
      error: error,
      stackTrace: stackTrace,
    );
    developer.log(
      '[fcm] $message',
      name: 'FirebaseMessagingService',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
