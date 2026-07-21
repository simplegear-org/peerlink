import 'dart:convert';

import '../runtime/account_membership_update_payload.dart';
import '../runtime/app_file_logger.dart';
import 'firebase_push_models.dart';

class FirebasePushCallbackRegistry {
  static Future<void> Function(PushServerUpdate update)? onServersFromPush;
  static Future<void> Function(AccountMembershipUpdatePayload payload)?
  onAccountMembershipUpdateFromPush;
  static Future<void> Function(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  })?
  onGroupMembersUpdateFromPush;
  static Future<void> Function(
    Map<String, dynamic> data, {
    required String source,
  })?
  onPushOpened;

  static Map<String, dynamic>? _pendingOpenedPushData;
  static Future<void>? _pendingServersApplyFuture;

  static Future<void> consumePendingOpenedPushIfAny() async {
    final pending = _pendingOpenedPushData;
    if (pending == null) {
      return;
    }
    final callback = onPushOpened;
    if (callback == null) {
      return;
    }
    _pendingOpenedPushData = null;
    try {
      await callback(Map<String, dynamic>.from(pending), source: 'pending');
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[fcm] consume pending opened push failed error=$error',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static Future<void> emitPushOpened(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final callback = onPushOpened;
    if (callback == null) {
      _pendingOpenedPushData = Map<String, dynamic>.from(data);
      return;
    }
    try {
      await callback(Map<String, dynamic>.from(data), source: source);
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[fcm] onPushOpened callback failed error=$error '
        'source=$source payload=${jsonEncode(data)}',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void trackPendingServersApply(Future<void> future) {
    _pendingServersApplyFuture = future;
    future.whenComplete(() {
      if (identical(_pendingServersApplyFuture, future)) {
        _pendingServersApplyFuture = null;
      }
    });
  }

  static Future<void> waitForPendingServersApply({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final pending = _pendingServersApplyFuture;
    if (pending == null) {
      return;
    }
    try {
      await pending.timeout(timeout);
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[fcm] wait pending servers apply failed error=$error',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
