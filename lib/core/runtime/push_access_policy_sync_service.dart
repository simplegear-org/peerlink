// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../push/push_api_client.dart';
import '../security/identity_service.dart';
import 'app_file_logger.dart';
import 'contacts_repository.dart';
import 'peer_access_control_service.dart';
import 'push_servers_service.dart';
import 'storage_service.dart';

class PushAccessPolicySyncService {
  static const _lastSnapshotHashKey = 'push_access_policy_last_hash.v1';
  static const _policyVersionKey = 'push_access_policy_version.v1';
  static const _pendingSyncKey = 'push_access_policy_pending.v1';
  static const _pushServerUrlDefine = String.fromEnvironment('PUSH_SERVER_URL');
  static const _pushApiTokenDefine = String.fromEnvironment(
    'PUSH_API_TOKEN',
    defaultValue: 'peerlink',
  );

  final IdentityService identity;
  final StorageService storage;
  final PushApiClient pushApiClient;
  final List<Uri> Function()? resolvePushBaseUris;
  final DateTime Function() now;

  Future<void>? _syncFuture;

  PushAccessPolicySyncService({
    required this.identity,
    required this.storage,
    required this.pushApiClient,
    this.resolvePushBaseUris,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  SecureStorageBox get _settings => storage.getSettings();

  Future<void> syncNow({required String reason, bool force = false}) async {
    final current = _syncFuture;
    if (current != null) {
      await current;
      if (!force) {
        return;
      }
    }
    final future = _syncNowImpl(reason: reason, force: force);
    _syncFuture = future;
    try {
      await future;
    } finally {
      if (identical(_syncFuture, future)) {
        _syncFuture = null;
      }
    }
  }

  Future<void> retryPending({required String reason}) async {
    if (_settings.get(_pendingSyncKey) == true) {
      await syncNow(reason: reason, force: true);
    }
  }

  Future<void> _syncNowImpl({
    required String reason,
    required bool force,
  }) async {
    final endpoints = _activePushBaseUris();
    if (endpoints.isEmpty) {
      await _settings.put(_pendingSyncKey, true);
      _log('skip reason=$reason no_endpoint pending=true');
      return;
    }

    final snapshot = _buildSnapshot();
    final lastHash = _settings.get(_lastSnapshotHashKey) as String?;
    final pending = _settings.get(_pendingSyncKey) == true;
    if (!force && !pending && lastHash == snapshot.hash) {
      _log('skip reason=$reason unchanged endpoints=${endpoints.length}');
      return;
    }

    final version = lastHash == snapshot.hash
        ? _readPolicyVersion()
        : _readPolicyVersion() + 1;
    _log(
      'start reason=$reason force=$force pending=$pending '
      'version=$version endpoints=${endpoints.length} '
      'contacts=${snapshot.contactPeerIds.length} '
      'blocked=${snapshot.blockedPeerIds.length} hash=${snapshot.hash}',
    );
    final bearerToken = _pushBearerToken();
    var failed = 0;
    for (final baseUri in endpoints) {
      try {
        await pushApiClient.syncAccessPolicy(
          baseUri: baseUri,
          identity: identity,
          userId: identity.nodeId,
          allowMessagesOnlyFromContacts: snapshot.allowMessagesOnlyFromContacts,
          contactPeerIds: snapshot.contactPeerIds,
          blockedPeerIds: snapshot.blockedPeerIds,
          policyVersion: version,
          updatedAt: snapshot.updatedAt,
          snapshotHash: snapshot.hash,
          bearerToken: bearerToken,
        );
      } catch (error, stackTrace) {
        failed += 1;
        _log(
          'endpoint failed reason=$reason uri=$baseUri error=$error',
          stackTrace: stackTrace,
        );
      }
    }

    if (failed > 0) {
      await _settings.put(_pendingSyncKey, true);
      _log(
        'failed reason=$reason failed=$failed endpoints=${endpoints.length}',
      );
      return;
    }
    await _settings.put(_lastSnapshotHashKey, snapshot.hash);
    await _settings.put(_policyVersionKey, version);
    await _settings.put(_pendingSyncKey, false);
    _log('done reason=$reason version=$version endpoints=${endpoints.length}');
  }

  _AccessPolicySnapshot _buildSnapshot() {
    final accessControl = PeerAccessControlService(
      settingsBox: _settings,
      contactsRepository: ContactsRepository(storage: storage),
    );
    final contacts =
        ContactsRepository(storage: storage)
            .loadAll()
            .map((contact) => contact.peerId.trim())
            .where((peerId) => peerId.isNotEmpty && peerId.length <= 128)
            .toSet()
            .toList(growable: false)
          ..sort();
    final blocked =
        accessControl
            .blockedPeers()
            .map((peer) => peer.peerId.trim())
            .where((peerId) => peerId.isNotEmpty && peerId.length <= 128)
            .toSet()
            .toList(growable: false)
          ..sort();
    final updatedAt = _serverCompatibleIso8601(now());
    final body = <String, dynamic>{
      'userId': identity.nodeId,
      'allowMessagesOnlyFromContacts':
          accessControl.allowMessagesOnlyFromContacts,
      'contactPeerIds': contacts,
      'blockedPeerIds': blocked,
    };
    return _AccessPolicySnapshot(
      allowMessagesOnlyFromContacts:
          accessControl.allowMessagesOnlyFromContacts,
      contactPeerIds: contacts,
      blockedPeerIds: blocked,
      updatedAt: updatedAt,
      hash: sha256.convert(utf8.encode(jsonEncode(body))).toString(),
    );
  }

  List<Uri> _activePushBaseUris() {
    final resolved = resolvePushBaseUris?.call();
    if (resolved != null) {
      final result = <String, Uri>{};
      for (final uri in resolved) {
        if (uri.hasScheme && uri.host.isNotEmpty) {
          result.putIfAbsent(uri.toString(), () => uri);
        }
      }
      if (result.isNotEmpty) {
        return result.values.toList(growable: false);
      }
    }

    final result = <String, Uri>{};
    final envPushUrl = _pushServerUrlDefine.trim();
    if (envPushUrl.isNotEmpty) {
      final parsed = Uri.tryParse(envPushUrl);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        result.putIfAbsent(parsed.toString(), () => parsed);
      }
    }
    for (final endpoint in PushServersService.extractActiveEndpointsFromStorage(
      _settings.get('push_servers'),
    )) {
      final parsed = Uri.tryParse(endpoint);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        result.putIfAbsent(parsed.toString(), () => parsed);
      }
    }
    final legacy = _settings.get('push_server_url');
    if (legacy is String) {
      final parsed = Uri.tryParse(legacy.trim());
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        result.putIfAbsent(parsed.toString(), () => parsed);
      }
    }
    return result.values.toList(growable: false);
  }

  int _readPolicyVersion() {
    final raw = _settings.get(_policyVersionKey);
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw) ?? 0;
    }
    return 0;
  }

  String? _pushBearerToken() {
    final token = _pushApiTokenDefine.trim();
    return token.isEmpty ? null : token;
  }

  void _log(String message, {StackTrace? stackTrace}) {
    AppFileLogger.log('[push_access_policy] $message', stackTrace: stackTrace);
  }

  String _serverCompatibleIso8601(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      utc.millisecondsSinceEpoch,
      isUtc: true,
    ).toIso8601String();
  }
}

class _AccessPolicySnapshot {
  final bool allowMessagesOnlyFromContacts;
  final List<String> contactPeerIds;
  final List<String> blockedPeerIds;
  final String updatedAt;
  final String hash;

  const _AccessPolicySnapshot({
    required this.allowMessagesOnlyFromContacts,
    required this.contactPeerIds,
    required this.blockedPeerIds,
    required this.updatedAt,
    required this.hash,
  });
}
