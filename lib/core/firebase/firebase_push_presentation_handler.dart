// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../notification/notification_service.dart';
import '../runtime/app_file_logger.dart';
import '../runtime/peer_access_control_service.dart';
import '../runtime/storage_service.dart';
import 'firebase_push_callback_registry.dart';
import 'firebase_push_payload.dart';
import 'firebase_push_payload_processor.dart';
import 'firebase_push_servers_merge_orchestrator.dart';

class FirebasePushPresentationHandler {
  FirebasePushPresentationHandler({
    required FirebasePushPayloadProcessor payloadProcessor,
    required StorageService storage,
  }) : _payloadProcessor = payloadProcessor,
       _accessControl = PeerAccessControlService.forStorage(storage),
       _serversMergeOrchestrator = FirebasePushServersMergeOrchestrator(
         settings: storage.getSettings(),
       ) {
    _configureIosPushPayloadCallbacks();
  }

  static const MethodChannel _iosPushPayloadMethodChannel = MethodChannel(
    'peerlink/push_payload/methods',
  );
  static FirebasePushPresentationHandler? _iosPushPayloadHandler;
  static const int _recentPushPayloadLimit = 64;
  static const Duration _recentPushPayloadTtl = Duration(minutes: 2);
  static final Map<String, DateTime> _recentPushPayloadKeys =
      <String, DateTime>{};

  final FirebasePushPayloadProcessor _payloadProcessor;
  final PeerAccessControlService _accessControl;
  final FirebasePushServersMergeOrchestrator _serversMergeOrchestrator;

  void _configureIosPushPayloadCallbacks() {
    _iosPushPayloadHandler = this;
    _iosPushPayloadMethodChannel.setMethodCallHandler((call) async {
      if (call.method != 'pushPayloadAvailable') {
        throw MissingPluginException('Unknown method ${call.method}');
      }
      await _iosPushPayloadHandler?.handlePendingIosPushFallback();
    });
  }

