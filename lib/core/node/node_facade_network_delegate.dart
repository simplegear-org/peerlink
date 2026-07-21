import '../relay/relay_server_status.dart';
import '../runtime/account_membership_update_payload.dart';
import '../signaling/signaling_service.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_server_config.dart';
import 'mesh_node.dart';
import 'peer_presence.dart';

class NodeFacadeNetworkDelegate {
  NodeFacadeNetworkDelegate(this._node);

  final MeshNode _node;

  Future<void> sendAccountMembershipUpdatePushEvent({
    required String directPeerId,
    required AccountMembershipUpdatePayload update,
  }) {
    return _node.sendAccountMembershipUpdatePushEvent(
      directPeerId: directPeerId,
      update: update,
    );
  }

  Future<void> connectToPeer(String peerId) {
    return _node.connectTo(peerId);
  }

  List<String> get bootstrapServers => _node.bootstrapServers;
  List<String> get relayServers => _node.relayServers;
  List<RelayServerStatus> get relayServerStatuses => _node.relayServerStatuses;
  List<TurnServerConfig> get turnServers => _node.turnServers;
  List<String> get connectedBootstrapServers => _node.connectedBootstrapServers;
  bool? turnServerHealthy(String url) => _node.turnAllocator.isHealthy(url);
  TurnAllocator get turnAllocator => _node.turnAllocator;
  String? get activeBootstrapServer => _node.activeBootstrapServer;
  SignalingConnectionStatus get bootstrapConnectionStatus =>
      _node.bootstrapConnectionStatus;
  Stream<SignalingConnectionStatus> get bootstrapConnectionStatusStream =>
      _node.bootstrapConnectionStatusStream;
  String? get bootstrapLastError => _node.bootstrapLastError;
  Stream<String?> get bootstrapLastErrorStream =>
      _node.bootstrapLastErrorStream;
  Stream<List<String>> get discoveredPeersStream => _node.discoveredPeersStream;
  Stream<PeerPresenceUpdate> get peerPresenceStream => _node.peerPresenceStream;
  bool isPeerOnline(String peerId) => _node.isPeerOnline(peerId);
  DateTime? peerLastSeenAt(String peerId) => _node.peerLastSeenAt(peerId);

  Future<void> addBootstrapServer(String endpoint) {
    return _node.addBootstrapServer(endpoint);
  }

  Future<void> removeBootstrapServer(String endpoint) {
    return _node.removeBootstrapServer(endpoint);
  }

  Future<void> configureBootstrapServers(List<String> endpoints) {
    return _node.configureBootstrapServers(endpoints);
  }

  Future<void> addRelayServer(String endpoint) {
    return _node.addRelayServer(endpoint);
  }

  Future<void> removeRelayServer(String endpoint) {
    return _node.removeRelayServer(endpoint);
  }

  Future<void> configureRelayServers(List<String> endpoints) {
    return _node.configureRelayServers(endpoints);
  }

  Future<void> configureTurnServers(List<TurnServerConfig> servers) {
    return _node.configureTurnServers(servers);
  }

  Future<void> updateFcmToken(String? token) {
    return _node.updateFcmToken(token);
  }

  Future<void> registerPushDeviceToken(String? token) {
    return _node.registerPushDeviceToken(token);
  }

  Future<void> unregisterPushDeviceToken(String token) {
    return _node.unregisterPushDeviceToken(token);
  }

  Future<void> registerVoipDeviceToken(String token) {
    return _node.registerVoipDeviceToken(token);
  }

  Future<void> unregisterVoipDeviceToken(String token) {
    return _node.unregisterVoipDeviceToken(token);
  }

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
  }) {
    return _node.sendGroupPushEvent(
      groupId: groupId,
      messageId: messageId,
      recipientUserIds: recipientUserIds,
      relayServers: relayServers,
      notificationType: notificationType,
      relayServerId: relayServerId,
      relayScopeKind: relayScopeKind,
      relayBlobId: relayBlobId,
      relayMessageId: relayMessageId,
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
  }) {
    return _node.sendDirectPushEvent(
      directPeerId: directPeerId,
      messageId: messageId,
      relayServers: relayServers,
      notificationType: notificationType,
      relayServerId: relayServerId,
      relayScopeKind: relayScopeKind,
      relayBlobId: relayBlobId,
      relayMessageId: relayMessageId,
      data: data,
    );
  }

  Future<void> pollRelay({List<String>? relayServers}) {
    return _node.pollRelay(relayServers: relayServers);
  }
}
