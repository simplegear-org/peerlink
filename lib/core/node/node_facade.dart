import 'dart:typed_data';

import '../calls/call_models.dart';
import '../calls/call_service.dart';
import '../messaging/chat_service.dart';
import '../messaging/reliable_messaging_service.dart';
import '../relay/relay_models.dart';
import '../relay/relay_server_status.dart';
import '../runtime/account_membership_update_payload.dart';
import '../runtime/network_event.dart';
import '../runtime/network_event_bus.dart';
import '../security/account_identity.dart';
import '../signaling/signaling_service.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_server_config.dart';
import 'mesh_node.dart';
import 'node_facade_calls_delegate.dart';
import 'node_facade_events_delegate.dart';
import 'node_facade_identity_delegate.dart';
import 'node_facade_messaging_delegate.dart';
import 'node_facade_network_delegate.dart';
import 'peer_presence.dart';

/// Публичный фасад ядра для UI-слоя.
/// Здесь UI получает унифицированные entrypoints для messaging/blob операций.
class NodeFacade {
  final NodeFacadeIdentityDelegate _identity;
  final NodeFacadeMessagingDelegate _messaging;
  final NodeFacadeNetworkDelegate _network;
  final NodeFacadeCallsDelegate _calls;
  final NodeFacadeEventsDelegate _events;

  NodeFacade({
    required MeshNode node,
    required ChatService chat,
    required CallService calls,
    required NetworkEventBus events,
  }) : _identity = NodeFacadeIdentityDelegate(node.identity),
       _messaging = NodeFacadeMessagingDelegate(chat),
       _network = NodeFacadeNetworkDelegate(node),
       _calls = NodeFacadeCallsDelegate(node: node, calls: calls),
       _events = NodeFacadeEventsDelegate(events);

