// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:io';

import '../runtime/server_availability.dart';
import 'relay_server_status.dart';

class RelayHttpServerPool {
  static const Duration _operationFailureCooldown = Duration(minutes: 2);
  final bool httpsOnly;
  final int maxActiveRelayPool;
  final int fetchPoolSize;
  final Duration sharedHealthFreshness;
  final void Function(String message) log;
  final Future<bool> Function(Uri server) probeServerHealth;

  final List<Uri> _servers = <Uri>[];
  final Map<String, RelayServerStatus> _statuses =
      <String, RelayServerStatus>{};
  final Map<String, DateTime> _operationUnavailableUntil = <String, DateTime>{};

  ServerAvailability? Function(String endpoint)? _availabilityLookup;
  Future<void> Function(List<String> endpoints)? _refreshAvailability;
  int _cursorIndex = 0;

  RelayHttpServerPool({
    required this.httpsOnly,
    required this.maxActiveRelayPool,
    required this.fetchPoolSize,
    required this.sharedHealthFreshness,
    required this.log,
    required this.probeServerHealth,
    ServerAvailability? Function(String endpoint)? availabilityLookup,
    Future<void> Function(List<String> endpoints)? refreshAvailability,
  }) : _availabilityLookup = availabilityLookup,
       _refreshAvailability = refreshAvailability;

  List<RelayServerStatus> get serverStatuses => _servers
      .map((server) {
        final key = server.toString();
        final shared = sharedAvailabilityFor(server);
        if (shared?.isAvailable != null) {
          final previous = _statuses[key];
          return RelayServerStatus(
            url: key,
            healthy: shared!.isAvailable!,
            lastError: shared.error,
            lastSuccessAt: shared.isAvailable == true
                ? (shared.checkedAt ?? previous?.lastSuccessAt)
                : previous?.lastSuccessAt,
          );
        }
        return _statuses[key] ??
            RelayServerStatus(
              url: key,
              healthy: false,
              lastError: 'ожидание проверки',
            );
      })
      .toList(growable: false);

  bool get isEmpty => _servers.isEmpty;

  int get totalServers => _servers.length;

  void setAvailabilityLookup(
    ServerAvailability? Function(String endpoint)? availabilityLookup,
  ) {
    _availabilityLookup = availabilityLookup;
  }

  void setAvailabilityRefresh(
    Future<void> Function(List<String> endpoints)? refreshAvailability,
  ) {
    _refreshAvailability = refreshAvailability;
  }

