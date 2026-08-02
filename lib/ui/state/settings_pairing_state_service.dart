import 'dart:async';
import 'dart:convert';

import '../../core/runtime/account_device_event.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/server_config_payload.dart';
import 'settings_controller_models.dart';
import 'settings_pairing_state_repository.dart';

class SettingsPairingStateService {
  static const String pendingAccountPairingRequestKey =
      'pending_account_pairing_request.v1';

  final SettingsPairingStateRepository repository;
  final Future<void> Function(String key, dynamic value) writeSettingValue;
  final Future<void> Function(String key) deleteSettingValue;
  final ServerConfigPayload Function() currentConfiguredServerConfigPayload;
  final Future<void> Function(
    ServerConfigPayload payload, {
    required ServerConfigImportMode mode,
  })
  importServerConfigPayload;
  final String Function() accountId;
  final String Function() deviceId;

  PendingAccountPairingRequest? _pendingAccountPairingRequest;

  SettingsPairingStateService({
    required this.repository,
    required this.writeSettingValue,
    required this.deleteSettingValue,
    required this.currentConfiguredServerConfigPayload,
    required this.importServerConfigPayload,
    required this.accountId,
    required this.deviceId,
  });

  PendingAccountPairingRequest? get pendingAccountPairingRequest =>
      _pendingAccountPairingRequest;

  List<IncomingAccountPairingRequest> get incomingAccountPairingRequests {
    final activeSessionIds = loadActiveAccountPairingSessions()
        .map((item) => item.sessionId)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    return repository.loadIncomingRequests(
      accountPairingIncomingRequestsStorageKey,
      activeSessionIds,
    );
  }

  AccountPairingRequestPayload? get outgoingAccountPairingRequest =>
      repository.loadOutgoingRequest(accountPairingOutgoingRequestStorageKey);

  AccountPairingApprovalPayload? get approvedAccountPairingPayload =>
      repository.loadApprovedPayload(accountPairingApprovedPayloadStorageKey);

  AccountPairingRejectedPayload? get rejectedAccountPairingPayload =>
      repository.loadRejectedPayload(accountPairingRejectedPayloadStorageKey);

  AccountPairingStagedServerConfig? get stagedPairingServerConfig => repository
      .loadStagedServerConfig(accountPairingStagedServerConfigStorageKey);

  List<AccountDeviceEvent> get accountDeviceEvents =>
      repository.loadAccountDeviceEvents(accountDeviceEventsStorageKey);

  List<AccountMembershipUpdatePayload> get incomingAccountMembershipUpdates =>
      repository.loadIncomingMembershipUpdates(
        accountMembershipUpdatesStorageKey,
      );

  Future<void> saveOutgoingRequest(AccountPairingRequestPayload request) {
    return writeSettingValue(
      accountPairingOutgoingRequestStorageKey,
      jsonEncode(request.toJson()),
    );
  }

  Future<void> deleteOutgoingRequest() {
    return deleteSettingValue(accountPairingOutgoingRequestStorageKey);
  }

  Future<void> deleteApprovedPayload() {
    return deleteSettingValue(accountPairingApprovedPayloadStorageKey);
  }

  Future<void> deleteRejectedPayload() {
    return deleteSettingValue(accountPairingRejectedPayloadStorageKey);
  }

  Future<void> deleteStagedServerConfig() {
    return deleteSettingValue(accountPairingStagedServerConfigStorageKey);
  }

