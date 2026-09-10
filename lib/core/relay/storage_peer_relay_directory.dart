// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import '../runtime/storage_service.dart';
import 'peer_relay_directory.dart';
import 'relay_http_server_pool.dart';

class StoragePeerRelayDirectory implements PeerRelayDirectory {
  static const String _key = 'peerlink.peer_relay_directory.v1';
  static const Duration _ttl = Duration(days: 30);

  StoragePeerRelayDirectory({required SecureStorageBox settings})
    : _settings = settings;

  final SecureStorageBox _settings;

  @override
  List<String> freshRelayServersFor(String peerId) {
    final value = _entries()[peerId.trim()];
    if (value == null || DateTime.now().difference(value.updatedAt) > _ttl) {
      return const <String>[];
    }
    return value.relays;
  }

  @override
  Future<void> updateRelayServers(
    String peerId,
    Iterable<String> relayServers, {
    required DateTime updatedAt,
  }) async {
    final peer = peerId.trim();
    if (peer.isEmpty) return;
    final relays =
        relayServers
            .map(
              (value) =>
                  RelayHttpServerPool.normalizeBase(value, httpsOnly: false),
            )
            .whereType<Uri>()
            .map((value) => value.toString())
            .toSet()
            .toList(growable: false)
          ..sort();
    if (relays.isEmpty) return;
    final entries = _entries();
    entries[peer] = _Entry(relays, updatedAt);
    await _settings.put(
      _key,
      jsonEncode(
        entries.map(
          (peer, value) => MapEntry(peer, <String, dynamic>{
            'relay': value.relays,
            'updatedAtMs': value.updatedAt.millisecondsSinceEpoch,
          }),
        ),
      ),
    );
  }

  Map<String, _Entry> _entries() {
    final raw = _settings.get(_key);
    if (raw is! String || raw.isEmpty) return <String, _Entry>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, _Entry>{};
      return decoded.map<String, _Entry>((key, rawValue) {
        final value = rawValue is Map ? rawValue : const <String, dynamic>{};
        return MapEntry(
          key.toString(),
          _Entry(
            (value['relay'] as List? ?? const <dynamic>[])
                .whereType<String>()
                .toList(growable: false),
            DateTime.fromMillisecondsSinceEpoch(
              value['updatedAtMs'] as int? ?? 0,
            ),
          ),
        );
      });
    } catch (_) {
      return <String, _Entry>{};
    }
  }
}

class _Entry {
  const _Entry(this.relays, this.updatedAt);
  final List<String> relays;
  final DateTime updatedAt;
}
