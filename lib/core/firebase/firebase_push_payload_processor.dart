import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';

import '../runtime/account_membership_update_payload.dart';
import '../runtime/app_file_logger.dart';
import '../runtime/runtime_servers_merge_orchestrator.dart';
import '../runtime/storage_service.dart';
import 'firebase_push_callback_registry.dart';
import 'firebase_push_log_formatter.dart';
import 'firebase_push_payload_parsers.dart';

class FirebasePushPayloadProcessor {
  const FirebasePushPayloadProcessor({
    RuntimeServersMergeOrchestrator serversMergeOrchestrator =
        const RuntimeServersMergeOrchestrator(),
    FirebasePushAccountMembershipPayloadParser accountMembershipParser =
        const FirebasePushAccountMembershipPayloadParser(),
    FirebasePushGroupMembersPayloadParser groupMembersParser =
        const FirebasePushGroupMembersPayloadParser(),
    FirebasePushLogFormatter logFormatter = const FirebasePushLogFormatter(),
  }) : _serversMergeOrchestrator = serversMergeOrchestrator,
       _accountMembershipParser = accountMembershipParser,
       _groupMembersParser = groupMembersParser,
       _logFormatter = logFormatter;

  final RuntimeServersMergeOrchestrator _serversMergeOrchestrator;
  final FirebasePushAccountMembershipPayloadParser _accountMembershipParser;
  final FirebasePushGroupMembersPayloadParser _groupMembersParser;
  final FirebasePushLogFormatter _logFormatter;

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
    final storage = StorageService();
    final settings = storage.getSettings();
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
