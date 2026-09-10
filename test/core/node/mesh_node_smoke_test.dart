import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_service.dart';
import 'package:peerlink/core/dht/dht_transport.dart';
import 'package:peerlink/core/dht/record_store.dart';
import 'package:peerlink/core/dht/routing_table.dart';
import 'package:peerlink/core/dht/rpc/kademlia_protocol.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/node/mesh_node.dart';
import 'package:peerlink/core/node/mesh_node_runtime_adapters.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/node/peer_presence.dart';
import 'package:peerlink/core/node/reliable_call_control_adapter.dart';
import 'package:peerlink/core/overlay/overlay_router.dart';
import 'package:peerlink/core/push/push_api_client.dart';
import 'package:peerlink/core/relay/http_relay_client.dart';
import 'package:peerlink/core/runtime/network_event_bus.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/security/identity_service.dart';
import 'package:peerlink/core/security/session_crypto.dart';
import 'package:peerlink/core/security/session_manager.dart';
import 'package:peerlink/core/security/signature_service.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/transport/transport_manager.dart';
import 'package:peerlink/core/turn/turn_allocator.dart';

class _InMemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FakeSignalingService implements SignalingService {
  final StreamController<SignalingMessage> _messagesController =
      StreamController<SignalingMessage>.broadcast();
  final StreamController<List<String>> _peersController =
      StreamController<List<String>>.broadcast();
  final StreamController<SignalingConnectionStatus> _statusController =
      StreamController<SignalingConnectionStatus>.broadcast();
  final StreamController<String?> _lastErrorController =
      StreamController<String?>.broadcast();

  _FakeSignalingService({
    SignalingConnectionStatus connectionStatus =
        SignalingConnectionStatus.connected,
  }) : _connectionStatus = connectionStatus;

  final List<List<String>> configuredServersHistory = <List<String>>[];
  final SignalingConnectionStatus _connectionStatus;

  void emitMessage(SignalingMessage message) {
    _messagesController.add(message);
  }

  void emitPeers(List<String> peers) {
    _peersController.add(peers);
  }

  @override
  Stream<SignalingMessage> get messages => _messagesController.stream;

  @override
  Stream<List<String>> get peersStream => _peersController.stream;

  @override
  SignalingConnectionStatus get connectionStatus => _connectionStatus;

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  @override
  String? get lastError => null;

  @override
  Stream<String?> get lastErrorStream => _lastErrorController.stream;

  @override
  Future<void> close() async {
    await _messagesController.close();
    await _peersController.close();
    await _statusController.close();
    await _lastErrorController.close();
  }

  @override
  Future<void> configureServers(List<String> endpoints) async {
    configuredServersHistory.add(List<String>.from(endpoints));
  }

  @override
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) async {}

  @override
  Future<void> sendIce(String peerId, Map<String, dynamic> candidate) async {}

  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) async {}

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {}

  @override
  Future<void> setServer(String endpoint) async {}
}

Future<
  ({
    MeshNode node,
    NodeFacade facade,
    _FakeSignalingService signaling,
    StorageService storage,
  })
