// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/runtime/app_data_cleaner_service.dart';
import 'package:peerlink/core/runtime/push_token_service.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/core/runtime/server_health_coordinator.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/runtime/terms_acceptance_service.dart';
import 'package:peerlink/core/security/account_identity.dart';
import 'package:peerlink/features/settings/application/settings_account_membership_service.dart';
import 'package:peerlink/features/settings/application/settings_controller_models.dart';
import 'package:peerlink/features/settings/application/settings_pairing_flow_service.dart';
import 'package:peerlink/features/settings/application/settings_pairing_state_service.dart';
import 'package:peerlink/features/settings/application/settings_read_model_service.dart';
import 'package:peerlink/features/settings/application/settings_server_config_service.dart';
import 'package:peerlink/features/settings/application/settings_storage_maintenance_service.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';

class SettingsControllerDependencies {
  const SettingsControllerDependencies({
    required this.health,
    required this.dataCleaner,
    required this.pushTokens,
    required this.pairingStateService,
    required this.pairingFlow,
    required this.readModelService,
    required this.serverConfigService,
    required this.storageMaintenanceService,
    required this.accountMembershipService,
    required this.accessControl,
    required this.termsAcceptance,
    required this.contactDisplayName,
  });

  final ServerHealthCoordinator health;
  final AppDataCleanerService dataCleaner;
  final PushTokenService pushTokens;
  final SettingsPairingStateService pairingStateService;
  final SettingsPairingFlowService pairingFlow;
  final SettingsReadModelService readModelService;
  final SettingsServerConfigService serverConfigService;
  final SettingsStorageMaintenanceService storageMaintenanceService;
  final SettingsAccountMembershipService accountMembershipService;
  final PeerAccessControlService accessControl;
  final TermsAcceptanceService termsAcceptance;
  final String Function(String peerId, {String? fallback}) contactDisplayName;
}

typedef SettingsControllerDependenciesFactory =
    SettingsControllerDependencies Function({
      required IdentityApi identity,
      required NetworkApi network,
      required StorageService storage,
      required List<String> Function() connectedBootstrapServers,
      required dynamic Function(String key) readSettingValue,
      required Future<void> Function(String key, dynamic value)
      writeSettingValue,
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
    });
