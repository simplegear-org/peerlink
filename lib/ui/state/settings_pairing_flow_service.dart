import 'dart:convert';

import '../../core/runtime/account_device_event.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/server_config_payload.dart';
import '../../core/security/account_identity.dart';
import 'settings_controller_models.dart';

typedef PairingSendControlMessage =
    Future<void> Function(
      String peerId, {
      required String kind,
      required String text,
    });
typedef PairingAppendDeviceEvent =
    Future<void> Function(
      AccountDeviceEventType type, {
      String? accountIdOverride,
      String? actorDeviceIdOverride,
      String? deviceId,
      String? details,
    });
typedef PairingSignMembershipUpdate =
    Future<String> Function({
      required AccountIdentity identity,
      required String action,
      required Iterable<String> affectedDeviceIds,
      required int updatedAtMs,
    });
typedef PairingMembershipUpdateSendFailed =
    void Function(String peerId, Object error, StackTrace stackTrace);

class SettingsPairingFlowService {
  const SettingsPairingFlowService({
    required this.peerId,
    required this.accountId,
    required this.deviceId,
    required this.endpointId,
    required this.fcmTokenHash,
    required this.accountIdentity,
    required this.loadOutgoingRequest,
    required this.loadApprovedPayload,
    required this.loadRejectedPayload,
    required this.loadPendingRequest,
    required this.stageTemporaryPairingServers,
    required this.rollbackTemporaryPairingServers,
    required this.saveOutgoingRequest,
    required this.deleteOutgoingRequest,
    required this.deleteApprovedPayload,
    required this.deleteRejectedPayload,
    required this.deleteStagedServerConfig,
    required this.issueApprovedPairingAccountIdentity,
    required this.applyApprovedPairingAccountIdentity,
    required this.sendAccountPairingControlMessage,
    required this.appendAccountDeviceEvent,
    required this.signAccountMembershipUpdate,
    required this.onMembershipUpdateSendFailed,
    required this.findActiveSession,
    required this.removeActiveSession,
    required this.removeIncomingRequest,
    required this.savePendingRequest,
    required this.clearPendingRequest,
    required this.pairingTimeout,
  });

  final String Function() peerId;
  final String Function() accountId;
  final String Function() deviceId;
  final String? Function() endpointId;
  final String? Function() fcmTokenHash;
  final AccountIdentity Function() accountIdentity;
  final AccountPairingRequestPayload? Function() loadOutgoingRequest;
  final AccountPairingApprovalPayload? Function() loadApprovedPayload;
  final AccountPairingRejectedPayload? Function() loadRejectedPayload;
  final PendingAccountPairingRequest? Function() loadPendingRequest;
  final Future<void> Function(ServerConfigPayload payload)
  stageTemporaryPairingServers;
  final Future<void> Function() rollbackTemporaryPairingServers;
  final Future<void> Function(AccountPairingRequestPayload request)
  saveOutgoingRequest;
  final Future<void> Function() deleteOutgoingRequest;
  final Future<void> Function() deleteApprovedPayload;
  final Future<void> Function() deleteRejectedPayload;
  final Future<void> Function() deleteStagedServerConfig;
  final Future<AccountIdentity> Function({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  })
  issueApprovedPairingAccountIdentity;
  final Future<AccountIdentity> Function(
    AccountIdentity identity, {
    required String expectedSessionId,
    required String expectedAccountId,
  })
  applyApprovedPairingAccountIdentity;
  final PairingSendControlMessage sendAccountPairingControlMessage;
  final PairingAppendDeviceEvent appendAccountDeviceEvent;
  final PairingSignMembershipUpdate signAccountMembershipUpdate;
  final PairingMembershipUpdateSendFailed onMembershipUpdateSendFailed;
  final AccountPairingPayload? Function(String sessionId) findActiveSession;
  final Future<void> Function(String sessionId) removeActiveSession;
  final Future<void> Function(String requestId) removeIncomingRequest;
  final Future<PendingAccountPairingRequest> Function(
    AccountPairingPayload payload, {
    int? scannedAtMs,
  })
  savePendingRequest;
  final Future<void> Function() clearPendingRequest;
  final Duration pairingTimeout;

