import 'dart:async';
import 'dart:io' show Platform;
import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'package:peerlink/core/security/session_manager.dart' hide PeerSession;

import '../security/identity_service.dart';
import '../calls/call_models.dart';
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
import '../push/push_api_client.dart';
import '../push/push_event_factory.dart';
import '../push/push_event_service.dart';
import '../push/push_runtime_metadata_builder.dart';
import '../runtime/network_event_bus.dart';
import '../runtime/network_event.dart';
import '../runtime/push_token_service.dart';
import '../runtime/push_servers_service.dart';
import '../runtime/storage_service.dart';
import '../runtime/account_membership_update_payload.dart';
import '../dht/rpc/kademlia_protocol.dart';
import '../dht/rpc/rpc_types.dart';
import '../signaling/multi_bootstrap_signaling_service.dart';
import '../signaling/signaling_service.dart';
import '../signaling/signaling_message.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_server_config.dart';
import 'peer_presence.dart';
import 'mesh_call_push_helper.dart';
import 'mesh_peer_transports.dart';
import 'mesh_signal_router.dart';

/// Оркестратор сетевого ядра: lifecycle, bootstrap, сессии и маршрутизация signaling.
class MeshNode {
  static const String _pushServerUrlDefine = String.fromEnvironment(
    'PUSH_SERVER_URL',
  );
  static const String _pushApiTokenDefine = String.fromEnvironment(
    'PUSH_API_TOKEN',
    defaultValue: 'peerlink',
  );