  String get peerId => _identity.peerId;
  String get accountId => _identity.accountId;
  String get activeAccountId => _identity.activeAccountId;
  String get homeAccountId => _identity.homeAccountId;
  String get deviceId => _identity.deviceId;
  AccountIdentity get accountIdentity => _identity.accountIdentity;
  String? get endpointId => _identity.endpointId;
  String? get fcmTokenHash => _identity.fcmTokenHash;

  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity incoming) {
    return _identity.mergeAccountIdentity(incoming);
  }

  Future<AccountIdentity> resetToNewLocalAccount() {
    return _identity.resetToNewLocalAccount();
  }

  Future<void> clearPersistedIdentity({required bool preserveDeviceKeys}) {
    return _identity.clearPersistedIdentity(
      preserveDeviceKeys: preserveDeviceKeys,
    );
  }

  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) {
    return _identity.issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice,
      sessionId: sessionId,
    );
  }

  Future<AccountIdentity> applyApprovedPairingAccountIdentity({
    required AccountIdentity incoming,
    required String expectedSessionId,
    required String expectedAccountId,
  }) {
    return _identity.applyApprovedPairingAccountIdentity(
      incoming: incoming,
      expectedSessionId: expectedSessionId,
      expectedAccountId: expectedAccountId,
    );
  }

  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  }) {
    return _identity.issueRevokedAccountIdentity(
      revokedDeviceIds: revokedDeviceIds,
    );
  }

  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) {
    return _identity.signAccountMembershipUpdate(
      identity: identity,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
    );
  }

  Future<AccountIdentity> applyAccountMembershipUpdate({
    required AccountIdentity incoming,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  }) {
    return _identity.applyAccountMembershipUpdate(
      incoming: incoming,
      actorDeviceId: actorDeviceId,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
      signature: signature,
    );
  }

  Future<ChatSendReceipt> sendPayload(
    String targetId, {
    ChatPayloadTargetKind targetKind = ChatPayloadTargetKind.direct,
    List<String>? recipients,
    required String text,
    String kind = 'text',
    String? messageId,
    String? fileName,
    String? mimeType,
    String? transferId,
    int? totalBytes,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
  }) {
    return _messaging.sendPayload(
      targetId,
      targetKind: targetKind,
      recipients: recipients,
      text: text,
      kind: kind,
      messageId: messageId,
      fileName: fileName,
      mimeType: mimeType,
      transferId: transferId,
      totalBytes: totalBytes,
      replyToMessageId: replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel,
      replyToTextPreview: replyToTextPreview,
      replyToKind: replyToKind,
    );
  }

  Future<void> updateRelayGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  }) {
    return _messaging.updateRelayGroupMembers(
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
    );
  }

  Future<String> uploadBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    return _messaging.uploadBlob(
      scopeKind: scopeKind,
      targetId: targetId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      blobId: blobId,
      onProgress: onProgress,
    );
  }

  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    return _messaging.downloadBlob(blobId, onProgress: onProgress);
  }

  Future<void> sendDeleteMessage(String peerId, String messageId) {
    return _messaging.sendDeleteMessage(peerId, messageId);
  }

  Future<void> sendPlainControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _messaging.sendPlainControlMessage(peerId, kind: kind, text: text);
  }

  Future<void> sendAccountMembershipUpdatePushEvent({
    required String directPeerId,
    required AccountMembershipUpdatePayload update,
  }) {
    return _network.sendAccountMembershipUpdatePushEvent(
      directPeerId: directPeerId,
      update: update,
    );
  }

  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _messaging.sendControlMessage(peerId, kind: kind, text: text);
  }

  Future<void> sendFile(
    String peerId, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int totalBytes,
    String? mimeType,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
    required bool Function() isCancelled,
    required void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })
    onProgress,
  }) {
    return _messaging.sendFile(
      peerId,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      totalBytes: totalBytes,
      mimeType: mimeType,
      replyToMessageId: replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel,
      replyToTextPreview: replyToTextPreview,
      replyToKind: replyToKind,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }

  Future<void> connectToPeer(String peerId) {
    return _network.connectToPeer(peerId);
  }

  List<String> get bootstrapServers => _network.bootstrapServers;
  List<String> get relayServers => _network.relayServers;
  List<RelayServerStatus> get relayServerStatuses =>
      _network.relayServerStatuses;
  List<TurnServerConfig> get turnServers => _network.turnServers;
  List<String> get connectedBootstrapServers =>
      _network.connectedBootstrapServers;
  bool? turnServerHealthy(String url) => _network.turnServerHealthy(url);
  TurnAllocator get turnAllocator => _network.turnAllocator;
  String? get activeBootstrapServer => _network.activeBootstrapServer;
  SignalingConnectionStatus get bootstrapConnectionStatus =>
      _network.bootstrapConnectionStatus;
  Stream<SignalingConnectionStatus> get bootstrapConnectionStatusStream =>
      _network.bootstrapConnectionStatusStream;
  String? get bootstrapLastError => _network.bootstrapLastError;
  Stream<String?> get bootstrapLastErrorStream =>
      _network.bootstrapLastErrorStream;
  Stream<List<String>> get discoveredPeersStream =>
      _network.discoveredPeersStream;
  Stream<PeerPresenceUpdate> get peerPresenceStream =>
      _network.peerPresenceStream;
  bool isPeerOnline(String peerId) => _network.isPeerOnline(peerId);
  DateTime? peerLastSeenAt(String peerId) => _network.peerLastSeenAt(peerId);

  Future<void> addBootstrapServer(String endpoint) {
    return _network.addBootstrapServer(endpoint);
  }

  Future<void> removeBootstrapServer(String endpoint) {
    return _network.removeBootstrapServer(endpoint);
  }

  Future<void> configureBootstrapServers(List<String> endpoints) {
    return _network.configureBootstrapServers(endpoints);
  }

  Future<void> addRelayServer(String endpoint) {
    return _network.addRelayServer(endpoint);
  }

  Future<void> removeRelayServer(String endpoint) {
    return _network.removeRelayServer(endpoint);
  }

  Future<void> configureRelayServers(List<String> endpoints) {
    return _network.configureRelayServers(endpoints);
  }

  Future<void> configureTurnServers(List<TurnServerConfig> servers) {
    return _network.configureTurnServers(servers);
  }

  Future<void> updateFcmToken(String? token) {
    return _network.updateFcmToken(token);
  }

  Future<void> registerPushDeviceToken(String? token) {
    return _network.registerPushDeviceToken(token);
  }

  Future<void> unregisterPushDeviceToken(String token) {
    return _network.unregisterPushDeviceToken(token);
  }

  Future<void> registerVoipDeviceToken(String token) {
    return _network.registerVoipDeviceToken(token);
  }

  Future<void> unregisterVoipDeviceToken(String token) {
    return _network.unregisterVoipDeviceToken(token);
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
    return _network.sendGroupPushEvent(
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
    return _network.sendDirectPushEvent(
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
    return _network.pollRelay(relayServers: relayServers);
  }

  CallState get callState => _calls.callState;
  Stream<CallState> get callStateStream => _calls.callStateStream;

  Future<void> startCall(String peerId) {
    return _calls.startCall(peerId);
  }

  Future<void> startVideoCall(String peerId) {
    return _calls.startVideoCall(peerId);
  }

  Future<void> acceptIncomingCall() {
    return _calls.acceptIncomingCall();
  }

  Future<void> rejectIncomingCall() {
    return _calls.rejectIncomingCall();
  }

  Future<void> endCall() {
    return _calls.endCall();
  }

  Future<void> toggleCallMuted() {
    return _calls.toggleCallMuted();
  }

  Future<void> toggleCallVideo() {
    return _calls.toggleCallVideo();
  }

  Future<void> flipCallCamera() {
    return _calls.flipCallCamera();
  }

  Future<void> setCallSpeakerOn(bool enabled) {
    return _calls.setCallSpeakerOn(enabled);
  }

  Future<void> presentIncomingCallFromPush({
    required String peerId,
    required String callId,
    CallMediaType mediaType = CallMediaType.audio,
  }) {
    return _calls.presentIncomingCallFromPush(
      peerId: peerId,
      callId: callId,
      mediaType: mediaType,
    );
  }

  Future<void> endCallFromRemotePush({
    required String peerId,
    required String callId,
  }) {
    return _calls.endCallFromRemotePush(peerId: peerId, callId: callId);
  }

  Stream<NetworkEvent> get messageEvents => _events.messageEvents;

  NetworkEventHandlerRegistration addMessageEventHandler(
    NetworkEventHandler handler,
  ) {
    return _events.addMessageEventHandler(handler);
  }

  Stream<String> get peerConnectedStream => _events.peerConnectedStream;
  Stream<String> get peerDisconnectedStream => _events.peerDisconnectedStream;
}
