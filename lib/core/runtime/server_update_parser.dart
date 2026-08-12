import 'dart:convert';

import '../turn/turn_server_config.dart';
import 'bootstrap_servers_service.dart';
import 'push_servers_service.dart';
import 'relay_servers_service.dart';
import 'server_update.dart';
import 'turn_servers_service.dart';

class ServerUpdateParser {
  const ServerUpdateParser();

  ServerUpdate? parse(Map<String, dynamic> data) {
    final nestedData = _extractNestedData(data);
    final serversPayload = _decodeMap(
      _readValue(data, nestedData, const <String>['servers']),
    );
    final priorityPayload = _decodeMap(
      _readValue(data, nestedData, const <String>['priority_servers']),
    );
    if (serversPayload == null && priorityPayload == null) {
      return null;
    }
    return ServerUpdate(
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

  Map<String, dynamic>? _extractNestedData(Map<String, dynamic> data) {
    return _decodeMap(data['data']) ?? _decodeMap(data['payload']);
  }

  Map<String, dynamic>? _decodeMap(Object? raw) {
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Object? _readValue(
    Map<String, dynamic> data,
    Map<String, dynamic>? nestedData,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (data.containsKey(key)) {
        return data[key];
      }
      if (nestedData != null && nestedData.containsKey(key)) {
        return nestedData[key];
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
