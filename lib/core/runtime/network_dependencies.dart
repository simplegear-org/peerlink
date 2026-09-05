// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:typed_data';

import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'storage_service.dart';
import '../security/identity_service.dart';
import '../security/session_crypto.dart';
import '../security/signature_service.dart';
import '../security/session_manager.dart';
import '../calls/call_service.dart';
import '../transport/transport_manager.dart';
import '../overlay/overlay_router.dart';
import '../messaging/reliable_messaging_service.dart';
import '../messaging/chat_service.dart';
import '../dht/routing_table.dart';
import '../dht/record_store.dart';
import '../dht/rpc/kademlia_protocol.dart';
import '../dht/dht_transport.dart';
import '../node/mesh_node.dart';
import '../node/mesh_node_runtime_adapters.dart';
import '../node/node_facade.dart';
import '../node/reliable_call_control_adapter.dart';
import '../push/push_api_client.dart';
import '../relay/http_relay_client.dart';
import '../signaling/bootstrap_signaling_models.dart';
import '../signaling/multi_bootstrap_signaling_service.dart';
import '../turn/turn_allocator.dart';
import 'server_health_coordinator.dart';
import 'network_event_bus.dart';
import 'push_token_service.dart';
import 'contacts_repository.dart';
import 'peer_access_control_service.dart';
import 'runtime_servers_merge_orchestrator.dart';

/// Сборка и wiring всех сетевых зависимостей приложения.
class NetworkDependencies {
  final int instanceId = identityHashCode(Object());
  late final NetworkEventBus eventBus;
  late final MeshNode node;
  late final NodeFacade nodeFacade;
  late final StorageService storage;

  NetworkDependencies._();

  /// Фабричный метод создания и инициализации dependency graph.
  static Future<NetworkDependencies> create({
    required StorageService storage,
  }) async {
    final deps = NetworkDependencies._();
    deps.storage = storage;
    AppFileLogger.log('[network] create:new instance=${deps.instanceId}');
    await deps._initialize();
    return deps;
  }

