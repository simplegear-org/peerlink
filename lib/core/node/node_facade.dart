import 'dart:typed_data';

import '../messaging/chat_service.dart';
import '../messaging/reliable_messaging_service.dart';
import '../relay/http_relay_client.dart';
import '../relay/relay_models.dart';
import '../runtime/network_event.dart';
import '../runtime/network_event_bus.dart';
import '../calls/call_models.dart';
import '../calls/call_service.dart';
import '../signaling/signaling_service.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_server_config.dart';
import 'peer_presence.dart';
import 'mesh_node.dart';

/// Публичный фасад ядра для UI-слоя.
/// Здесь UI получает унифицированные entrypoints для messaging/blob операций.
class NodeFacade {
  final MeshNode _node;
  final ChatService _chat;
  final CallService _calls;
  final NetworkEventBus _events;

  NodeFacade({
    required MeshNode node,
    required ChatService chat,
    required CallService calls,
    required NetworkEventBus events,
  }) : _node = node,
       _chat = chat,
       _calls = calls,
       _events = events;

  /// Текущий peerId локального узла.
  String get peerId => _node.identity.nodeId;
  String get legacyPeerId => _node.identity.legacyNodeId;
  String? get endpointId => _node.identity.endpointId;
  String? get fcmTokenHash => _node.identity.fcmTokenHash;

  /// Унифицированная отправка payload в direct/group target.
  Future<void> sendPayload(
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
  }) async {
    await _chat.sendPayload(
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
    return _chat.updateGroupMembers(
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
    );
  }

  /// Унифицированная загрузка blob в direct/group relay scope.
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
    return _chat.uploadBlob(
      scopeKind: scopeKind,
      targetId: targetId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      blobId: blobId,
      onProgress: onProgress,
    );
  }

  /// Скачивает blob по `blobId` независимо от исходного direct/group scope.
  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    return _chat.downloadBlob(blobId, onProgress: onProgress);
  }

  Future<void> sendDeleteMessage(String peerId, String messageId) async {
    await _chat.sendControlMessage(peerId, kind: 'delete', text: messageId);
  }

  Future<void> sendPlainControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) async {
    await _chat.sendControlMessage(
      peerId,
      kind: kind,
      text: text,
      forcePlain: true,
    );
  }

  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) async {
    await _chat.sendControlMessage(peerId, kind: kind, text: text);
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
  }) async {
    await _chat.sendFile(
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

  /// Явно инициирует подключение к peer (поднятие transport-сессии).
  Future<void> connectToPeer(String peerId) async {
    await _node.connectTo(peerId);
  }

  /// Список bootstrap-серверов, доступный из UI.
  List<String> get bootstrapServers => _node.bootstrapServers;

  /// Список message relay-серверов, доступный из UI.
  List<String> get relayServers => _node.relayServers;
  List<RelayServerStatus> get relayServerStatuses => _node.relayServerStatuses;
  List<TurnServerConfig> get turnServers => _node.turnServers;
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

  /// Добавляет bootstrap-сервер из UI.
  Future<void> addBootstrapServer(String endpoint) {
    return _node.addBootstrapServer(endpoint);
  }

  /// Удаляет bootstrap-сервер из UI.
  Future<void> removeBootstrapServer(String endpoint) {
    return _node.removeBootstrapServer(endpoint);
  }

  /// Полностью конфигурирует bootstrap-серверы из UI/настроек.
  Future<void> configureBootstrapServers(List<String> endpoints) {
    return _node.configureBootstrapServers(endpoints);
  }

  /// Добавляет message relay-сервер из UI.
  Future<void> addRelayServer(String endpoint) {
    return _node.addRelayServer(endpoint);
  }

  /// Удаляет message relay-сервер из UI.
  Future<void> removeRelayServer(String endpoint) {
    return _node.removeRelayServer(endpoint);
  }

  /// Полностью конфигурирует message relay-серверы из UI/настроек.
  Future<void> configureRelayServers(List<String> endpoints) {
    return _node.configureRelayServers(endpoints);
  }

  Future<void> configureTurnServers(List<TurnServerConfig> servers) {
    return _node.configureTurnServers(servers);
  }

  Future<void> updateFcmToken(String? token) {
    return _node.updateFcmToken(token);
  }

  /// Принудительный опрос message relay для фоновых задач.
  Future<void> pollRelay() {
    return _node.pollRelay();
  }

  CallState get callState => _calls.state;

  Stream<CallState> get callStateStream => _calls.stateStream;

  Future<void> startCall(String peerId) {
    return _calls.startOutgoingCall(peerId);
  }

  Future<void> startVideoCall(String peerId) {
    return _calls.startOutgoingCall(peerId, mediaType: CallMediaType.video);
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
    return _calls.toggleMuted();
  }

  Future<void> toggleCallVideo() {
    return _calls.toggleVideo();
  }

  Future<void> flipCallCamera() {
    return _calls.flipCamera();
  }

  Future<void> setCallSpeakerOn(bool enabled) {
    return _calls.setSpeakerOn(enabled);
  }

  /// Поток сетевых событий сообщений для UI-контроллеров.
  Stream<NetworkEvent> get messageEvents => _events.on<NetworkEvent>().where(
    (e) => e.type == NetworkEventType.messageReceived,
  );

  NetworkEventHandlerRegistration addMessageEventHandler(
    NetworkEventHandler handler,
  ) {
    return _events.addAwaitableHandler((event) {
      if (event.type != NetworkEventType.messageReceived) {
        return Future<void>.value();
      }
      return handler(event);
    });
  }

  Stream<String> get peerConnectedStream => _events
      .on<NetworkEvent>()
      .where((e) => e.type == NetworkEventType.peerConnected)
      .map((e) => e.payload as String);

  Stream<String> get peerDisconnectedStream => _events
      .on<NetworkEvent>()
      .where((e) => e.type == NetworkEventType.peerDisconnected)
      .map((e) => e.payload as String);
}
