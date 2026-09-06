// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/runtime/app_data_cleaner_service.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/push_token_service.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/core/runtime/server_health_coordinator.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/runtime/terms_acceptance_service.dart';
import 'package:peerlink/core/security/account_identity.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/settings/application/settings_account_membership_service.dart';
import 'package:peerlink/features/settings/application/settings_controller_dependencies.dart';
import 'package:peerlink/features/settings/application/settings_controller_models.dart';
import 'package:peerlink/features/settings/application/settings_pairing_flow_service.dart';
import 'package:peerlink/features/settings/application/settings_pairing_state_repository.dart';
import 'package:peerlink/features/settings/application/settings_pairing_state_service.dart';
import 'package:peerlink/features/settings/application/settings_read_model_service.dart';
import 'package:peerlink/features/settings/application/settings_server_config_service.dart';
import 'package:peerlink/features/settings/application/settings_storage_maintenance_service.dart';

class SettingsControllerComposition {
  const SettingsControllerComposition._();

  static SettingsControllerDependencies create({
    required IdentityApi identity,
    required NetworkApi network,
    required StorageService storage,
    required List<String> Function() connectedBootstrapServers,
    required dynamic Function(String key) readSettingValue,
    required Future<void> Function(String key, dynamic value) writeSettingValue,
    required Future<void> Function(String key) deleteSettingValue,
    required ServerConfigPayload Function()
    currentConfiguredServerConfigPayload,
    required Future<void> Function(
      ServerConfigPayload payload, {
      required ServerConfigImportMode mode,
    })
    importServerConfigPayload,
    required String Function() peerId,
    required String Function() accountId,
    required String Function() deviceId,
    required String? Function() endpointId,
    required String? Function() fcmTokenHash,
    required AccountIdentity Function() accountIdentity,
    required void Function() ensurePrimaryAccountDeviceForManagement,
    required Future<AccountIdentity> Function({
      required AccountDeviceIdentity requestedDevice,
      required String sessionId,
    })
    issueApprovedPairingAccountIdentity,
    required Future<AccountIdentity> Function(
      AccountIdentity identity, {
      required String expectedSessionId,
      required String expectedAccountId,
    })
    applyApprovedPairingAccountIdentity,
    required Future<void> Function(
      String peerId, {
      required String kind,
      required String text,
    })
    sendAccountPairingControlMessage,
    required Future<AccountIdentity> Function({
      required Iterable<String> revokedDeviceIds,
    })
    issueRevokedAccountIdentity,
    required Future<String> Function({
      required AccountIdentity identity,
      required String action,
      required Iterable<String> affectedDeviceIds,
      required int updatedAtMs,
    })
    signAccountMembershipUpdate,
    required Future<AccountIdentity> Function({
      required AccountIdentity identity,
      required String actorDeviceId,
      required String action,
      required Iterable<String> affectedDeviceIds,
      required int updatedAtMs,
      required String signature,
    })
    applyAccountMembershipUpdate,
  }) {
    final health = ServerHealthCoordinator(facade: network, storage: storage);
    final dataCleaner = AppDataCleanerService(
      identity: identity,
      storage: storage,
    );
    final contactsRepository = ContactsRepository(storage: storage);
    final accessControl = PeerAccessControlService(
      settingsBox: storage.getSettings(),
      contactsRepository: contactsRepository,
    );
    final serverConfigService = SettingsServerConfigService(health: health);
    final pairingStateRepository = SettingsPairingStateRepository(
      read: readSettingValue,
      write: writeSettingValue,
      delete: deleteSettingValue,
    );
    final pairingStateService = SettingsPairingStateService(
      repository: pairingStateRepository,
      writeSettingValue: writeSettingValue,
      deleteSettingValue: deleteSettingValue,
      currentConfiguredServerConfigPayload:
          currentConfiguredServerConfigPayload,
      importServerConfigPayload: importServerConfigPayload,
      accountId: accountId,
      deviceId: deviceId,
    );
    final pairingFlow = SettingsPairingFlowService(
      peerId: peerId,
      accountId: accountId,
      deviceId: deviceId,
      endpointId: endpointId,
      fcmTokenHash: fcmTokenHash,
      accountIdentity: accountIdentity,
      loadOutgoingRequest: () =>
          pairingStateService.outgoingAccountPairingRequest,
      loadApprovedPayload: () =>
          pairingStateService.approvedAccountPairingPayload,
      loadRejectedPayload: () =>
          pairingStateService.rejectedAccountPairingPayload,
      loadPendingRequest: () =>
          pairingStateService.pendingAccountPairingRequest,
      stageTemporaryPairingServers:
          pairingStateService.stageTemporaryPairingServers,
      rollbackTemporaryPairingServers:
          pairingStateService.rollbackTemporaryPairingServers,
      saveOutgoingRequest: pairingStateService.saveOutgoingRequest,
      deleteOutgoingRequest: pairingStateService.deleteOutgoingRequest,
      deleteApprovedPayload: pairingStateService.deleteApprovedPayload,
      deleteRejectedPayload: pairingStateService.deleteRejectedPayload,
      deleteStagedServerConfig: pairingStateService.deleteStagedServerConfig,
      issueApprovedPairingAccountIdentity: issueApprovedPairingAccountIdentity,
      applyApprovedPairingAccountIdentity: applyApprovedPairingAccountIdentity,
      sendAccountPairingControlMessage: sendAccountPairingControlMessage,
      appendAccountDeviceEvent: pairingStateService.appendAccountDeviceEvent,
      signAccountMembershipUpdate: signAccountMembershipUpdate,
      findActiveSession: pairingStateService.activeAccountPairingSession,
      removeActiveSession:
          pairingStateService.removeActiveAccountPairingSession,
      removeIncomingRequest:
          pairingStateService.removeIncomingAccountPairingRequest,
      savePendingRequest: pairingStateService.savePendingRequest,
      clearPendingRequest: pairingStateService.clearPendingRequest,
      onMembershipUpdateSendFailed: (peerId, error, stackTrace) {
        AppFileLogger.log(
          'account membership update send failed peerId=$peerId error=$error',
          name: 'account_membership',
          stackTrace: stackTrace,
        );
      },
      pairingTimeout: const Duration(minutes: 5),
    );
    final accountMembershipService = SettingsAccountMembershipService(
      deviceId: deviceId,
      accountId: accountId,
      accountIdentity: accountIdentity,
      ensurePrimaryAccountDeviceForManagement:
          ensurePrimaryAccountDeviceForManagement,
      issueRevokedAccountIdentity: issueRevokedAccountIdentity,
      signAccountMembershipUpdate: signAccountMembershipUpdate,
      applyAccountMembershipUpdate: applyAccountMembershipUpdate,
      sendAccountPairingControlMessage: sendAccountPairingControlMessage,
      sendAccountMembershipUpdatePushEvent:
          network.sendAccountMembershipUpdatePushEvent,
      appendAccountDeviceEvent: pairingStateService.appendAccountDeviceEvent,
      loadIncomingAccountMembershipUpdates: () =>
          pairingStateService.incomingAccountMembershipUpdates,
      removeIncomingAccountMembershipUpdate:
          pairingStateService.removeIncomingAccountMembershipUpdate,
    );
    return SettingsControllerDependencies(
      health: health,
      dataCleaner: dataCleaner,
      pushTokens: PushTokenService(storage: storage),
      pairingStateService: pairingStateService,
      pairingFlow: pairingFlow,
      readModelService: SettingsReadModelService(
        health: health,
        connectedBootstrapServers: connectedBootstrapServers,
      ),
      serverConfigService: serverConfigService,
      storageMaintenanceService: SettingsStorageMaintenanceService(
        dataCleaner: dataCleaner,
        serverConfigService: serverConfigService,
        loadStorageBreakdownImpl: storage.computeAppStorageBreakdown,
      ),
      accountMembershipService: accountMembershipService,
      accessControl: accessControl,
      termsAcceptance: TermsAcceptanceService(
        settingsBox: storage.getSettings(),
      ),
      contactDisplayName: contactsRepository.displayName,
    );
  }
}
