// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../calls/call_service.dart';
import '../push/push_api_client.dart';
import '../push/push_event_factory.dart';
import '../push/push_event_service.dart';
import '../push/push_runtime_metadata_builder.dart';
import '../relay/relay_server_status.dart';
import '../runtime/moderation_api_client.dart';
import '../runtime/moderation_delivery_service.dart';
import '../runtime/moderation_policy_service.dart';
import '../runtime/push_access_policy_sync_service.dart';
import '../runtime/push_device_registration_service.dart';
import '../runtime/push_server_sharing_preferences.dart';
import '../runtime/push_token_service.dart';
import '../runtime/storage_service.dart';
import '../security/identity_service.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_server_config.dart';
import 'mesh_call_push_helper.dart';
import 'mesh_peer_transports.dart';
import 'mesh_signal_router.dart';

typedef MeshEnsurePeerSession =
    Future<void> Function(String peerId, {required bool initiateDial});

class MeshNodeRuntimeAdapterContext {
  const MeshNodeRuntimeAdapterContext({
    required this.identity,
    required this.calls,
    required this.storage,
    required this.settingsBox,
    required this.pushApiClient,
    required this.turnAllocator,
    required this.resolvePushBaseUris,
    required this.pushBearerToken,
    required this.platformName,
    required this.log,
    required this.configuredBootstrapServers,
    required this.connectedBootstrapServers,
    required this.activeBootstrapServer,
    required this.relayServerStatuses,
    required this.turnServers,
    required this.connectedTargetBootstrapServersForPeer,
    required this.ensurePeerSession,
    required this.getPeerTransports,
  });

  final IdentityService identity;
  final CallService calls;
  final StorageService storage;
  final SecureStorageBox settingsBox;
  final PushApiClient pushApiClient;
  final TurnAllocator turnAllocator;
  final List<Uri> Function() resolvePushBaseUris;
  final String? Function() pushBearerToken;
  final String Function() platformName;
  final void Function(String message) log;
  final List<String> Function() configuredBootstrapServers;
  final List<String> Function() connectedBootstrapServers;
  final String? Function() activeBootstrapServer;
  final List<RelayServerStatus> Function() relayServerStatuses;
  final List<TurnServerConfig> Function() turnServers;
  final List<String> Function(String peerId)
  connectedTargetBootstrapServersForPeer;
  final MeshEnsurePeerSession ensurePeerSession;
  final MeshPeerTransports? Function(String peerId) getPeerTransports;
}

class MeshNodeRuntimeAdapters {
  const MeshNodeRuntimeAdapters({
    required this.callPush,
    required this.signalRouter,
    required this.pushEventFactory,
    required this.pushEventService,
    required this.pushRuntimeMetadataBuilder,
    required this.pushAccessPolicySync,
    required this.pushDeviceSync,
    required this.moderationDelivery,
  });

  final MeshCallPushHelper callPush;
  final MeshSignalRouter signalRouter;
  final PushEventFactory pushEventFactory;
  final PushEventService pushEventService;
  final PushRuntimeMetadataBuilder pushRuntimeMetadataBuilder;
  final PushAccessPolicySyncService pushAccessPolicySync;
  final PushDeviceRegistrationService pushDeviceSync;
  final ModerationDeliveryService moderationDelivery;
}

abstract interface class MeshNodeRuntimeAdapterFactory {
  MeshNodeRuntimeAdapters create(MeshNodeRuntimeAdapterContext context);
}

class DefaultMeshNodeRuntimeAdapterFactory
    implements MeshNodeRuntimeAdapterFactory {
  const DefaultMeshNodeRuntimeAdapterFactory();

  @override
  MeshNodeRuntimeAdapters create(MeshNodeRuntimeAdapterContext context) {
    final pushTokens = PushTokenService(storage: context.storage);
    const pushEventFactory = PushEventFactory();
    final pushEventService = PushEventService(
      identity: context.identity,
      pushApiClient: context.pushApiClient,
      resolvePushBaseUris: context.resolvePushBaseUris,
      pushBearerToken: context.pushBearerToken,
      log: context.log,
    );
    final pushAccessPolicySync = PushAccessPolicySyncService(
      identity: context.identity,
      storage: context.storage,
      pushApiClient: context.pushApiClient,
      resolvePushBaseUris: context.resolvePushBaseUris,
    );
    final moderationDelivery = ModerationDeliveryService(
      identity: context.identity,
      apiClient: const ModerationApiClient(),
      policyService: ModerationPolicyService(settingsBox: context.settingsBox),
      resolvePushBaseUris: context.resolvePushBaseUris,
      log: context.log,
    );
    final pushRuntimeMetadataBuilder = PushRuntimeMetadataBuilder(
      configuredBootstrapServers: context.configuredBootstrapServers,
      connectedBootstrapServers: context.connectedBootstrapServers,
      activeBootstrapServer: context.activeBootstrapServer,
      relayServerStatuses: context.relayServerStatuses,
      activePushBaseUris: context.resolvePushBaseUris,
      turnServers: context.turnServers,
      isTurnServerHealthy: context.turnAllocator.isHealthy,
      connectedTargetBootstrapServersForPeer:
          context.connectedTargetBootstrapServersForPeer,
      healthyOrderedTurnServerConfigs: () =>
          context.turnAllocator.healthyOrderedServerConfigs,
      shareServersInPush: () =>
          PushServerSharingPreferences.shareOutgoingServers(
            context.settingsBox,
          ),
      log: context.log,
    );
    final callPush = MeshCallPushHelper(
      identity: context.identity,
      pushApiClient: context.pushApiClient,
      pushTokens: pushTokens,
      resolvePushBaseUris: context.resolvePushBaseUris,
      pushBearerToken: context.pushBearerToken,
      pushEventFactory: pushEventFactory,
      pushEventService: pushEventService,
      pushRuntimeMetadataBuilder: pushRuntimeMetadataBuilder,
      platformName: context.platformName,
      callerDisplayName: () => _localProfileDisplayName(context.settingsBox),
      log: context.log,
    );
    final pushDeviceSync = PushDeviceRegistrationService(
      storage: context.storage,
      registerPushDeviceToken: callPush.registerPushDeviceToken,
      syncAccessPolicy: pushAccessPolicySync.syncNow,
      retryPendingAccessPolicySync: ({required reason, force = false}) =>
          pushAccessPolicySync.retryPending(reason: reason),
    );
    final signalRouter = MeshSignalRouter(
      selfPeerId: context.identity.nodeId,
      calls: context.calls,
      ensurePeerSession: context.ensurePeerSession,
      getPeerTransports: context.getPeerTransports,
      log: context.log,
    );

    return MeshNodeRuntimeAdapters(
      callPush: callPush,
      signalRouter: signalRouter,
      pushEventFactory: pushEventFactory,
      pushEventService: pushEventService,
      pushRuntimeMetadataBuilder: pushRuntimeMetadataBuilder,
      pushAccessPolicySync: pushAccessPolicySync,
      pushDeviceSync: pushDeviceSync,
      moderationDelivery: moderationDelivery,
    );
  }
}

String? _localProfileDisplayName(SecureStorageBox settings) {
  final profile = settings.get('peerlink.profile.v1');
  final name = profile is Map
      ? profile['displayName']?.toString().trim()
      : null;
  if (name != null && name.isNotEmpty) {
    return name;
  }
  final legacy = settings
      .get('peerlink.profile.invite_username.v1')
      ?.toString()
      .trim();
  return legacy?.isNotEmpty == true ? legacy : null;
}