  Future<PendingAccountPairingRequest> savePendingRequest(
    AccountPairingPayload payload, {
    int? scannedAtMs,
  }) async {
    final request = PendingAccountPairingRequest(
      payload: payload,
      scannedAtMs: scannedAtMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    _pendingAccountPairingRequest = request;
    await repository.savePendingRequest(
      pendingAccountPairingRequestKey,
      request,
    );
    return request;
  }

  Future<void> clearPendingRequest() async {
    _pendingAccountPairingRequest = null;
    await repository.clearPendingRequest(pendingAccountPairingRequestKey);
  }

  Future<void> restorePendingAccountPairingRequest() async {
    try {
      _pendingAccountPairingRequest = repository.loadPendingRequest(
        pendingAccountPairingRequestKey,
      );
      if (_pendingAccountPairingRequest != null) {
        return;
      }
      _pendingAccountPairingRequest = null;
      return;
    } catch (error, stackTrace) {
      AppFileLogger.log(
        'load pending pairing failed',
        name: 'settings',
        error: error,
        stackTrace: stackTrace,
      );
      _pendingAccountPairingRequest = null;
      await repository.clearPendingRequest(pendingAccountPairingRequestKey);
    }
  }

  Future<void> cleanupExpiredIncomingAccountPairingRequests() {
    final activeSessionIds = loadActiveAccountPairingSessions()
        .map((item) => item.sessionId)
        .where((item) => item.trim().isNotEmpty)
        .toSet();
    return repository.cleanupIncomingRequests(
      accountPairingIncomingRequestsStorageKey,
      activeSessionIds,
    );
  }

  Future<void> stageTemporaryPairingServers(ServerConfigPayload payload) async {
    if (payload.bootstrap.isEmpty &&
        payload.relay.isEmpty &&
        payload.turn.isEmpty) {
      return;
    }
    final snapshot = AccountPairingStagedServerConfig(
      previousServerConfig: currentConfiguredServerConfigPayload(),
      stagedServerConfig: payload,
      stagedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await repository.saveStagedServerConfig(
      accountPairingStagedServerConfigStorageKey,
      snapshot,
    );
    await importServerConfigPayload(
      payload,
      mode: ServerConfigImportMode.merge,
    );
  }

  Future<void> rollbackTemporaryPairingServers() async {
    final staged = stagedPairingServerConfig;
    if (staged == null) {
      return;
    }
    await importServerConfigPayload(
      staged.previousServerConfig,
      mode: ServerConfigImportMode.replace,
    );
    await repository.clearValue(accountPairingStagedServerConfigStorageKey);
  }

  Future<void> removeIncomingAccountPairingRequest(String requestId) {
    return repository.removeIncomingRequest(
      accountPairingIncomingRequestsStorageKey,
      requestId,
      incomingAccountPairingRequests,
    );
  }

  List<AccountPairingPayload> loadActiveAccountPairingSessions() {
    return repository.loadActiveSessions(
      accountPairingActiveSessionsStorageKey,
    );
  }

  void storeActiveAccountPairingSession(AccountPairingPayload payload) {
    unawaited(
      repository.storeActiveSession(
        accountPairingActiveSessionsStorageKey,
        payload,
        loadActiveAccountPairingSessions(),
      ),
    );
  }

  AccountPairingPayload? activeAccountPairingSession(String sessionId) {
    final normalized = sessionId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final session in loadActiveAccountPairingSessions()) {
      if (session.sessionId == normalized) {
        return session;
      }
    }
    return null;
  }

  Future<void> removeActiveAccountPairingSession(String sessionId) {
    return repository.removeActiveSession(
      accountPairingActiveSessionsStorageKey,
      sessionId,
      loadActiveAccountPairingSessions(),
    );
  }

  Future<void> removeIncomingAccountMembershipUpdate(String updateId) {
    return repository.removeIncomingMembershipUpdate(
      accountMembershipUpdatesStorageKey,
      updateId,
      incomingAccountMembershipUpdates,
    );
  }

  Future<void> appendAccountDeviceEvent(
    AccountDeviceEventType type, {
    String? accountIdOverride,
    String? actorDeviceIdOverride,
    String? deviceId,
    String? details,
  }) async {
    final current = accountDeviceEvents.toList(growable: true);
    current.insert(
      0,
      AccountDeviceEvent(
        eventId: 'device-event:${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        accountId: accountIdOverride?.trim().isNotEmpty == true
            ? accountIdOverride!.trim()
            : accountId(),
        deviceId: deviceId?.trim().isNotEmpty == true ? deviceId!.trim() : null,
        actorDeviceId: actorDeviceIdOverride?.trim().isNotEmpty == true
            ? actorDeviceIdOverride!.trim()
            : this.deviceId(),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        details: details,
      ),
    );
    if (current.length > 50) {
      current.removeRange(50, current.length);
    }
    await repository.saveAccountDeviceEvents(
      accountDeviceEventsStorageKey,
      current,
    );
  }
}
