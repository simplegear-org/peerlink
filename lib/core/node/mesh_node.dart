import 'dart:async';
import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'package:peerlink/core/security/session_manager.dart' hide PeerSession;

import '../security/identity_service.dart';
import '../calls/call_service.dart';
import '../transport/transport_manager.dart';
import '../transport/peer_session.dart';
import '../transport/webrtc_transport.dart';
import '../transport/transport_mode.dart';
import '../overlay/overlay_router.dart';
import '../messaging/reliable_messaging_service.dart';
import '../messaging/chat_service.dart';
import '../relay/http_relay_client.dart';
import '../dht/routing_table.dart';
import '../dht/record_store.dart';
import '../runtime/network_event_bus.dart';
import '../runtime/network_event.dart';
import '../dht/rpc/kademlia_protocol.dart';
import '../dht/rpc/rpc_types.dart';
import '../signaling/multi_bootstrap_signaling_service.dart';
import '../signaling/signaling_service.dart';
import '../signaling/signaling_message.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_server_config.dart';
import 'peer_presence.dart';
import 'mesh_peer_transports.dart';
import 'mesh_signal_router.dart';

/// Оркестратор сетевого ядра: lifecycle, bootstrap, сессии и маршрутизация signaling.
class MeshNode {
  final IdentityService identity;
  final SessionManager sessions;
  final TransportManager transport;
  final OverlayRouter overlay;
  final ReliableMessagingService messaging;
  final HttpRelayClient relayClient;
  final ChatService chat;
  final CallService calls;
  final TurnAllocator turnAllocator;
  final RoutingTable routing;
  final RecordStore records;
  final NetworkEventBus events;
  final KademliaProtocol kademlia;
  final SignalingService signaling;

  final Map<String, PeerSession> _peerSessions = {};
  final Map<String, MeshPeerTransports> _peerTransports = {};
  final List<String> _bootstrapServers = [];
  final List<String> _relayServers = [];
  final Set<String> _discoveredPeers = {};
  final StreamController<List<String>> _discoveredPeersController =
      StreamController.broadcast();
  final StreamController<PeerPresenceUpdate> _peerPresenceController =
      StreamController.broadcast();
  StreamSubscription<SignalingMessage>? _signalingSubscription;
  StreamSubscription<List<String>>? _peersSubscription;
  final Set<String> _connectedPeers = {};
  final Set<String> _onlinePeers = {};
  final Map<String, DateTime> _lastSeenByPeer = {};
  late final MeshSignalRouter _signalRouter;
  int _logSeq = 0;

  MeshNode({
    required this.identity,
    required this.sessions,
    required this.transport,
    required this.overlay,
    required this.messaging,
    required this.relayClient,
    required this.chat,
    required this.calls,
    required this.turnAllocator,
    required this.routing,
    required this.records,
    required this.events,
    required this.kademlia,
    required this.signaling,
  }) {
    _signalRouter = MeshSignalRouter(
      selfPeerId: identity.nodeId,
      calls: calls,
      ensurePeerSession: _ensurePeerSession,
      getPeerTransports: (peerId) => _peerTransports[peerId],
      log: _log,
    );
  }

  /// Инициализирует зависимости узла и подписывается на signaling события.
  Future<void> initialize() async {
    await identity.initialize();
    _signalingSubscription = signaling.messages.listen(
      _signalRouter.handleSignalingMessage,
    );
    _peersSubscription = signaling.peersStream.listen(_handleDiscoveredPeers);
    _log('initialize:signaling subscribed');
  }

  /// Подключает peer в routing и поднимает обязательную transport-сессию.
  Future<void> connectTo(String peerId) async {
    _log('connectTo peerId=$peerId');

    final signalingReady = await _waitForSignalingReady();
    if (!signalingReady) {
      _log('connectTo aborted: signaling is not ready');
      return;
    }

    routing.update(NodeInfo(peerId, ''));
    final shouldInitiate = _shouldInitiateDial(peerId);
    _log('connectTo initiateDial=$shouldInitiate peerId=$peerId');
    await _ensurePeerSession(peerId, initiateDial: shouldInitiate);
  }