  final int instanceId = identityHashCode(Object());
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
  final PushApiClient pushApiClient;
  final PushTokenService _pushTokens = PushTokenService();
  final SecureStorageBox settingsBox;

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
  late final MeshCallPushHelper _callPush;
  late final MeshSignalRouter _signalRouter;
  late final PushEventFactory _pushEventFactory;
  late final PushEventService _pushEventService;
  late final PushRuntimeMetadataBuilder _pushRuntimeMetadataBuilder;
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
    required this.pushApiClient,
    required this.settingsBox,
  }) {
    _pushEventFactory = const PushEventFactory();
    _pushEventService = PushEventService(
      identity: identity,
      pushApiClient: pushApiClient,
      resolvePushBaseUris: _resolvePushBaseUris,
      pushBearerToken: _pushBearerToken,
      log: _log,
    );
    _pushRuntimeMetadataBuilder = PushRuntimeMetadataBuilder(
      connectedBootstrapServers: () => connectedBootstrapServers,
      activeBootstrapServer: () => activeBootstrapServer,
      relayServerStatuses: () => relayServerStatuses,
      activePushBaseUri: _resolvePushBaseUri,
      turnServers: () => turnServers,
      isTurnServerHealthy: turnAllocator.isHealthy,
      connectedTargetBootstrapServersForPeer:
          _connectedTargetBootstrapServersForPeer,
      healthyOrderedTurnServerConfigs: () =>
          turnAllocator.healthyOrderedServerConfigs,
      log: _log,
    );
    _callPush = MeshCallPushHelper(
      identity: identity,
      pushApiClient: pushApiClient,
      pushTokens: _pushTokens,
      resolvePushBaseUris: _resolvePushBaseUris,
      pushBearerToken: _pushBearerToken,
      pushEventFactory: _pushEventFactory,
      pushEventService: _pushEventService,
      pushRuntimeMetadataBuilder: _pushRuntimeMetadataBuilder,
      platformName: _platformName,
      log: _log,
    );
    calls.setCallInviteMetadataBuilder(
      _pushRuntimeMetadataBuilder.buildCallInviteRuntimeMetadata,
    );
    _signalRouter = MeshSignalRouter(
      selfPeerId: identity.nodeId,
      calls: calls,
      ensurePeerSession: _ensurePeerSession,
      getPeerTransports: (peerId) => _peerTransports[peerId],
      log: _log,
    );
    _log('construct instance=$instanceId');
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

  Future<void> pollRelay({List<String>? relayServers}) async {
    await messaging.pollRelay(relayServers: relayServers);
  }

  bool _shouldInitiateDial(String peerId) {
    return identity.nodeId.compareTo(peerId) < 0;
  }

  /// Возвращает список настроенных bootstrap-серверов.
  List<String> get bootstrapServers => List.unmodifiable(_bootstrapServers);
  List<String> get connectedBootstrapServers =>
      signaling is MultiBootstrapSignalingService
      ? List.unmodifiable(
          (signaling as MultiBootstrapSignalingService).connectedEndpoints,
        )
      : const <String>[];
  String? get activeBootstrapServer =>
      signaling is MultiBootstrapSignalingService
      ? (signaling as MultiBootstrapSignalingService).primaryConnectedEndpoint
      : (_bootstrapServers.isEmpty ? null : _bootstrapServers.first);
  SignalingConnectionStatus get bootstrapConnectionStatus =>
      signaling.connectionStatus;
  Stream<SignalingConnectionStatus> get bootstrapConnectionStatusStream =>
      signaling.connectionStatusStream;
  String? get bootstrapLastError => signaling.lastError;
  Stream<String?> get bootstrapLastErrorStream => signaling.lastErrorStream;
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
    final normalized = endpoints
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (_sameStringsIgnoringOrder(_bootstrapServers, normalized)) {
      _log(
        'configureBootstrapServers skip unchanged instance=$instanceId endpoints=${normalized.join(",")}',
      );
      return;
    }
    _log(
      'configureBootstrapServers apply instance=$instanceId endpoints=${normalized.join(",")}',
    );
    _bootstrapServers
      ..clear()
      ..addAll(normalized);

    if (_bootstrapServers.isEmpty) {
      await signaling.close();
      return;
    }

    await signaling.configureServers(_bootstrapServers);
  }

  Future<bool> waitForAnyBootstrapConnected(
    List<String> endpoints, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final expected = endpoints
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (expected.isEmpty) {
      return false;
    }
    if (signaling is! MultiBootstrapSignalingService) {
      return signaling.connectionStatus == SignalingConnectionStatus.connected;
    }
    final multi = signaling as MultiBootstrapSignalingService;
    final connected = multi.connectedEndpoints.toSet();
    if (connected.intersection(expected).isNotEmpty) {
      return true;
    }
    final completer = Completer<bool>();
    late final StreamSubscription<SignalingConnectionStatus> sub;
    sub = signaling.connectionStatusStream.listen((_) {
      final current = multi.connectedEndpoints.toSet();
      if (current.intersection(expected).isNotEmpty && !completer.isCompleted) {
        completer.complete(true);
      }
    });
    try {
      return await completer.future.timeout(timeout, onTimeout: () => false);
    } finally {
      await sub.cancel();
    }
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
    _log(
      'turn:configure count=${servers.length} urls=${servers.map((e) => e.url).join(',')}',
    );
    turnAllocator.configureServers(servers);
  }

  Future<void> updateFcmToken(String? token) async {
    await identity.updateMessagingEndpoint(token);
    _log(
      'identity:update fcmToken endpointId=${identity.endpointId} '
      'tokenHash=${identity.fcmTokenHash}',
    );
  }

  Future<void> registerPushDeviceToken(String? token) async {
    await _callPush.registerPushDeviceToken(token);
  }

  Future<void> registerVoipDeviceToken(String token) =>
      _callPush.registerVoipDeviceToken(token);

  Future<void> unregisterPushDeviceToken(String token) async {
    await _callPush.unregisterPushDeviceToken(token);
  }

  Future<void> unregisterVoipDeviceToken(String token) =>
      _callPush.unregisterVoipDeviceToken(token);

  Future<void> sendGroupPushEvent({
    required String groupId,
    required String messageId,
    required List<String> recipientUserIds,
    List<String>? relayServers,
    String? notificationType,
    String? relayServerId,
    String? relayScopeKind,
    String? relayBlobId,
    String? relayMessageId,
  }) async {
    final resolvedRelayScopeKind = (relayScopeKind?.trim().isNotEmpty ?? false)
        ? relayScopeKind!.trim()
        : 'group';
    final resolvedRelayServerId = _resolveRelayServerId(relayServerId);
    final draft = _pushEventFactory.buildGroupMessage(
      senderUserId: identity.nodeId,
      groupId: groupId,
      messageId: messageId,
      recipientUserIds: recipientUserIds,
      servers: _pushRuntimeMetadataBuilder.collectAvailableServers(),
      relayHint: PushRelayHint(
        serverId: resolvedRelayServerId,
        servers: relayServers ?? const <String>[],
        scopeKind: resolvedRelayScopeKind,
        blobId: relayBlobId,
        relayMessageId: relayMessageId,
      ),
      notificationType: notificationType,
    );
    await _pushEventService.send(draft, logLabel: 'push event');
    _log(
      'push event done sender=${identity.nodeId} group=$groupId '
      'message=$messageId recipients=${recipientUserIds.length} '
      'relayServerId=${resolvedRelayServerId ?? '-'} scope=$resolvedRelayScopeKind',
    );
  }

  Future<void> sendDirectPushEvent({
    required String directPeerId,
    required String messageId,
    List<String>? relayServers,
    String? notificationType,
    String? relayServerId,
    String? relayScopeKind,
    String? relayBlobId,
    String? relayMessageId,
    Map<String, dynamic>? data,
  }) async {
    final resolvedRelayScopeKind = (relayScopeKind?.trim().isNotEmpty ?? false)
        ? relayScopeKind!.trim()
        : 'direct';
    final resolvedRelayServerId = _resolveRelayServerId(relayServerId);
    final draft = _pushEventFactory.buildDirectMessage(
      senderUserId: identity.nodeId,
      directPeerId: directPeerId,
      messageId: messageId,
      servers: _pushRuntimeMetadataBuilder.collectAvailableServers(),
      relayHint: PushRelayHint(
        serverId: resolvedRelayServerId,
        servers: relayServers ?? const <String>[],
        scopeKind: resolvedRelayScopeKind,
        blobId: relayBlobId,
        relayMessageId: relayMessageId,
      ),
      notificationType: notificationType,
      data: data,
    );
    await _pushEventService.send(draft, logLabel: 'push direct event');
    _log(
      'push direct event done sender=${identity.nodeId} peer=$directPeerId '
      'message=$messageId relayServerId=${resolvedRelayServerId ?? '-'} scope=$resolvedRelayScopeKind',
    );
  }

  Future<void> sendAccountMembershipUpdatePushEvent({
    required String directPeerId,
    required AccountMembershipUpdatePayload update,
  }) async {
    final draft = _pushEventFactory.buildAccountMembershipUpdate(
      senderUserId: identity.nodeId,
      directPeerId: directPeerId,
      update: update,
      servers: _pushRuntimeMetadataBuilder.collectAvailableServers(),
    );
    await _pushEventService.send(draft, logLabel: 'push account update');
    _log(
      'push account update done sender=${identity.nodeId} peer=$directPeerId update=${update.updateId}',
    );
  }

  Future<void> sendCallInvitePushEvent({
    required String calleeUserId,
    required String callId,
    required CallMediaType mediaType,
  }) => _callPush.sendCallInvitePushEvent(
    calleeUserId: calleeUserId,
    callId: callId,
    mediaType: mediaType,
  );

  Future<void> sendCallEndPushEvent({
    required String calleeUserId,
    required String callId,
  }) => _callPush.sendCallEndPushEvent(
    calleeUserId: calleeUserId,
    callId: callId,
  );

  bool _sameStringsIgnoringOrder(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    final leftSet = left.toSet();
    final rightSet = right.toSet();
    if (leftSet.length != rightSet.length) {
      return false;
    }
    return leftSet.containsAll(rightSet);
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

    final session = PeerSession(peerId: peerId, direct: direct);

    _peerSessions[peerId] = session;
    _peerTransports[peerId] = MeshPeerTransports(direct: direct);
    transport.registerSession(session);

    if (initiateDial) {
      await session.connect();
    }
  }

  void _log(String message) {
    AppFileLogger.log('[mesh][${identity.nodeId}][${_logSeq++}] $message');
  }

  Uri? _resolvePushBaseUri() {
    final resolved = _resolvePushBaseUris();
    if (resolved.isEmpty) {
      return null;
    }
    return resolved.first;
  }

  List<Uri> _resolvePushBaseUris() {
    final result = <String, Uri>{};

    final envPushUrl = _pushServerUrlDefine.trim();
    if (envPushUrl.isNotEmpty) {
      final parsed = Uri.tryParse(envPushUrl);
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        result.putIfAbsent(parsed.toString(), () => parsed);
      }
    }
    final configuredList = settingsBox.get('push_servers');
    if (configuredList is List) {
      for (final item in PushServersService.extractActiveEndpointsFromStorage(
        configuredList,
      )) {
        final parsed = Uri.tryParse(item.trim());
        if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
          result.putIfAbsent(parsed.toString(), () => parsed);
        }
      }
    }
    final legacyConfigured = settingsBox.get('push_server_url');
    if (legacyConfigured is String && legacyConfigured.trim().isNotEmpty) {
      final parsed = Uri.tryParse(legacyConfigured.trim());
      if (parsed != null && parsed.hasScheme && parsed.host.isNotEmpty) {
        result.putIfAbsent(parsed.toString(), () => parsed);
      }
    }
    if (result.isNotEmpty) {
      return result.values.toList(growable: false);
    }
    if (_relayServers.isNotEmpty) {
      final relayUri = Uri.tryParse(_relayServers.first);
      if (relayUri != null && relayUri.host.isNotEmpty) {
        final fallback = Uri(scheme: 'https', host: relayUri.host, port: 445);
        result.putIfAbsent(fallback.toString(), () => fallback);
      }
    }
    return result.values.toList(growable: false);
  }

  String? _pushBearerToken() {
    final envToken = _pushApiTokenDefine.trim();
    if (envToken.isNotEmpty) {
      return envToken;
    }
    return null;
  }

  String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isLinux) return 'linux';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }

  String? _resolveRelayServerId(String? explicit) {
    final normalizedExplicit = explicit?.trim();
    if (normalizedExplicit != null && normalizedExplicit.isNotEmpty) {
      return normalizedExplicit;
    }
    if (_relayServers.isEmpty) {
      return null;
    }
    final relayUri = Uri.tryParse(_relayServers.first.trim());
    if (relayUri == null || relayUri.host.isEmpty) {
      return null;
    }
    final normalizedPort = relayUri.hasPort ? ':${relayUri.port}' : '';
    return '${relayUri.host}$normalizedPort';
  }

  List<String> _connectedTargetBootstrapServersForPeer(String calleeUserId) {
    if (signaling is MultiBootstrapSignalingService) {
      return (signaling as MultiBootstrapSignalingService)
          .connectedTargetEndpointsForPeer(calleeUserId);
    }
    return activeBootstrapServer == null
        ? const <String>[]
        : <String>[activeBootstrapServer!];
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
        PeerPresenceUpdate(peerId: peerId, isOnline: true, observedAt: now),
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
