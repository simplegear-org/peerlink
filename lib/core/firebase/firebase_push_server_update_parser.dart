import 'dart:convert';

import '../runtime/bootstrap_servers_service.dart';
import '../runtime/push_servers_service.dart';
import '../runtime/relay_servers_service.dart';
import '../runtime/turn_servers_service.dart';
import '../turn/turn_server_config.dart';
import 'firebase_push_models.dart';
import 'firebase_push_payload.dart';

class FirebasePushServerUpdateParser {
  const FirebasePushServerUpdateParser();

  PushServerUpdate? parse(Map<String, dynamic> data) {
    final pushPayload = FirebasePushPayload.fromMap(data);
    final serversPayload = _decodeMap(pushPayload.rawServers);
    final priorityPayload = _decodeMap(pushPayload.rawPriorityServers);
    if (serversPayload == null && priorityPayload == null) {
      return null;
    }
    return PushServerUpdate(
      bootstrap: _parseBootstrap(serversPayload),
      relay: _parseRelay(serversPayload),
      push: _parsePush(serversPayload),
      turn: _parseTurn(serversPayload),
      priorityBootstrap: _parseBootstrap(priorityPayload),
      priorityRelay: _parseRelay(priorityPayload),
      priorityPush: _parsePush(priorityPayload),
      priorityTurn: _parseTurn(priorityPayload),
    );
  }

  Map<String, dynamic>? _decodeMap(Object? raw) {
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

  List<String> _parseBootstrap(Map<String, dynamic>? payload) {
    return (payload?['bootstrap'] as List? ?? const <dynamic>[])
        .map(
          (item) => BootstrapServersService.normalizeEndpoint(item.toString()),
        )
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _parseRelay(Map<String, dynamic>? payload) {
    return (payload?['relay'] as List? ?? const <dynamic>[])
        .map((item) => RelayServersService.normalizeEndpoint(item.toString()))
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<String> _parsePush(Map<String, dynamic>? payload) {
    return (payload?['push'] as List? ?? const <dynamic>[])
        .map(
          (item) =>
              PushServersService.normalizeIncomingEndpoint(item.toString()),
        )
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  List<TurnServerConfig> _parseTurn(Map<String, dynamic>? payload) {
    return (payload?['turn'] as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (item) => TurnServerConfig.fromJson(Map<String, dynamic>.from(item)),
        )
        .map(_normalizeTurnConfig)
        .whereType<TurnServerConfig>()
        .toList(growable: false);
  }

  TurnServerConfig? _normalizeTurnConfig(TurnServerConfig item) {
    final normalizedUrl = TurnServersService.normalizeTurnsEndpoint(item.url);
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
  }
}
