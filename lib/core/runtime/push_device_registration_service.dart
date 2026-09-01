// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../node/node_facade.dart';
import 'app_file_logger.dart';
import 'push_servers_service.dart';
import 'push_token_service.dart';
import 'storage_service.dart';

typedef PushDeviceTokenRegistrar =
    Future<void> Function(String? token, {bool force});
typedef PushAccessPolicySync =
    Future<void> Function({required String reason, bool force});

class PushDeviceRegistrationService {
  static const _lastRegisterAtMsKey = 'push_device_last_register_at_ms';
  static const _lastRegisterSignatureKey =
      'push_device_last_register_signature';
  static const Duration defaultRefreshInterval = Duration(hours: 24);

  final NodeFacade? facade;
  final StorageService storage;
  final Duration refreshInterval;
  final DateTime Function() now;
  final PushDeviceTokenRegistrar _registerPushDeviceToken;
  final PushAccessPolicySync _syncAccessPolicy;
  final PushAccessPolicySync? _retryPendingAccessPolicySync;
  late final PushTokenService _pushTokens;
  Future<void>? _syncFuture;

  PushDeviceRegistrationService({
    this.facade,
    required this.storage,
    this.refreshInterval = defaultRefreshInterval,
    DateTime Function()? now,
    PushDeviceTokenRegistrar? registerPushDeviceToken,
    PushAccessPolicySync? syncAccessPolicy,
    PushAccessPolicySync? retryPendingAccessPolicySync,
  }) : now = now ?? DateTime.now,
       _registerPushDeviceToken =
           registerPushDeviceToken ??
           ((token, {force = false}) =>
               facade!.registerPushDeviceToken(token, force: force)),
       _syncAccessPolicy =
           syncAccessPolicy ??
           (({required reason, force = false}) =>
               facade!.syncPushAccessPolicy(reason: reason, force: force)),
       _retryPendingAccessPolicySync =
           retryPendingAccessPolicySync ??
           (facade == null
               ? null
               : ({required reason, force = false}) =>
                     facade.retryPendingPushAccessPolicySync(reason: reason)) {
    _pushTokens = PushTokenService(storage: storage);
  }

  SecureStorageBox get _settings => storage.getSettings();

  Future<void> registerIfDue({required String reason, bool force = false}) {
    return syncNow(reason: reason, forceRegister: force, forcePolicy: true);
  }

  Future<void> syncNow({
    required String reason,
    bool forceRegister = false,
    bool forcePolicy = true,
  }) async {
    final current = _syncFuture;
    if (current != null) {
      await current;
    }
    final future = _syncNowImpl(
      reason: reason,
      forceRegister: forceRegister,
      forcePolicy: forcePolicy,
    );
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
    await syncNow(reason: reason, forceRegister: true, forcePolicy: false);
    await _retryPendingAccessPolicySync?.call(reason: reason, force: true);
  }

  Future<void> _syncNowImpl({
    required String reason,
    required bool forceRegister,
    required bool forcePolicy,
  }) async {
    final fcmToken = (_pushTokens.fcmToken ?? '').trim();
    final apnsToken = (_pushTokens.apnsToken ?? '').trim();
    final voipToken = (_pushTokens.voipToken ?? '').trim();
    if (fcmToken.isEmpty && apnsToken.isEmpty) {
      if (forcePolicy) {
        await _syncAccessPolicy(reason: reason, force: true);
      }
      _log('skip register reason=$reason no_token');
      return;
    }

    final endpoints = _activePushEndpoints();
    if (endpoints.isEmpty) {
      if (forcePolicy) {
        await _syncAccessPolicy(reason: reason, force: true);
      }
      _log('skip register reason=$reason no_endpoint');
      return;
    }

    final signature = _buildSignature(
      fcmToken: fcmToken,
      apnsToken: apnsToken,
      voipToken: voipToken,
      endpoints: endpoints,
    );
    final lastSignature = _settings.get(_lastRegisterSignatureKey) as String?;
    final lastAtMs = _readLastRegisterAtMs();
    final nowMs = now().millisecondsSinceEpoch;
    final ttlExpired =
        lastAtMs == null || nowMs - lastAtMs >= refreshInterval.inMilliseconds;
    final signatureChanged = lastSignature != signature;
    if (!forceRegister && !signatureChanged && !ttlExpired) {
      _log('skip register reason=$reason fresh endpoints=${endpoints.length}');
      if (forcePolicy) {
        await _syncAccessPolicy(reason: reason, force: true);
      }
      return;
    }

    _log(
      'start reason=$reason forceRegister=$forceRegister '
      'forcePolicy=$forcePolicy signatureChanged=$signatureChanged '
      'ttlExpired=$ttlExpired endpoints=${endpoints.length}',
    );
    Object? registerError;
    StackTrace? registerStackTrace;
    try {
      await _registerPushDeviceToken(
        fcmToken.isEmpty ? null : fcmToken,
        force: forceRegister || !signatureChanged,
      );
    } catch (error, stackTrace) {
      registerError = error;
      registerStackTrace = stackTrace;
      _log(
        'register failed reason=$reason error=$error',
        stackTrace: stackTrace,
      );
    }
    if (forcePolicy) {
      _log('policy sync start reason=$reason');
      await _syncAccessPolicy(reason: reason, force: true);
      _log('policy sync done reason=$reason');
    }
    if (registerError != null) {
      _log(
        'done with register error reason=$reason endpoints=${endpoints.length}',
        stackTrace: registerStackTrace,
      );
      return;
    }
    await _settings.put(_lastRegisterAtMsKey, nowMs);
    await _settings.put(_lastRegisterSignatureKey, signature);
    _log('done reason=$reason endpoints=${endpoints.length}');
  }

  List<String> _activePushEndpoints() {
    final result = <String>{};
    result.addAll(
      PushServersService.extractActiveEndpointsFromStorage(
        _settings.get('push_servers'),
      ),
    );
    final legacy = _settings.get('push_server_url');
    if (legacy is String) {
      final normalized = PushServersService.normalizeIncomingEndpoint(legacy);
      if (normalized.isNotEmpty) {
        result.add(normalized);
      }
    }
    return result.toList(growable: false)..sort();
  }

  int? _readLastRegisterAtMs() {
    final raw = _settings.get(_lastRegisterAtMsKey);
    if (raw is int) {
      return raw;
    }
    if (raw is String) {
      return int.tryParse(raw);
    }
    return null;
  }

  String _buildSignature({
    required String fcmToken,
    required String apnsToken,
    required String voipToken,
    required List<String> endpoints,
  }) {
    return sha256
        .convert(
          utf8.encode('$fcmToken|$apnsToken|$voipToken|${endpoints.join('|')}'),
        )
        .toString();
  }

  void _log(String message, {StackTrace? stackTrace}) {
    AppFileLogger.log('[push_register] $message', stackTrace: stackTrace);
  }
}
