import 'dart:convert';

import '../../core/node/node_facade.dart';
import '../../core/runtime/account_device_event.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/security/account_identity.dart';

class SettingsAccountMembershipService {
  final NodeFacade facade;
  final String Function() deviceId;
  final String Function() accountId;
  final AccountIdentity Function() accountIdentity;
  final void Function() ensurePrimaryAccountDeviceForManagement;
  final Future<AccountIdentity> Function({
    required Iterable<String> revokedDeviceIds,
  })
  issueRevokedAccountIdentity;
  final Future<String> Function({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  })
  signAccountMembershipUpdate;
  final Future<AccountIdentity> Function({
    required AccountIdentity identity,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  })
  applyAccountMembershipUpdate;
  final Future<void> Function(
    String peerId, {
    required String kind,
    required String text,
  })
  sendAccountPairingControlMessage;
  final Future<void> Function(
    AccountDeviceEventType type, {
    String? accountIdOverride,
    String? actorDeviceIdOverride,
    String? deviceId,
    String? details,
  })
  appendAccountDeviceEvent;
  final List<AccountMembershipUpdatePayload> Function()
  loadIncomingAccountMembershipUpdates;
  final Future<void> Function(String updateId)
  removeIncomingAccountMembershipUpdate;

  const SettingsAccountMembershipService({
    required this.facade,
    required this.deviceId,
    required this.accountId,
    required this.accountIdentity,
    required this.ensurePrimaryAccountDeviceForManagement,
    required this.issueRevokedAccountIdentity,
    required this.signAccountMembershipUpdate,
    required this.applyAccountMembershipUpdate,
    required this.sendAccountPairingControlMessage,
    required this.appendAccountDeviceEvent,
    required this.loadIncomingAccountMembershipUpdates,
    required this.removeIncomingAccountMembershipUpdate,
  });

  Future<void> revokeAccountDevice(String targetDeviceId) {
    return revokeAccountDevices(<String>[targetDeviceId]);
  }

  Future<void> revokeAllOtherAccountDevices() {
    final revoked = accountIdentity().devices
        .map((device) => device.deviceId)
        .where((item) => item != deviceId())
        .toList(growable: false);
    return revokeAccountDevices(revoked);
  }

  Future<void> revokeAccountDevices(Iterable<String> targetDeviceIds) async {
    ensurePrimaryAccountDeviceForManagement();
    final currentDeviceId = deviceId();
    final previousIdentity = accountIdentity();
    final revokedDeviceIds = targetDeviceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != currentDeviceId)
        .toSet()
        .toList(growable: false);
    if (revokedDeviceIds.isEmpty) {
      return;
    }
    final updatedIdentity = await issueRevokedAccountIdentity(
      revokedDeviceIds: revokedDeviceIds,
    );
    final updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    final signature = await signAccountMembershipUpdate(
      identity: updatedIdentity,
      action: AccountMembershipUpdatePayload.revokeDevicesAction,
      affectedDeviceIds: revokedDeviceIds,
      updatedAtMs: updatedAtMs,
    );
    final payload = AccountMembershipUpdatePayload(
      updateId: 'account-update:${DateTime.now().microsecondsSinceEpoch}',
      accountId: previousIdentity.accountId,
      actorDeviceId: currentDeviceId,
      action: AccountMembershipUpdatePayload.revokeDevicesAction,
      affectedDeviceIds: revokedDeviceIds,
      accountIdentity: updatedIdentity.withCurrentDevice(currentDeviceId),
      updatedAtMs: updatedAtMs,
      signature: signature,
    );
    final recipientPeerIds = previousIdentity.devices
        .where((device) => device.deviceId != currentDeviceId)
        .map((device) => device.peerId.trim())
        .where((peerId) => peerId.isNotEmpty)
        .toSet()
        .toList(growable: false);
    for (final peerId in recipientPeerIds) {
      try {
        await sendAccountPairingControlMessage(
          peerId,
          kind: 'accountMembershipUpdate',
          text: jsonEncode(payload.toJson()),
        );
      } catch (error, stackTrace) {
        AppFileLogger.log(
          'account membership update send failed peerId=$peerId error=$error',
          name: 'account_membership',
          stackTrace: stackTrace,
        );
      }
      try {
        await facade.sendAccountMembershipUpdatePushEvent(
          directPeerId: peerId,
          update: payload,
        );
      } catch (error, stackTrace) {
        AppFileLogger.log(
          'account membership update push send failed peerId=$peerId error=$error',
          name: 'account_membership',
          stackTrace: stackTrace,
        );
      }
    }
    for (final revokedDeviceId in revokedDeviceIds) {
      await appendAccountDeviceEvent(
        AccountDeviceEventType.deviceRemoved,
        deviceId: revokedDeviceId,
        details: 'actor=$currentDeviceId',
      );
    }
  }

  Future<int> applyIncomingAccountMembershipUpdatesIfAvailable() async {
    final updates = loadIncomingAccountMembershipUpdates();
    if (updates.isEmpty) {
      return 0;
    }
    var applied = 0;
    for (final update in updates) {
      try {
        final previousAccountId = accountId();
        await applyAccountMembershipUpdate(
          identity: update.accountIdentity,
          actorDeviceId: update.actorDeviceId,
          action: update.action,
          affectedDeviceIds: update.affectedDeviceIds,
          updatedAtMs: update.updatedAtMs,
          signature: update.signature,
        );
        for (final revokedDeviceId in update.affectedDeviceIds) {
          await appendAccountDeviceEvent(
            AccountDeviceEventType.deviceRemoved,
            accountIdOverride: previousAccountId,
            actorDeviceIdOverride: update.actorDeviceId,
            deviceId: revokedDeviceId,
            details: 'update=${update.updateId}',
          );
        }
        applied++;
      } catch (error, stackTrace) {
        AppFileLogger.log(
          'account membership update apply failed updateId=${update.updateId} error=$error',
          name: 'account_membership',
          stackTrace: stackTrace,
        );
      } finally {
        await removeIncomingAccountMembershipUpdate(update.updateId);
      }
    }
    return applied;
  }
}
