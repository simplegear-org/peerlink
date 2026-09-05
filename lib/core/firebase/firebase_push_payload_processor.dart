// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';

import '../runtime/account_membership_update_payload.dart';
import '../runtime/app_file_logger.dart';
import '../runtime/moderation_policy_service.dart';
import '../runtime/runtime_servers_merge_orchestrator.dart';
import '../runtime/storage_service.dart';
import 'firebase_push_callback_registry.dart';
import 'firebase_push_log_formatter.dart';
import 'firebase_push_payload.dart';
import 'firebase_push_payload_parsers.dart';

class FirebasePushPayloadProcessor {
  FirebasePushPayloadProcessor({
    required StorageService storage,
    RuntimeServersMergeOrchestrator? serversMergeOrchestrator,
    FirebasePushAccountMembershipPayloadParser accountMembershipParser =
        const FirebasePushAccountMembershipPayloadParser(),
    FirebasePushGroupMembersPayloadParser groupMembersParser =
        const FirebasePushGroupMembersPayloadParser(),
    FirebasePushLogFormatter logFormatter = const FirebasePushLogFormatter(),
    ModerationPolicyService? moderationPolicyService,
  }) : _storage = storage,
       _serversMergeOrchestrator =
           serversMergeOrchestrator ??
           RuntimeServersMergeOrchestrator(settings: storage.getSettings()),
       _accountMembershipParser = accountMembershipParser,
       _groupMembersParser = groupMembersParser,
       _logFormatter = logFormatter,
       _moderationPolicyService = moderationPolicyService;

  final RuntimeServersMergeOrchestrator _serversMergeOrchestrator;
  final StorageService _storage;
  final FirebasePushAccountMembershipPayloadParser _accountMembershipParser;
  final FirebasePushGroupMembersPayloadParser _groupMembersParser;
  final FirebasePushLogFormatter _logFormatter;
  final ModerationPolicyService? _moderationPolicyService;

  Future<FirebaseModerationProcessingResult> applyModerationGate(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final isModerationPolicy = await applyModerationPolicyFromPush(
      data,
      source: source,
    );
    if (isModerationPolicy) {
      return const FirebaseModerationProcessingResult(
        isModerationPolicy: true,
        shouldDropBecauseBanned: false,
      );
    }
    final shouldDropBecauseBanned = isPeerBanned();
    if (shouldDropBecauseBanned) {
      AppFileLogger.log(
        '[fcm][moderation][$source] push dropped reason=account_banned',
        name: 'FirebaseMessagingService',
      );
    }
    return FirebaseModerationProcessingResult(
      isModerationPolicy: false,
      shouldDropBecauseBanned: shouldDropBecauseBanned,
    );
  }

  void logIncomingPush(RemoteMessage message, {required String source}) {
    final formatted = _logFormatter.incomingPush(message, source: source);
    developer.log(
      '[fcm][incoming] $formatted',
      name: 'FirebaseMessagingService',
    );
    AppFileLogger.log(
      '[fcm][incoming] $formatted',
      name: 'FirebaseMessagingService',
    );
  }

  Future<void> mergeServersFromPush(Map<String, dynamic> data) async {
    await _serversMergeOrchestrator.applyIfPresent(
      data,
      source: 'push',
      logName: 'FirebaseMessagingService',
      logPrefix: '[fcm][servers]',
    );
  }

  Future<bool> applyModerationPolicyFromPush(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final pushPayload = FirebasePushPayload.fromMap(data);
    if (!pushPayload.isModerationPolicy) {
      return false;
    }
    final normalizedData = <String, dynamic>{
      ...?pushPayload.nestedData,
      ...pushPayload.root,
    };
    final snapshot = await _moderationPolicyService?.applyPushPayload(
      normalizedData,
    );
    if (snapshot == null) {
      return false;
    }
    AppFileLogger.log(
      '[fcm][moderation][$source] applied state=${snapshot.state.name}',
      name: 'FirebaseMessagingService',
    );
    final callback = FirebasePushCallbackRegistry.onModerationPolicyFromPush;
    if (callback != null) {
      try {
        await callback(snapshot, source: source);
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[fcm][moderation][$source] callback failed error=$error',
          name: 'FirebaseMessagingService',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return true;
  }

  bool isPeerBanned() {
    return _moderationPolicyService?.isBanned ?? false;
  }

  Future<bool> applyAccountMembershipUpdateFromPush(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final payload = _accountMembershipParser.parse(data);
    if (payload == null) {
      return false;
    }
    final callback =
        FirebasePushCallbackRegistry.onAccountMembershipUpdateFromPush;
    if (callback == null) {
      await _appendIncomingAccountMembershipUpdate(payload);
      AppFileLogger.log(
        '[fcm][account_update][$source] queued update=${payload.updateId} '
        'reason=callback_missing',
        name: 'FirebaseMessagingService',
      );
      return true;
    }
    try {
      await callback(payload);
      AppFileLogger.log(
        '[fcm][account_update][$source] applied update=${payload.updateId}',
        name: 'FirebaseMessagingService',
      );
    } catch (error, stackTrace) {
      await _appendIncomingAccountMembershipUpdate(payload);
      AppFileLogger.log(
        '[fcm][account_update][$source] apply_failed '
        'queued update=${payload.updateId} error=$error',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return true;
  }

  Future<bool> applyGroupMembersUpdateFromPush(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final incoming = _groupMembersParser.parse(data);
    if (incoming == null) {
      return false;
    }
    final callback = FirebasePushCallbackRegistry.onGroupMembersUpdateFromPush;
    if (callback == null) {
      AppFileLogger.log(
        '[fcm][group_members][$source] skip reason=callback_missing',
        name: 'FirebaseMessagingService',
      );
      return true;
    }
    try {
      await callback(incoming.payload, sourcePeerId: incoming.sourcePeerId);
      AppFileLogger.log(
        '[fcm][group_members][$source] applied '
        'source=${incoming.sourcePeerId ?? '-'}',
        name: 'FirebaseMessagingService',
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[fcm][group_members][$source] apply_failed error=$error',
        name: 'FirebaseMessagingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return true;
  }

  Future<void> _appendIncomingAccountMembershipUpdate(
    AccountMembershipUpdatePayload payload,
  ) async {
    final settings = _storage.getSettings();
    final existingRaw = settings.get(accountMembershipUpdatesStorageKey);
    final current = <Map<String, dynamic>>[];
    if (existingRaw is String && existingRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(existingRaw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            current.add(Map<String, dynamic>.from(item));
          }
        }
      } catch (_) {}
    }
    current.removeWhere(
      (item) => item['updateId']?.toString() == payload.updateId,
    );
    current.add(payload.toJson());
    await settings.put(accountMembershipUpdatesStorageKey, jsonEncode(current));
  }
}

class FirebaseModerationProcessingResult {
  final bool isModerationPolicy;
  final bool shouldDropBecauseBanned;

  const FirebaseModerationProcessingResult({
    required this.isModerationPolicy,
    required this.shouldDropBecauseBanned,
  });

  bool get shouldStopRegularHandling =>
      isModerationPolicy || shouldDropBecauseBanned;
}