  void configureServers(List<String> servers) {
    final normalizedServers = <Uri>[];
    for (final raw in servers) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final normalized = normalizeBase(trimmed, httpsOnly: httpsOnly);
      if (normalized == null) {
        log('configure:skip invalid relay endpoint=$trimmed');
        continue;
      }
      normalizedServers.add(normalized);
    }
    _servers
      ..clear()
      ..addAll(normalizedServers);
    final activeKeys = _servers.map((server) => server.toString()).toSet();
    _statuses.removeWhere((key, _) => !activeKeys.contains(key));
    _operationUnavailableUntil.removeWhere(
      (key, _) => !activeKeys.contains(key),
    );
    for (final server in _servers) {
      final key = server.toString();
      _statuses.putIfAbsent(
        key,
        () => RelayServerStatus(
          url: key,
          healthy: false,
          lastError: 'ожидание проверки',
        ),
      );
    }
  }

  Future<List<Uri>> writeTargets({
    Iterable<String> preferredServers = const <String>[],
  }) async {
    final targets = await liveServers(limit: maxActiveRelayPool);
    final preferred = resolveServers(
      preferredServers,
    ).map((server) => server.toString()).toSet();
    return List<Uri>.from(targets)..sort((a, b) {
      final aPreferred = preferred.contains(a.toString());
      final bPreferred = preferred.contains(b.toString());
      if (aPreferred == bPreferred) return 0;
      return aPreferred ? -1 : 1;
    });
  }

  Future<List<Uri>> fetchTargets() => liveServers(limit: fetchPoolSize);

  List<Uri> resolveServers(Iterable<String> servers) {
    final result = <String, Uri>{};
    for (final raw in servers) {
      final normalized = normalizeBase(raw, httpsOnly: httpsOnly);
      if (normalized == null) {
        continue;
      }
      result.putIfAbsent(normalized.toString(), () => normalized);
    }
    return result.values.toList(growable: false);
  }

  Future<List<Uri>> liveServers({required int limit}) async {
    final candidates = candidateServers(limit: limit);
    if (candidates.isEmpty) {
      return const <Uri>[];
    }
    if (_availabilityLookup == null) {
      return liveServersLegacy(candidates, limit: limit);
    }
    await refreshSharedHealthIfStale(candidates);
    return candidates
        .where((server) => effectiveHealthy(server) == true)
        .take(limit)
        .toList(growable: false);
  }

  List<Uri> prioritizedServers({required int limit}) {
    if (_servers.isEmpty) {
      return const <Uri>[];
    }
    final rotated = rotatedServers();
    rotated.sort(compareServers);
    return rotated.take(limit).toList(growable: false);
  }

  void markHealthy(Uri server) {
    final key = server.toString();
    _operationUnavailableUntil.remove(key);
    _statuses[key] = RelayServerStatus(
      url: key,
      healthy: true,
      lastSuccessAt: DateTime.now(),
    );
  }

  void markUnhealthy(Uri server, String error) {
    final key = server.toString();
    _operationUnavailableUntil[key] = DateTime.now().add(
      _operationFailureCooldown,
    );
    final previous = _statuses[key];
    _statuses[key] = RelayServerStatus(
      url: key,
      healthy: false,
      lastError: error,
      lastSuccessAt: previous?.lastSuccessAt,
    );
  }

  ServerAvailability? sharedAvailabilityFor(Uri server) {
    return _availabilityLookup?.call(server.toString());
  }

  bool? effectiveHealthy(Uri server) {
    final key = server.toString();
    final unavailableUntil = _operationUnavailableUntil[key];
    if (unavailableUntil != null) {
      if (DateTime.now().isBefore(unavailableUntil)) {
        return false;
      }
      _operationUnavailableUntil.remove(key);
    }
    if (_availabilityLookup == null) {
      return _statuses[key]?.healthy ?? true;
    }
    return sharedAvailabilityFor(server)?.isAvailable;
  }

  Future<void> refreshSharedHealthIfStale(List<Uri> candidates) async {
    final refresh = _refreshAvailability;
    if (refresh == null || candidates.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final selected = candidates
        .take(maxActiveRelayPool)
        .toList(growable: false);
    final stale = selected.any((server) {
      final availability = sharedAvailabilityFor(server);
      final checkedAt = availability?.checkedAt;
      if (checkedAt == null) {
        return true;
      }
      return now.difference(checkedAt) > sharedHealthFreshness;
    });
    if (!stale) {
      return;
    }
    try {
      await refresh(
        selected.map((server) => server.toString()).toList(growable: false),
      );
    } catch (error) {
      log('relay shortlist refresh failed error=$error');
    }
  }

  int compareServers(Uri a, Uri b) {
    final aAvailability = sharedAvailabilityFor(a);
    final bAvailability = sharedAvailabilityFor(b);
    final aHealthyRank = sortRankForAvailability(aAvailability);
    final bHealthyRank = sortRankForAvailability(bAvailability);
    if (aHealthyRank != bHealthyRank) {
      return aHealthyRank.compareTo(bHealthyRank);
    }
    final aSuccess = lastSuccessAt(a, aAvailability);
    final bSuccess = lastSuccessAt(b, bAvailability);
    if (aSuccess != null && bSuccess != null) {
      return bSuccess.compareTo(aSuccess);
    }
    if (aSuccess != null) {
      return -1;
    }
    if (bSuccess != null) {
      return 1;
    }
    return _servers.indexOf(a).compareTo(_servers.indexOf(b));
  }

  int sortRankForAvailability(ServerAvailability? shared) {
    if (_availabilityLookup == null) {
      return 1;
    }
    final available = shared?.isAvailable;
    if (available == true) {
      return 0;
    }
    if (available == false) {
      return 2;
    }
    return 1;
  }

  DateTime? lastSuccessAt(Uri server, ServerAvailability? shared) {
    final local = _statuses[server.toString()];
    if (shared?.isAvailable == true) {
      return shared?.checkedAt ?? local?.lastSuccessAt;
    }
    return local?.lastSuccessAt;
  }

  List<Uri> candidateServers({required int limit}) {
    if (_servers.isEmpty) {
      return const <Uri>[];
    }
    final rotated = prioritizedServers(limit: _servers.length);
    final available = rotated
        .where((server) => effectiveHealthy(server) == true)
        .take(limit)
        .toList(growable: false);
    if (available.isNotEmpty) {
      return available;
    }
    return rotated.take(limit).toList(growable: false);
  }

  List<Uri> rotatedServers() {
    if (_servers.length <= 1) {
      return List<Uri>.from(_servers);
    }
    final offset = _cursorIndex % _servers.length;
    _cursorIndex += 1;
    return List<Uri>.from(_servers.skip(offset))..addAll(_servers.take(offset));
  }

  Future<List<Uri>> liveServersLegacy(
    List<Uri> candidates, {
    required int limit,
  }) async {
    final selected = <Uri>[];
    final deferred = <Uri>[];

    for (final server in candidates) {
      if (effectiveHealthy(server) == true) {
        selected.add(server);
        if (selected.length >= limit) {
          return selected;
        }
      } else {
        deferred.add(server);
      }
    }

    for (final server in deferred) {
      final live = await probeServerHealth(server);
      if (live) {
        selected.add(server);
        if (selected.length >= limit) {
          return selected;
        }
      }
    }

    return selected;
  }

  static Uri? normalizeBase(String raw, {required bool httpsOnly}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.trim().isEmpty) {
      return null;
    }

    if (httpsOnly && uri.scheme != 'https') {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return null;
    }
    if (!isSafeRelayHost(uri.host.trim())) {
      return null;
    }

    return uri;
  }

  static bool isSafeRelayHost(String host) {
    final value = host.trim();
    if (value.isEmpty || value.contains('%')) {
      return false;
    }
    if (isStaticIpAddressHost(value)) {
      return true;
    }
    final domainPattern = RegExp(r'^[A-Za-z0-9.-]+$');
    return domainPattern.hasMatch(value);
  }

  static bool isStaticIpAddressHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    try {
      return InternetAddress.tryParse(host) != null;
    } on FormatException {
      return false;
    }
  }
}
