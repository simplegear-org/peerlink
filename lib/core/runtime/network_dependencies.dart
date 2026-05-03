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
import '../node/node_facade.dart';
import '../relay/relay_router.dart';
import '../relay/http_relay_client.dart';
import '../signaling/bootstrap_signaling_service.dart';
import '../signaling/multi_bootstrap_signaling_service.dart';
import '../turn/turn_allocator.dart';
import 'server_health_coordinator.dart';
import 'network_event_bus.dart';

/// Сборка и wiring всех сетевых зависимостей приложения.
class NetworkDependencies {
  late final NetworkEventBus eventBus;
  late final MeshNode node;
  late final NodeFacade nodeFacade;

  NetworkDependencies._();

  /// Фабричный метод создания и инициализации dependency graph.
  static Future<NetworkDependencies> create() async {
    final deps = NetworkDependencies._();
    await deps._initialize();
    return deps;
  }

  /// Инициализирует core-сервисы и связывает их в единый runtime.
  Future<void> _initialize() async {
    try {
      AppFileLogger.log('[network] initialize:start');
      eventBus = NetworkEventBus();
      AppFileLogger.log('[network] eventBus:ready');
      final storage = StorageService();

      // ============================
      // CORE SERVICES
      // ============================

      AppFileLogger.log('[network] creating IdentityService');
      final identity = IdentityService();
      String? fcmToken;
      try {
        fcmToken = storage.getSettings().get('fcm_token') as String?;
      } catch (_) {
        fcmToken = null;
      }
      AppFileLogger.log('[network] identity:init:start');
      await identity.initialize(fcmToken: fcmToken);
      AppFileLogger.log(
        '[network] identity:init:ready peerId=${identity.nodeId} '
        'legacyPeerId=${identity.legacyNodeId} endpointId=${identity.endpointId}',
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

      AppFileLogger.log('[network] creating RelayRouter');
      const relay = RelayRouter();
      AppFileLogger.log('[network] creating OverlayRouter');
      final overlay = OverlayRouter(
        selfId: identity.nodeId,
        transport: transport,
        routing: routing,
        relay: relay,
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
            'legacyPeerId': identity.legacyNodeId,
            'identityProfile': identity.identityProfileJson(),
          });
          final signature = await signatures.sign(
            Uint8List.fromList(utf8.encode(canonicalPayload)),
            identity.signingKeyPair,
          );
          return BootstrapRegisterProof(
            scheme: 'peerlink-ed25519-v1',
            peerId: identity.nodeId,
            legacyPeerId: identity.legacyNodeId,
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
      AppFileLogger.log('[network] creating ReliableMessagingService');
      final messaging = ReliableMessagingService(
        relayClient,
        sessions,
        identity.nodeId,
        enableEncryption: true,
      );
      AppFileLogger.log('[network] creating ChatService');
      final chat = ChatService(messaging, eventBus);
      AppFileLogger.log('[network] creating CallService');
      final calls = CallService(
        selfPeerId: identity.nodeId,
        signaling: signaling,
        turnAllocator: turnAllocator,
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
      );
      AppFileLogger.log('[network] node:constructed');

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
      
      AppFileLogger.log('[network] initialize:complete');
    } catch (e, stack) {
      AppFileLogger.log('[network] initialize:error $e\n$stack');
      rethrow;
    }
  }
}