  Future<AccountPairingRequestPayload> requestAccountPairingPayload(
    AccountPairingPayload payload,
  ) async {
    final currentDevice = accountIdentity().deviceById(deviceId());
    if (currentDevice == null) {
      throw StateError('Current device identity is missing');
    }
    if (payload.isExpired) {
      throw const FormatException('QR привязки устройства уже истек');
    }
    final request = AccountPairingRequestPayload(
      requestId: 'pair:${DateTime.now().microsecondsSinceEpoch}',
      sessionId: payload.sessionId,
      targetAccountId: payload.accountId,
      targetDeviceId: payload.targetDeviceId,
      requesterPeerId: peerId(),
      requesterAccountId: accountId(),
      requesterDeviceId: deviceId(),
      requesterDisplayName: accountIdentity().displayName,
      requesterSigningPublicKey: currentDevice.signingPublicKey ?? '',
      requesterAgreementPublicKey: currentDevice.agreementPublicKey ?? '',
      requesterEndpointId: endpointId(),
      requesterFcmTokenHash: fcmTokenHash(),
      requestedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    if (request.requesterSigningPublicKey.isEmpty ||
        request.requesterAgreementPublicKey.isEmpty) {
      throw const FormatException('На устройстве нет identity-ключей pairing');
    }
    await stageTemporaryPairingServers(payload.serverConfig);
    await saveOutgoingRequest(request);
    try {
      await sendAccountPairingControlMessage(
        payload.targetPeerId,
        kind: 'accountPairRequest',
        text: jsonEncode(request.toJson()),
      );
      await appendAccountDeviceEvent(
        AccountDeviceEventType.pairingRequestSent,
        deviceId: request.requesterDeviceId,
        details: 'session=${request.sessionId}',
      );
    } catch (_) {
      await rollbackTemporaryPairingServers();
      await deleteOutgoingRequest();
      rethrow;
    }
    return request;
  }

  Future<void> approveIncomingAccountPairingRequest(
    IncomingAccountPairingRequest request,
  ) async {
    final previousIdentity = accountIdentity();
    final session = findActiveSession(request.payload.sessionId);
    if (session == null) {
      throw const FormatException('Pairing session not found or already used');
    }
    if (session.isExpired) {
      await removeActiveSession(session.sessionId);
      throw const FormatException('QR привязки устройства уже истек');
    }
    if (session.targetDeviceId != deviceId()) {
      throw const FormatException(
        'Pairing request is addressed to another trusted device',
      );
    }
    if (request.payload.targetAccountId != session.accountId ||
        request.payload.targetDeviceId != session.targetDeviceId) {
      throw const FormatException('Pairing request does not match session QR');
    }
    final requestedDevice = AccountDeviceIdentity(
      deviceId: request.payload.requesterDeviceId,
      peerId: request.payload.requesterPeerId,
      signingPublicKey: request.payload.requesterSigningPublicKey,
      agreementPublicKey: request.payload.requesterAgreementPublicKey,
      endpointId: request.payload.requesterEndpointId,
      fcmTokenHash: request.payload.requesterFcmTokenHash,
      createdAtMs: request.payload.requestedAtMs,
      updatedAtMs: request.payload.requestedAtMs,
      isCurrentDevice: false,
    );
    final approvedIdentity = await issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice,
      sessionId: request.payload.sessionId,
    );
    final payload = AccountPairingApprovalPayload(
      requestId: request.payload.requestId,
      sessionId: request.payload.sessionId,
      accountIdentity: approvedIdentity.withCurrentDevice(deviceId()),
      serverConfig: session.serverConfig,
      approvedAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final membershipUpdatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final membershipSignature = await signAccountMembershipUpdate(
      identity: approvedIdentity,
      action: AccountMembershipUpdatePayload.addDevicesAction,
      affectedDeviceIds: <String>[requestedDevice.deviceId],
      updatedAtMs: membershipUpdatedAtMs,
    );
    final membershipPayload = AccountMembershipUpdatePayload(
      updateId: 'account-update:${DateTime.now().microsecondsSinceEpoch}',
      accountId: previousIdentity.accountId,
      actorDeviceId: deviceId(),
      action: AccountMembershipUpdatePayload.addDevicesAction,
      affectedDeviceIds: <String>[requestedDevice.deviceId],
      accountIdentity: approvedIdentity.withCurrentDevice(deviceId()),
      updatedAtMs: membershipUpdatedAtMs,
      signature: membershipSignature,
    );
    await sendAccountPairingControlMessage(
      request.sourcePeerId,
      kind: 'accountPairApproval',
      text: jsonEncode(payload.toJson()),
    );
    final membershipRecipients = previousIdentity.devices
        .where(
          (device) =>
              device.deviceId != deviceId() &&
              device.deviceId != requestedDevice.deviceId,
        )
        .map((device) => device.peerId.trim())
        .where((peerId) => peerId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    for (final peerId in membershipRecipients) {
      try {
        await sendAccountPairingControlMessage(
          peerId,
          kind: 'accountMembershipUpdate',
          text: jsonEncode(membershipPayload.toJson()),
        );
      } catch (error, stackTrace) {
        onMembershipUpdateSendFailed(peerId, error, stackTrace);
      }
    }
    await appendAccountDeviceEvent(
      AccountDeviceEventType.pairingApproved,
      deviceId: requestedDevice.deviceId,
      details: 'session=${request.payload.sessionId}',
    );
    await appendAccountDeviceEvent(
      AccountDeviceEventType.deviceAdded,
      deviceId: requestedDevice.deviceId,
      details: 'session=${request.payload.sessionId}',
    );
    await removeActiveSession(session.sessionId);
    await removeIncomingRequest(request.payload.requestId);
  }

  Future<void> rejectIncomingAccountPairingRequest(
    String requestId,
    List<IncomingAccountPairingRequest> incomingRequests,
  ) async {
    IncomingAccountPairingRequest? request;
    for (final item in incomingRequests) {
      if (item.payload.requestId == requestId) {
        request = item;
        break;
      }
    }
    if (request != null) {
      final payload = AccountPairingRejectedPayload(
        requestId: requestId,
        sessionId: request.payload.sessionId,
        rejectedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      await sendAccountPairingControlMessage(
        request.sourcePeerId,
        kind: 'accountPairRejection',
        text: jsonEncode(payload.toJson()),
      );
      await appendAccountDeviceEvent(
        AccountDeviceEventType.pairingRejected,
        deviceId: request.payload.requesterDeviceId,
        details: 'session=${request.payload.sessionId}',
      );
      await removeActiveSession(request.payload.sessionId);
    }
    await removeIncomingRequest(requestId);
  }

  Future<AccountIdentity?> applyApprovedAccountPairingIfAvailable() async {
    final approval = loadApprovedPayload();
    final outgoing = loadOutgoingRequest();
    if (approval == null || outgoing == null) {
      return null;
    }
    if (approval.requestId != outgoing.requestId ||
        approval.sessionId != outgoing.sessionId) {
      return null;
    }
    final identity = await applyApprovedPairingAccountIdentity(
      approval.accountIdentity,
      expectedSessionId: outgoing.sessionId,
      expectedAccountId: outgoing.targetAccountId,
    );
    await appendAccountDeviceEvent(
      AccountDeviceEventType.deviceAdded,
      deviceId: deviceId(),
      details: 'session=${outgoing.sessionId}',
    );
    await deleteApprovedPayload();
    await deleteOutgoingRequest();
    await deleteRejectedPayload();
    await deleteStagedServerConfig();
    return identity;
  }

  Future<bool> consumeRejectedAccountPairingIfAvailable() async {
    final rejection = loadRejectedPayload();
    final outgoing = loadOutgoingRequest();
    if (rejection == null || outgoing == null) {
      return false;
    }
    if (rejection.requestId != outgoing.requestId ||
        rejection.sessionId != outgoing.sessionId) {
      return false;
    }
    await rollbackTemporaryPairingServers();
    await deleteRejectedPayload();
    await deleteOutgoingRequest();
    return true;
  }

  Future<bool> expireStaleOutgoingAccountPairingIfNeeded() async {
    final outgoing = loadOutgoingRequest();
    if (outgoing == null) {
      return false;
    }
    final requestedAt = DateTime.fromMillisecondsSinceEpoch(
      outgoing.requestedAtMs,
    );
    if (DateTime.now().difference(requestedAt) < pairingTimeout) {
      return false;
    }
    await rollbackTemporaryPairingServers();
    await deleteOutgoingRequest();
    await deleteApprovedPayload();
    await deleteRejectedPayload();
    return true;
  }

  Future<PendingAccountPairingRequest> stageAccountPairingPayload(
    AccountPairingPayload payload, {
    int? scannedAtMs,
  }) {
    return savePendingRequest(payload, scannedAtMs: scannedAtMs);
  }

  Future<AccountPairingRequestPayload> approvePendingAccountPairing() async {
    final request = loadPendingRequest();
    if (request == null) {
      throw StateError('Нет ожидающей привязки устройства');
    }
    final response = await requestAccountPairingPayload(request.payload);
    await clearPendingRequest();
    return response;
  }
}
