// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'bootstrap_servers_service.dart';
import 'push_servers_service.dart';
import 'relay_servers_service.dart';
import 'server_update.dart';
import 'storage_service.dart';
import 'turn_servers_service.dart';
import '../turn/turn_server_config.dart';

class ServerUpdateStorageMergeResult {
  final List<String>? bootstrap;
  final List<String>? relay;
  final List<Map<String, dynamic>>? push;
  final List<Map<String, dynamic>>? turn;

  const ServerUpdateStorageMergeResult({
    required this.bootstrap,
    required this.relay,
    required this.push,
    required this.turn,
  });

  bool get bootstrapChanged => bootstrap != null;
  bool get relayChanged => relay != null;
  bool get pushChanged => push != null;
  bool get turnChanged => turn != null;
}

class ServerUpdateStorageMerger {
  const ServerUpdateStorageMerger();

  Future<ServerUpdateStorageMergeResult> merge({
    required SecureStorageBox settings,
    required ServerUpdate update,
  }) async {
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
    return ServerUpdateStorageMergeResult(
      bootstrap: mergedBootstrap,
      relay: mergedRelay,
      push: mergedPush,
      turn: mergedTurn,
    );
  }

  List<String>? _mergeBootstrapServers(Object? existing, ServerUpdate update) {
    final incoming = <String>{...update.bootstrap, ...update.priorityBootstrap};
    if (incoming.isEmpty) {
      return null;
    }
    final current = (existing is List ? existing : const <dynamic>[])
        .map(
          (item) => BootstrapServersService.normalizeEndpoint(item.toString()),
        )
        .where((item) => item.isNotEmpty)
        .toSet();
    final next = <String>{...current, ...incoming}.toList(growable: false);
    next.sort();
    return next.length == current.length ? null : next;
  }

  List<String>? _mergeRelayServers(Object? existing, ServerUpdate update) {
    final incoming = <String>{...update.relay, ...update.priorityRelay};
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
    ServerUpdate update,
  ) {
    final incoming = <String>{...update.push, ...update.priorityPush};
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

  List<Map<String, dynamic>>? _mergeTurnServers(
    Object? existing,
    ServerUpdate update,
  ) {
    final incoming = <TurnServerConfig>[...update.turn, ...update.priorityTurn];
    if (incoming.isEmpty) {
      return null;
    }
    final current = <String, TurnServerConfig>{};
    if (existing is List) {
      for (final item in existing.whereType<Map>()) {
        final config = TurnServerConfig.fromJson(
          Map<String, dynamic>.from(item),
        );
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
    for (final config in incoming) {
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
}