  Future<void> pollRelay() async {
    await messaging.pollRelay();
  }

  bool _shouldInitiateDial(String peerId) {
    return identity.nodeId.compareTo(peerId) < 0;
  }

  /// Возвращает список настроенных bootstrap-серверов.
  List<String> get bootstrapServers => List.unmodifiable(_bootstrapServers);
  String? get activeBootstrapServer =>
      signaling is MultiBootstrapSignalingService
          ? (signaling as MultiBootstrapSignalingService).primaryConnectedEndpoint
          : (_bootstrapServers.isEmpty ? null : _bootstrapServers.first);
  SignalingConnectionStatus get bootstrapConnectionStatus =>
      signaling.connectionStatus;
  Stream<SignalingConnectionStatus> get bootstrapConnectionStatusStream =>
      signaling.connectionStatusStream;
  String? get bootstrapLastError => signaling.lastError;
  Stream<String?> get bootstrapLastErrorStream =>
      signaling.lastErrorStream;
  Stream<List<String>> get discoveredPeersStream =>
      _discoveredPeersController.stream;
  Stream<PeerPresenceUpdate> get peerPresenceStream =>
      _peerPresenceController.stream;
  bool isPeerOnline(String peerId) => _onlinePeers.contains(peerId);
  DateTime? peerLastSeenAt(String peerId) => _lastSeenByPeer[peerId];

  /// Возвращает список настроенных message relay-серверов.
  List<String> get relayServers => List.unmodifiable(_relayServers);
  List<RelayServerStatus> get relayServerStatuses => relayClient.serverStatuses;
  List<TurnServerConfig> get turnServers => turnAllocator.serverConfigs;

  /// Добавляет bootstrap-сервер и активирует его, если это первый сервер.
  Future<void> addBootstrapServer(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      return;
    }

    if (_bootstrapServers.contains(normalized)) {
      return;
    }

