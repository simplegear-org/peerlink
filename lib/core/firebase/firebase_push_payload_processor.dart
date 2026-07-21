import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:firebase_messaging/firebase_messaging.dart';

import '../runtime/account_membership_update_payload.dart';
import '../runtime/app_file_logger.dart';
import '../runtime/bootstrap_servers_service.dart';
import '../runtime/push_servers_service.dart';
import '../runtime/storage_service.dart';
import '../runtime/relay_servers_service.dart';
import '../runtime/turn_servers_service.dart';
import '../turn/turn_server_config.dart';
import 'firebase_push_payload.dart';
import 'firebase_push_callback_registry.dart';
import 'firebase_push_models.dart';

class FirebasePushPayloadProcessor {
  const FirebasePushPayloadProcessor();

  void logIncomingPush(RemoteMessage message, {required String source}) {
    final safeData = <String, dynamic>{};
    message.data.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower.contains('sig') ||
          lower.contains('signingpub') ||
          lower.contains('token') ||
          lower.contains('authorization')) {
        safeData[key] = '<redacted>';
        return;
      }
      safeData[key] = value;
    });
    final payload = <String, dynamic>{
      'source': source,
      'messageId': message.messageId,
      'from': message.from,
      'sentTime': message.sentTime?.toIso8601String(),
      'notification': <String, dynamic>{
        'title': message.notification?.title,
        'body': message.notification?.body,
      },
      'data': safeData,
    };
    final encoded = jsonEncode(payload);
    final truncated = encoded.length > 4000
        ? '${encoded.substring(0, 4000)}...(truncated)'
        : encoded;
    developer.log(
      '[fcm][incoming] $truncated',
      name: 'FirebaseMessagingService',
    );
    AppFileLogger.log(
      '[fcm][incoming] $truncated',
      name: 'FirebaseMessagingService',
    );
  }

  Future<void> mergeServersFromPush(Map<String, dynamic> data) async {
    final update = _extractServerUpdate(data);
    if (update == null || update.isEmpty) {
      AppFileLogger.log(
        '[fcm][servers] no servers in push payload',
        name: 'FirebaseMessagingService',
      );
      return;
    }
    AppFileLogger.log(
      '[fcm][servers] extracted bootstrap=${update.bootstrap.length} '
      'relay=${update.relay.length} push=${update.push.length} '
      'turn=${update.turn.length} priorityBootstrap=${update.priorityBootstrap.length} '
      'priorityTurn=${update.priorityTurn.length} '
      'bootstrapList=${update.bootstrap.join(",")} '
      'priorityBootstrapList=${update.priorityBootstrap.join(",")}',
      name: 'FirebaseMessagingService',
    );
    final storage = StorageService();
    final settings = storage.getSettings();

    final mergedBootstrap = _mergeBootstrapServers(
      settings.get('bootstrap_servers'),
      update,
    );
    final mergedRelay = _mergeRelayServers(
      settings.get('relay_servers'),
      update,
    );
    final mergedPush = _mergePushServers(settings.get('push_servers'), update);
    final mergedTurn = _mergeTurnServers(settings.get('turn_servers'), update);

    if (mergedBootstrap != null) {
      await settings.put('bootstrap_servers', mergedBootstrap);
      AppFileLogger.log(
        '[fcm][servers] bootstrap storage write=${mergedBootstrap.join(",")}',
        name: 'FirebaseMessagingService',
      );
    }
    if (mergedRelay != null) {
      await settings.put('relay_servers', mergedRelay);
    }
    if (mergedTurn != null) {
      await settings.put('turn_servers', mergedTurn);
    }
    if (mergedPush != null) {
      await settings.put('push_servers', mergedPush);
    }
    AppFileLogger.log(
      '[fcm][servers] storage merged bootstrapChanged=${mergedBootstrap != null} '
      'relayChanged=${mergedRelay != null} pushChanged=${mergedPush != null} '
      'turnChanged=${mergedTurn != null} '
      'bootstrapCurrent=${((settings.get('bootstrap_servers') as List?) ?? const <dynamic>[]).join(",")}',
      name: 'FirebaseMessagingService',
    );
    final callback = FirebasePushCallbackRegistry.onServersFromPush;
    if (callback != null) {
      AppFileLogger.log(
        '[fcm][servers] apply callback start',
        name: 'FirebaseMessagingService',
      );
      final future = callback(update);
      FirebasePushCallbackRegistry.trackPendingServersApply(future);
      await future;
      AppFileLogger.log(
        '[fcm][servers] apply callback done',
        name: 'FirebaseMessagingService',
      );
    } else {
      AppFileLogger.log(
        '[fcm][servers] apply callback missing',
        name: 'FirebaseMessagingService',
      );
    }
  }

  Future<bool> applyAccountMembershipUpdateFromPush(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    final payload = _extractAccountMembershipUpdatePayload(data);
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
    final incoming = _extractGroupMembersUpdatePayload(data);
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

  PushServerUpdate? _extractServerUpdate(Map<String, dynamic> data) {
    final pushPayload = FirebasePushPayload.fromMap(data);
    Object? raw = pushPayload.rawServers;
    Object? rawPriority = pushPayload.rawPriorityServers;
    Map<String, dynamic>? serversPayload;
    Map<String, dynamic>? priorityPayload;
    if (raw is Map) {
      serversPayload = Map<String, dynamic>.from(raw);
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          serversPayload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    if (rawPriority is Map) {
      priorityPayload = Map<String, dynamic>.from(rawPriority);
    } else if (rawPriority is String && rawPriority.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPriority);
        if (decoded is Map) {
          priorityPayload = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        priorityPayload = null;
      }
    }
    if (serversPayload == null && priorityPayload == null) {
      return null;
    }
    final bootstrap =
        (serversPayload?['bootstrap'] as List? ?? const <dynamic>[])
            .map(
              (item) =>
                  BootstrapServersService.normalizeEndpoint(item.toString()),
            )
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false);
    final relay = (serversPayload?['relay'] as List? ?? const <dynamic>[])
        .map((item) => RelayServersService.normalizeEndpoint(item.toString()))
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final push = (serversPayload?['push'] as List? ?? const <dynamic>[])
        .map((item) => _normalizeIncomingPushEndpoint(item.toString()))
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final turn = (serversPayload?['turn'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) => TurnServerConfig.fromJson(Map<String, dynamic>.from(item)),
        )
        .map((item) {
          final normalizedUrl = TurnServersService.normalizeTurnsEndpoint(
            item.url,
          );
          if (normalizedUrl == null || normalizedUrl.isEmpty) {
            return null;
          }
          return item.copyWith(
            url: normalizedUrl,
            username: item.username.trim().isEmpty
                ? 'peerlink'
                : item.username.trim(),
            password: item.password.isEmpty ? 'peerlink' : item.password,
          );
        })
        .whereType<TurnServerConfig>()
        .toList(growable: false);
    final priorityBootstrap =
        (priorityPayload?['bootstrap'] as List? ?? const <dynamic>[])
            .map(
              (item) =>
                  BootstrapServersService.normalizeEndpoint(item.toString()),
            )
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final priorityTurn =
        (priorityPayload?['turn'] as List? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (item) =>
                  TurnServerConfig.fromJson(Map<String, dynamic>.from(item)),
            )
            .map((item) {
              final normalizedUrl = TurnServersService.normalizeTurnsEndpoint(
                item.url,
              );
              if (normalizedUrl == null || normalizedUrl.isEmpty) {
                return null;
              }
              return item.copyWith(
                url: normalizedUrl,
                username: item.username.trim().isEmpty
                    ? 'peerlink'
                    : item.username.trim(),
                password: item.password.isEmpty ? 'peerlink' : item.password,
              );
            })
            .whereType<TurnServerConfig>()
            .toList(growable: false);
    return PushServerUpdate(
      bootstrap: bootstrap,
      relay: relay,
      push: push,
      turn: turn,
      priorityBootstrap: priorityBootstrap,
      priorityTurn: priorityTurn,
    );
  }

  AccountMembershipUpdatePayload? _extractAccountMembershipUpdatePayload(
    Map<String, dynamic> data,
  ) {
    final payload = FirebasePushPayload.fromMap(data);
    if (!payload.isAccountMembershipUpdate) {
      return null;
    }
    final raw = payload.rawAccountMembershipUpdate;
    if (raw is Map) {
      try {
        return AccountMembershipUpdatePayload.fromJson(
          Map<String, dynamic>.from(raw),
        );
      } catch (_) {
        return null;
      }
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return AccountMembershipUpdatePayload.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  _IncomingGroupMembersPushPayload? _extractGroupMembersUpdatePayload(
    Map<String, dynamic> data,
  ) {
    final pushPayload = FirebasePushPayload.fromMap(data);
    if (pushPayload.isGroupMembersUpdate) {
      final payload = _extractGroupMembersMap(pushPayload.rawGroupMembers);
      if (payload == null) {
        return null;
      }
      final sourcePeerId = (payload['senderPeerId'] as String?)?.trim();
      return _IncomingGroupMembersPushPayload(
        payload: payload,
        sourcePeerId: sourcePeerId,
      );
    }
    return null;
  }

  Map<String, dynamic>? _extractGroupMembersMap(Object? raw) {
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return null;
      }
    }
    return null;
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

class _IncomingGroupMembersPushPayload {
  final Map<String, dynamic> payload;
  final String? sourcePeerId;

  const _IncomingGroupMembersPushPayload({
    required this.payload,
    required this.sourcePeerId,
  });
}

List<String>? _mergeBootstrapServers(
  Object? existing,
  PushServerUpdate update,
) {
  final incoming = update.bootstrap;
  if (incoming.isEmpty) {
    return null;
  }
  final current = (existing is List ? existing : const <dynamic>[])
      .map((item) => BootstrapServersService.normalizeEndpoint(item.toString()))
      .where((item) => item.isNotEmpty)
      .toSet();
  final next = <String>{...current, ...incoming}.toList(growable: false);
  next.sort();
  return next.length == current.length ? null : next;
}

List<String>? _mergeRelayServers(Object? existing, PushServerUpdate update) {
  final incoming = update.relay;
  if (incoming.isEmpty) {
    return null;
  }
  final current = (existing is List ? existing : const <dynamic>[])
      .map((item) => RelayServersService.normalizeEndpoint(item.toString()))
      .where((item) => item.isNotEmpty)
      .toSet();
  final next = <String>{...current, ...incoming}.toList(growable: false);
  next.sort();
  return next.length == current.length ? null : next;
}

List<Map<String, dynamic>>? _mergePushServers(
  Object? existing,
  PushServerUpdate update,
) {
  final incoming = update.push;
  if (incoming.isEmpty) {
    return null;
  }
  final current = <String, PushServerEntry>{};
  if (existing is List) {
    for (final item in existing) {
      final entry = PushServerEntry.fromStorage(item);
      if (entry == null) {
        continue;
      }
      current[entry.endpoint] = entry;
    }
  }
  var changed = false;
  for (final endpoint in incoming) {
    if (current.containsKey(endpoint)) {
      continue;
    }
    current[endpoint] = PushServerEntry(endpoint: endpoint);
    changed = true;
  }
  if (!changed) {
    return null;
  }
  final next = current.values.toList(growable: false)
    ..sort((a, b) => a.endpoint.compareTo(b.endpoint));
  return next.map((item) => item.toJson()).toList(growable: false);
}

String _normalizeIncomingPushEndpoint(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null ||
      parsed.host.isEmpty ||
      !parsed.hasScheme ||
      (parsed.scheme != 'http' && parsed.scheme != 'https')) {
    return '';
  }
  return parsed.toString();
}

List<Map<String, dynamic>>? _mergeTurnServers(
  Object? existing,
  PushServerUpdate update,
) {
  if (update.turn.isEmpty) {
    return null;
  }
  final current = <String, TurnServerConfig>{};
  if (existing is List) {
    for (final item in existing.whereType<Map>()) {
      final config = TurnServerConfig.fromJson(Map<String, dynamic>.from(item));
      final normalizedUrl = TurnServersService.normalizeTurnsEndpoint(
        config.url,
      );
      if (normalizedUrl == null || normalizedUrl.isEmpty) {
        continue;
      }
      current[normalizedUrl] = config.copyWith(url: normalizedUrl);
    }
  }

  var changed = false;
  for (final config in update.turn) {
    final normalizedUrl = config.url;
    if (current.containsKey(normalizedUrl)) {
      continue;
    }
    current[normalizedUrl] = config;
    changed = true;
  }

  if (!changed) {
    return null;
  }
  final next = current.values.toList(growable: false)
    ..sort((a, b) => a.url.compareTo(b.url));
  return next.map((item) => item.toJson()).toList(growable: false);
}
