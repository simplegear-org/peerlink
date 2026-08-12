import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../node/node_facade.dart';
import 'app_file_logger.dart';
import 'push_servers_service.dart';
import 'push_token_service.dart';
import 'storage_service.dart';

class PushDeviceRegistrationService {
  static const _lastRegisterAtMsKey = 'push_device_last_register_at_ms';
  static const _lastRegisterSignatureKey =
      'push_device_last_register_signature';
  static const Duration defaultRefreshInterval = Duration(hours: 24);

  final NodeFacade facade;
  final StorageService storage;
  final Duration refreshInterval;
  final DateTime Function() now;
  late final PushTokenService _pushTokens;

  PushDeviceRegistrationService({
    required this.facade,
    required this.storage,
    this.refreshInterval = defaultRefreshInterval,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    _pushTokens = PushTokenService(storage: storage);
  }

  SecureStorageBox get _settings => storage.getSettings();

  Future<void> registerIfDue({
    required String reason,
    bool force = false,
  }) async {
    final fcmToken = (_pushTokens.fcmToken ?? '').trim();
    final apnsToken = (_pushTokens.apnsToken ?? '').trim();
    final voipToken = (_pushTokens.voipToken ?? '').trim();
    if (fcmToken.isEmpty && apnsToken.isEmpty) {
      _log('skip reason=$reason no_token');
      return;
    }

    final endpoints = _activePushEndpoints();
    if (endpoints.isEmpty) {
      _log('skip reason=$reason no_endpoint');
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
    if (!force && !signatureChanged && !ttlExpired) {
      _log('skip reason=$reason fresh endpoints=${endpoints.length}');
      return;
    }

    _log(
      'start reason=$reason force=$force signatureChanged=$signatureChanged '
      'ttlExpired=$ttlExpired endpoints=${endpoints.length}',
    );
    await facade.registerPushDeviceToken(
      fcmToken.isEmpty ? null : fcmToken,
      force: force || !signatureChanged,
    );
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

  void _log(String message) {
    AppFileLogger.log('[push_register] $message');
  }
}
