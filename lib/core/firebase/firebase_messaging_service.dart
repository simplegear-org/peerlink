import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../runtime/account_membership_update_payload.dart';
import '../runtime/app_file_logger.dart';
import '../runtime/push_token_service.dart';
import '../runtime/storage_service.dart';
import 'firebase_push_callback_registry.dart';
import 'firebase_push_inbound_service.dart';
import 'firebase_push_models.dart';
import 'firebase_push_token_lifecycle.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase may already be initialized in the background isolate.
  }
  final inbound = FirebasePushInboundService();
  await inbound.handleBackgroundMessage(message);
}

class FirebaseMessagingService {
  FirebaseMessagingService({
    FirebaseMessaging? messaging,
    StorageService? storage,
  }) : _messaging = messaging ?? FirebaseMessaging.instance,
       _tokenLifecycle = FirebasePushTokenLifecycle(
         messaging: messaging ?? FirebaseMessaging.instance,
         pushTokens: PushTokenService(storage: storage ?? StorageService()),
       ),
       _inbound = FirebasePushInboundService() {
    _activeInstance = this;
  }

  static FirebaseMessagingService? _activeInstance;

  static Future<void> Function(PushServerUpdate update)?
  get onServersFromPush => FirebasePushCallbackRegistry.onServersFromPush;
  static set onServersFromPush(
    Future<void> Function(PushServerUpdate update)? callback,
  ) => FirebasePushCallbackRegistry.onServersFromPush = callback;

  static Future<void> Function(AccountMembershipUpdatePayload payload)?
  get onAccountMembershipUpdateFromPush =>
      FirebasePushCallbackRegistry.onAccountMembershipUpdateFromPush;
  static set onAccountMembershipUpdateFromPush(
    Future<void> Function(AccountMembershipUpdatePayload payload)? callback,
  ) =>
      FirebasePushCallbackRegistry.onAccountMembershipUpdateFromPush = callback;

  static Future<void> Function(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  })?
  get onGroupMembersUpdateFromPush =>
      FirebasePushCallbackRegistry.onGroupMembersUpdateFromPush;
  static set onGroupMembersUpdateFromPush(
    Future<void> Function(Map<String, dynamic> payload, {String? sourcePeerId})?
    callback,
  ) => FirebasePushCallbackRegistry.onGroupMembersUpdateFromPush = callback;

  static Future<void> Function(
    Map<String, dynamic> data, {
    required String source,
  })?
  get onPushOpened => FirebasePushCallbackRegistry.onPushOpened;
  static set onPushOpened(
    Future<void> Function(Map<String, dynamic> data, {required String source})?
    callback,
  ) => FirebasePushCallbackRegistry.onPushOpened = callback;

  final FirebaseMessaging _messaging;
  final FirebasePushTokenLifecycle _tokenLifecycle;
  final FirebasePushInboundService _inbound;

  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _initialized = false;

  Stream<String> get tokenStream => _tokenLifecycle.tokenStream;

  String? get cachedToken => _tokenLifecycle.cachedToken;

  Future<void> initialize() async {
    if (_initialized) {
      _log('initialize skip reason=already_initialized');
      return;
    }
    _log('initialize start');

    await _inbound.configureForegroundPresentation(_messaging);
    await _tokenLifecycle.initialize();

    _foregroundSubscription = FirebaseMessaging.onMessage.listen(
      _inbound.handleForegroundMessage,
    );
    _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _inbound.handleOpenedMessage,
    );

    await _inbound.handleInitialOpen(_messaging);

    _initialized = true;
    _log('initialize done');
  }

  Future<void> dispose() async {
    await _foregroundSubscription?.cancel();
    await _openedSubscription?.cancel();
    await _tokenLifecycle.dispose();
    if (identical(_activeInstance, this)) {
      _activeInstance = null;
    }
  }

  static Future<void> consumePendingOpenedPushIfAny() async {
    final active = _activeInstance;
    if (active != null) {
      await active._inbound.handlePendingIosPushFallback();
    }
    await FirebasePushCallbackRegistry.consumePendingOpenedPushIfAny();
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