>
_buildHarness() async {
  final identity = IdentityService(keyStore: _InMemoryIdentityKeyStore());
  await identity.initialize();

  final signaling = _FakeSignalingService();
  final transport = TransportManager();
  final events = NetworkEventBus();
  final routing = RoutingTable(identity.nodeId);
  final overlay = OverlayRouter(
    selfId: identity.nodeId,
    transport: transport,
    routing: routing,
    events: events,
  );
  final dhtTransport = DhtTransport(
    selfId: identity.nodeId,
    router: overlay,
    onMessage: (_, payload) {},
  );
  final kademlia = KademliaProtocol(
    selfId: identity.nodeId,
    routingTable: routing,
    recordStore: RecordStore(),
    transport: dhtTransport,
  );
  final sessions = SessionManager(
    identity: identity,
    crypto: SessionCrypto(),
    signatures: SignatureService(),
  );
  final relayClient = HttpRelayClient(servers: const <String>[]);
  final settingsStorage = StorageService();
  await settingsStorage.init();
  final settings = settingsStorage.getSettings();
  await settings.clear();
  final messaging = ReliableMessagingService(
    relayClient,
    sessions,
    identity.nodeId,
    enableEncryption: true,
    stateBox: settings,
  );
  await messaging.initialize();
  final chat = ChatService(messaging, events);
  final turnAllocator = TurnAllocator();
  final callControlTransport = ReliableCallControlAdapter(
    selfPeerId: identity.nodeId,
    chat: chat,
  );
  final calls = CallService(
    selfPeerId: identity.nodeId,
    signaling: signaling,
    turnAllocator: turnAllocator,
    callControlTransport: callControlTransport,
  );
  final node = MeshNode(
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
    records: RecordStore(),
    events: events,
    kademlia: kademlia,
    signaling: signaling,
    pushApiClient: PushApiClient(),
    settingsBox: settings,
    storage: settingsStorage,
    runtimeAdapterFactory: const DefaultMeshNodeRuntimeAdapterFactory(),
  );
  await node.initialize();
  final facade = NodeFacade(
    node: node,
    chat: chat,
    calls: calls,
    events: events,
  );

  return (
    node: node,
    facade: facade,
    signaling: signaling,
    storage: settingsStorage,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'MeshNode smoke via NodeFacade wires bootstrap config, discovery, and call invite routing',
    () async {
      final harness = await _buildHarness();
      final node = harness.node;
      final facade = harness.facade;
      final signaling = harness.signaling;
      expect(identical(node.storage, harness.storage), isTrue);
      final discoveredPeers = <List<String>>[];
      final presenceUpdates = <PeerPresenceUpdate>[];

      final discoveredSub = facade.discoveredPeersStream.listen(
        discoveredPeers.add,
      );
      final presenceSub = facade.peerPresenceStream.listen(presenceUpdates.add);

      addTearDown(() async {
        await discoveredSub.cancel();
        await presenceSub.cancel();
        await node.shutdown();
      });

      await facade.configureBootstrapServers(<String>[
        'wss://bootstrap-a.example',
        'wss://bootstrap-a.example',
        ' wss://bootstrap-b.example ',
      ]);

      expect(facade.bootstrapServers, <String>[
        'wss://bootstrap-a.example',
        'wss://bootstrap-b.example',
      ]);
      expect(signaling.configuredServersHistory.single, <String>[
        'wss://bootstrap-a.example',
        'wss://bootstrap-b.example',
      ]);

      signaling.emitPeers(<String>['peer-a', 'peer-b', facade.peerId]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(discoveredPeers, hasLength(1));
      expect(discoveredPeers.single, <String>['peer-a', 'peer-b']);
      expect(facade.isPeerOnline('peer-a'), isTrue);
      expect(facade.isPeerOnline('peer-b'), isTrue);
      expect(
        presenceUpdates.map((update) => update.peerId),
        containsAll(<String>['peer-a', 'peer-b']),
      );

      signaling.emitPeers(<String>['peer-b']);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(facade.isPeerOnline('peer-a'), isFalse);
      expect(facade.peerLastSeenAt('peer-a'), isNotNull);
      expect(
        presenceUpdates.any(
          (update) => update.peerId == 'peer-a' && !update.isOnline,
        ),
        isTrue,
      );

      signaling.emitMessage(
        SignalingMessage(
          type: 'call_invite',
          fromPeerId: 'peer-b',
          toPeerId: facade.peerId,
          data: const <String, dynamic>{
            'callId': 'call-smoke-node',
            'mediaType': 'video',
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(facade.callState.phase, CallPhase.incomingRinging);
      expect(facade.callState.peerId, 'peer-b');
      expect(facade.callState.callId, 'call-smoke-node');
      expect(facade.callState.mediaType, CallMediaType.video);
    },
  );
}