  Future<void> configureForegroundPresentation(
    FirebaseMessaging messaging,
  ) async {
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );
  }

  Future<void> handleForegroundMessage(RemoteMessage message) async {
    developer.log(
      '[fcm] foreground message id=${message.messageId}',
      name: 'FirebaseMessagingService',
    );
    _payloadProcessor.logIncomingPush(message, source: 'foreground');
    if (_shouldSkipDuplicatePush(message.data, source: 'foreground')) {
      return;
    }
    final moderation = await _payloadProcessor.applyModerationGate(
      message.data,
      source: 'foreground',
    );
    if (moderation.shouldStopRegularHandling) {
      return;
    }
    if (_shouldDropForAccessControl(message.data, source: 'foreground')) {
      return;
    }
    await _applyPushSideEffects(message.data, source: 'foreground');
    await FirebasePushCallbackRegistry.emitPushOpened(
      Map<String, dynamic>.from(message.data),
      source: 'foreground',
    );
  }

  Future<void> handleOpenedMessage(RemoteMessage message) async {
    developer.log(
      '[fcm] opened message id=${message.messageId}',
      name: 'FirebaseMessagingService',
    );
    _payloadProcessor.logIncomingPush(message, source: 'opened');
    if (_shouldSkipDuplicatePush(message.data, source: 'opened')) {
      return;
    }
    final moderation = await _payloadProcessor.applyModerationGate(
      message.data,
      source: 'opened',
    );
    if (moderation.shouldStopRegularHandling) {
      return;
    }
    if (_shouldDropForAccessControl(message.data, source: 'opened')) {
      return;
    }
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
    if (!Platform.isIOS && !Platform.isAndroid) {
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
    if (_shouldSkipDuplicatePush(normalized, source: 'native-fallback')) {
      return;
    }
    final moderation = await _payloadProcessor.applyModerationGate(
      normalized,
      source: 'native-fallback',
    );
    if (moderation.shouldStopRegularHandling) {
      return;
    }
    if (_shouldDropForAccessControl(normalized, source: 'native-fallback')) {
      return;
    }
    await _serversMergeOrchestrator.applyIfPresent(
      normalized,
      source: 'native-fallback',
    );
    await FirebasePushCallbackRegistry.emitPushOpened(
      normalized,
      source: 'native-fallback',
    );
  }

  bool _shouldSkipDuplicatePush(
    Map<String, dynamic> data, {
    required String source,
  }) {
    final key = _dedupeKeyForPush(data);
    if (key.isEmpty) {
      return false;
    }
    final now = DateTime.now();
    _recentPushPayloadKeys.removeWhere(
      (_, seenAt) => now.difference(seenAt) > _recentPushPayloadTtl,
    );
    if (_recentPushPayloadKeys.containsKey(key)) {
      AppFileLogger.log(
        '[fcm] duplicate push payload ignored source=$source key=$key',
        name: 'FirebaseMessagingService',
      );
      return true;
    }
    _recentPushPayloadKeys[key] = now;
    while (_recentPushPayloadKeys.length > _recentPushPayloadLimit) {
      _recentPushPayloadKeys.remove(_recentPushPayloadKeys.keys.first);
    }
    return false;
  }

  String _dedupeKeyForPush(Map<String, dynamic> data) {
    final payload = FirebasePushPayload.fromMap(data);
    final sequence = payload.relayMessageId.isNotEmpty
        ? payload.relayMessageId
        : (data['lastSeq']?.toString().trim() ?? '');
    final target = payload.groupId.isNotEmpty
        ? payload.groupId
        : payload.directPeerId;
    final callId = payload.callId;
    final businessId = sequence.isNotEmpty ? sequence : callId;
    if (payload.type.isEmpty || businessId.isEmpty) {
      return '';
    }
    return '${payload.type}|${payload.senderPeerId}|$target|$businessId';
  }

  bool _shouldDropForAccessControl(
    Map<String, dynamic> data, {
    required String source,
  }) {
    final payload = FirebasePushPayload.fromMap(data);
    final peerId = payload.senderPeerId;
    if (peerId.isEmpty) {
      return false;
    }
    final decision = _accessControl.evaluateIncoming(
      peerId: peerId,
      type: payload.isCallPayload
          ? IncomingInteractionType.call
          : IncomingInteractionType.push,
    );
    if (decision == IncomingInteractionDecision.allow) {
      return false;
    }
    AppFileLogger.log(
      '[fcm] push dropped source=$source reason=${decision.name} '
      'type=${payload.type} from=$peerId',
      name: 'FirebaseMessagingService',
    );
    return true;
  }

  Future<void> showNotificationFromPush(
    RemoteMessage message, {
    bool moderationPolicyAlreadyApplied = false,
  }) async {
    _payloadProcessor.logIncomingPush(message, source: 'display');
    final moderation = moderationPolicyAlreadyApplied
        ? const FirebaseModerationProcessingResult(
            isModerationPolicy: true,
            shouldDropBecauseBanned: false,
          )
        : await _payloadProcessor.applyModerationGate(
            message.data,
            source: 'display',
          );
    if (moderation.shouldDropBecauseBanned) {
      return;
    }
    if (!moderation.isModerationPolicy &&
        _shouldDropForAccessControl(message.data, source: 'display')) {
      return;
    }
    final handledSilently = moderation.isModerationPolicy
        ? false
        : await _applyPushSideEffects(message.data, source: 'display');
    if (handledSilently) {
      return;
    }
    final notification = message.notification;
    final data = message.data;
    final payload = FirebasePushPayload.fromMap(data);
    final fromPeerId = payload.senderPeerId.isNotEmpty
        ? payload.senderPeerId
        : 'unknown';

    if (payload.isCallPayload) {
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

  Future<bool> _applyPushSideEffects(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final moderation = await _payloadProcessor.applyModerationGate(
      data,
      source: source,
    );
    if (moderation.isModerationPolicy) {
      return false;
    }
    if (moderation.shouldDropBecauseBanned) {
      return true;
    }
    await _serversMergeOrchestrator.applyIfPresent(data, source: source);
    final isAccountMembershipUpdate = await _payloadProcessor
        .applyAccountMembershipUpdateFromPush(data, source: source);
    if (isAccountMembershipUpdate) {
      return true;
    }
    final isGroupMembersUpdate = await _payloadProcessor
        .applyGroupMembersUpdateFromPush(data, source: source);
    return isGroupMembersUpdate;
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
}