    _bootstrapServers.add(normalized);
    await signaling.configureServers(_bootstrapServers);
  }

  /// Удаляет bootstrap-сервер и переключает signaling на следующий доступный.
  Future<void> removeBootstrapServer(String endpoint) async {
    final normalized = endpoint.trim();
    if (!_bootstrapServers.remove(normalized)) {
      return;
    }

    if (_bootstrapServers.isEmpty) {
      await signaling.close();
      return;
    }
    await signaling.configureServers(_bootstrapServers);
  }

  /// Полностью заменяет список bootstrap-серверов.
  Future<void> configureBootstrapServers(List<String> endpoints) async {
    _bootstrapServers
      ..clear()
      ..addAll(
        endpoints.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
      );

    if (_bootstrapServers.isEmpty) {
      await signaling.close();
      return;
    }

    await signaling.configureServers(_bootstrapServers);
  }

  /// Добавляет message relay-сервер.
  Future<void> addRelayServer(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      return;
    }

    if (_relayServers.contains(normalized)) {
      return;
    }

    _relayServers.add(normalized);
    messaging.configureRelayServers(_relayServers);
  }

  /// Удаляет message relay-сервер.
  Future<void> removeRelayServer(String endpoint) async {
    final normalized = endpoint.trim();
    _relayServers.remove(normalized);
    messaging.configureRelayServers(_relayServers);
  }

  /// Полностью заменяет список message relay-серверов.
  Future<void> configureRelayServers(List<String> endpoints) async {
    _relayServers
      ..clear()
      ..addAll(
        endpoints.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet(),
      );
    messaging.configureRelayServers(_relayServers);
  }

  Future<void> configureTurnServers(List<TurnServerConfig> servers) async {
    _log('turn:configure count=${servers.length} urls=${servers.map((e) => e.url).join(',')}');
    turnAllocator.configureServers(servers);
  }

  Future<void> updateFcmToken(String? token) async {
    await identity.updateMessagingEndpoint(token);
    _log(
      'identity:update fcmToken endpointId=${identity.endpointId} '
      'tokenHash=${identity.fcmTokenHash}',
    );
  }

  /// Создает peer-сессию и регистрирует прямой transport для peer.
  Future<void> _ensurePeerSession(
    String peerId, {
    required bool initiateDial,
  }) async {
    if (_peerSessions.containsKey(peerId)) {
      return;
    }

    final direct = WebRtcTransport(
      mode: TransportMode.direct,
      signaling: signaling,
      subscribeToSignaling: false,
      canSignal: () => !calls.state.isBusy,
      onIncomingMessage: (bytes) => transport.emit(peerId, bytes),
      onConnected: _handleTransportConnected,
    );

    final session = PeerSession(
      peerId: peerId,
      direct: direct,
    );

    _peerSessions[peerId] = session;
    _peerTransports[peerId] = MeshPeerTransports(
      direct: direct,
    );
    transport.registerSession(session);

    if (initiateDial) {
      await session.connect();
    }
  }

  void _log(String message) {
    AppFileLogger.log('[mesh][${identity.nodeId}][${_logSeq++}] $message');
  }

  Future<bool> _waitForSignalingReady() async {
    if (_bootstrapServers.isEmpty) {
      _log('connectTo:skip wait signaling - no bootstrap servers configured');
      return false;
    }

    if (signaling.connectionStatus == SignalingConnectionStatus.connected) {
      return true;
    }

    _log('connectTo:wait signaling');
    final completer = Completer<void>();
    late final StreamSubscription<SignalingConnectionStatus> sub;
    sub = signaling.connectionStatusStream.listen((status) {
      if (status == SignalingConnectionStatus.connected) {
        sub.cancel();
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 10));
      return true;
    } on TimeoutException {
      _log('connectTo:signaling timeout');
      return false;
    } finally {
      await sub.cancel();
    }
  }

  void _handleTransportConnected(String peerId, TransportMode mode) {
    if (_connectedPeers.contains(peerId)) {
      return;
    }
    _connectedPeers.add(peerId);
    _log('peerConnected peerId=$peerId mode=$mode');
    events.emit(PeerConnected(peerId));
  }

  /// Останавливает узел и корректно освобождает сетевые ресурсы.
  Future<void> shutdown() async {
    final sessions = List<PeerSession>.from(_peerSessions.values);
    for (final session in sessions) {
      await session.close();
    }
    _peerSessions.clear();
    _peerTransports.clear();

    await _signalingSubscription?.cancel();
    await _peersSubscription?.cancel();
    await _discoveredPeersController.close();
    await _peerPresenceController.close();
    await signaling.close();
    await calls.dispose();
    await chat.dispose();
    await messaging.dispose();
    await overlay.dispose();
    transport.dispose();
    await events.dispose();
  }

  void _handleDiscoveredPeers(List<String> peers) {
    final now = DateTime.now();
    final onlineNow = peers
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != identity.nodeId)
        .toSet();

    final becameOnline = onlineNow.difference(_onlinePeers);
    for (final peerId in becameOnline) {
      _onlinePeers.add(peerId);
      _lastSeenByPeer.remove(peerId);
      _peerPresenceController.add(
        PeerPresenceUpdate(
          peerId: peerId,
          isOnline: true,
          observedAt: now,
        ),
      );
    }

    final becameOffline = _onlinePeers.difference(onlineNow);
    for (final peerId in becameOffline) {
      _onlinePeers.remove(peerId);
      _lastSeenByPeer[peerId] = now;
      _peerPresenceController.add(
        PeerPresenceUpdate(
          peerId: peerId,
          isOnline: false,
          observedAt: now,
          lastSeenAt: now,
        ),
      );
    }

    final fresh = <String>[];
    for (final peerId in onlineNow) {
      if (_discoveredPeers.add(peerId)) {
        fresh.add(peerId);
        routing.update(NodeInfo(peerId, ''));
      }
    }

    if (fresh.isNotEmpty) {
      _log('discovery:peers=${fresh.length}');
      _discoveredPeersController.add(fresh);
    }
  }
}