  /// Инициализирует core-сервисы и связывает их в единый runtime.
  Future<void> _initialize() async {
    try {
      AppFileLogger.log('[network] initialize:start instance=$instanceId');
      eventBus = NetworkEventBus();
      AppFileLogger.log('[network] eventBus:ready');
      await storage.init();

      // ============================
      // CORE SERVICES
      // ============================

      AppFileLogger.log('[network] creating IdentityService');
      final identity = IdentityService();
      String? fcmToken;
      try {
        fcmToken = PushTokenService(storage: storage).fcmToken;
      } catch (_) {
        fcmToken = null;
      }
      AppFileLogger.log('[network] identity:init:start');
      await identity.initialize(fcmToken: fcmToken);
      AppFileLogger.log(
        '[network] identity:init:ready peerId=${identity.nodeId} '
        'accountId=${identity.accountId} endpointId=${identity.endpointId}',
      );

      AppFileLogger.log('[network] creating SessionCrypto');
      final sessionCrypto = SessionCrypto();
      AppFileLogger.log('[network] creating SignatureService');
      final signatures = SignatureService();
      AppFileLogger.log('[network] creating SessionManager');
      final sessions = SessionManager(
        identity: identity,
        crypto: sessionCrypto,
        signatures: signatures,
      );
      AppFileLogger.log('[network] sessions:ready');

      AppFileLogger.log('[network] creating RoutingTable');
      final routing = RoutingTable(identity.nodeId);
      AppFileLogger.log('[network] creating RecordStore');
      final records = RecordStore();
      AppFileLogger.log('[network] routing-records:ready');

      // ============================
      // TRANSPORT LAYER
      // ============================

      AppFileLogger.log('[network] creating TransportManager');
      final transport = TransportManager();
      AppFileLogger.log('[network] transport:ready');

      // ============================
      // OVERLAY NETWORK
      // ============================

      AppFileLogger.log('[network] creating OverlayRouter');
      final overlay = OverlayRouter(
        selfId: identity.nodeId,
        transport: transport,
        routing: routing,
        events: eventBus,
      );
      AppFileLogger.log('[network] overlay:ready');

      AppFileLogger.log('[network] creating MultiBootstrapSignalingService');
      final signaling = MultiBootstrapSignalingService(
        identity.nodeId,
        registerProofBuilder: () async {
          final timestampMs = DateTime.now().millisecondsSinceEpoch;
          final nonce = DateTime.now().microsecondsSinceEpoch.toString();
          final signingPublicKey = Uint8List.fromList(
            identity.signingPublicKey.bytes,
          );
          final canonicalPayload = jsonEncode(<String, dynamic>{
            'purpose': 'bootstrap-register',
            'protocol': '1',
            'peerId': identity.nodeId,
            'timestampMs': timestampMs,
            'nonce': nonce,
            'signingPublicKey': base64Encode(signingPublicKey),
            'identityProfile': identity.identityProfileJson(),
          });
          final signature = await signatures.sign(
            Uint8List.fromList(utf8.encode(canonicalPayload)),
            identity.signingKeyPair,
          );
          return BootstrapRegisterProof(
            scheme: 'peerlink-ed25519-v1',
            peerId: identity.nodeId,
            timestampMs: timestampMs,
            nonce: nonce,
            signingPublicKey: signingPublicKey,
            signature: signature,
            identityProfile: identity.identityProfileJson(),
          );
        },
      );
      AppFileLogger.log('[network] signaling:ready');

      AppFileLogger.log('[network] creating TurnAllocator');
      final turnAllocator = TurnAllocator();
      await turnAllocator.initialize();
      AppFileLogger.log('[network] turnAllocator:ready');

      // ============================
      // DHT TRANSPORT
      // ============================

      late KademliaProtocol kademlia;

      AppFileLogger.log('[network] creating DhtTransport');
      final dhtTransport = DhtTransport(
        selfId: identity.nodeId,
        router: overlay,
        onMessage: (peerId, rpc) {
          kademlia.handleIncoming(peerId, rpc);
        },
      );
      AppFileLogger.log('[network] dhtTransport:ready');

      // ============================
      // KADEMLIA
      // ============================

      AppFileLogger.log('[network] creating KademliaProtocol');
      kademlia = KademliaProtocol(
        selfId: identity.nodeId,
        routingTable: routing,
        recordStore: records,
        transport: dhtTransport,
      );
      AppFileLogger.log('[network] kademlia:ready');

      // ============================
      // MESSAGING
      // ============================

      AppFileLogger.log('[network] creating HttpRelayClient');
      final relayClient = HttpRelayClient(servers: []);
      AppFileLogger.log('[network] creating PushApiClient');
      final pushApiClient = PushApiClient();
      AppFileLogger.log('[network] creating ReliableMessagingService');
      final messaging = ReliableMessagingService(
        relayClient,
        sessions,
        identity.nodeId,
        enableEncryption: true,
        stateBox: storage.getSettings(),
      );
      await messaging.initialize();
      AppFileLogger.log('[network] creating ChatService');
      final chat = ChatService(
        messaging,
        eventBus,
        serversMergeOrchestrator: RuntimeServersMergeOrchestrator(
          settings: storage.getSettings(),
        ),
      );
      final accessControl = PeerAccessControlService(
        settingsBox: storage.getSettings(),
        contactsRepository: ContactsRepository(storage: storage),
      );
      final callControlTransport = ReliableCallControlAdapter(
        selfPeerId: identity.nodeId,
        chat: chat,
      );
      AppFileLogger.log('[network] creating CallService');
      final calls = CallService(
        selfPeerId: identity.nodeId,
        signaling: signaling,
        turnAllocator: turnAllocator,
        callControlTransport: callControlTransport,
        serversMergeOrchestrator: RuntimeServersMergeOrchestrator(
          settings: storage.getSettings(),
        ),
        incomingCallAccessDecision: (peerId) => accessControl.evaluateIncoming(
          peerId: peerId,
          type: IncomingInteractionType.call,
        ),
        outgoingCallAccessDecision: (peerId) => accessControl.evaluateOutgoing(
          peerId: peerId,
          type: IncomingInteractionType.call,
        ),
      );
      AppFileLogger.log('[network] messaging-chat:ready');

      // ============================
      // NODE
      // ============================

      AppFileLogger.log('[network] creating MeshNode');
      node = MeshNode(
        identity: identity,
        sessions: sessions,
        transport: transport,
        overlay: overlay,
        messaging: messaging,
        relayClient: relayClient,
        chat: chat,
        calls: calls,
        turnAllocator: turnAllocator,
        routing: routing,
        records: records,
        events: eventBus,
        kademlia: kademlia,
        signaling: signaling,
        pushApiClient: pushApiClient,
        settingsBox: storage.getSettings(),
        storage: storage,
        runtimeAdapterFactory: const DefaultMeshNodeRuntimeAdapterFactory(),
      );
      AppFileLogger.log('[network] node:constructed');
      chat.setServerMetadataProvider(node.collectRelayMessageServerMetadata);

      AppFileLogger.log('[network] node:initialize:start');
      await node.initialize();
      AppFileLogger.log('[network] node:initialize:ready');

      AppFileLogger.log('[network] creating NodeFacade');
      nodeFacade = NodeFacade(
        node: node,
        chat: chat,
        calls: calls,
        events: eventBus,
      );
      AppFileLogger.log('[network] facade:ready');

      final health = ServerHealthCoordinator(
        facade: nodeFacade,
        storage: storage,
      );
      relayClient.setAvailabilityLookup(health.relayAvailabilityFor);
      relayClient.setAvailabilityRefresh(health.refreshRelayEndpoints);
      turnAllocator.setAvailabilityLookup(health.turnAvailabilityFor);
      turnAllocator.setAvailabilityRefresh(health.refreshTurnUrls);
      AppFileLogger.log('[network] health:wired');

      AppFileLogger.log('[network] initialize:complete instance=$instanceId');
    } catch (e, stack) {
      AppFileLogger.log(
        '[network] initialize:error instance=$instanceId $e\n$stack',
      );
      rethrow;
    }
  }
}
