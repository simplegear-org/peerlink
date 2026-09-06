// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/node/peer_presence.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/relay/relay_server_status.dart';
import 'package:peerlink/core/runtime/account_membership_update_payload.dart';
import 'package:peerlink/core/runtime/network_event.dart';
import 'package:peerlink/core/runtime/network_event_bus.dart';
import 'package:peerlink/core/security/account_identity.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/turn/turn_allocator.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';

class ChatRuntimeNodeAdapter implements ChatRuntimeApi {
  const ChatRuntimeNodeAdapter(this._facade);

  final NodeFacade _facade;

  @override
  String get peerId => _facade.peerId;
  @override
  String get accountId => _facade.accountId;
  @override
  String get activeAccountId => _facade.activeAccountId;
  @override
  String get homeAccountId => _facade.homeAccountId;
  @override
  String get deviceId => _facade.deviceId;
  @override
  AccountIdentity get accountIdentity => _facade.accountIdentity;
  @override
  String? get endpointId => _facade.endpointId;
  @override
  String? get fcmTokenHash => _facade.fcmTokenHash;
  @override
  Map<String, dynamic> get identityBundleV3Json => _facade.identityBundleV3Json;

  @override
  Future<bool> trustPeerIdentityBundleV3(
    Map<String, dynamic> bundle, {
    String? expectedPeerId,
  }) {
    return _facade.trustPeerIdentityBundleV3(
      bundle,
      expectedPeerId: expectedPeerId,
    );
  }

  @override
  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity incoming) =>
      _facade.mergeAccountIdentity(incoming);

  @override
  Future<AccountIdentity> resetToNewLocalAccount() =>
      _facade.resetToNewLocalAccount();

  @override
  Future<void> clearPersistedIdentity({required bool preserveDeviceKeys}) =>
      _facade.clearPersistedIdentity(preserveDeviceKeys: preserveDeviceKeys);

  @override
  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) {
    return _facade.issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice,
      sessionId: sessionId,
    );
  }

  @override
  Future<AccountIdentity> applyApprovedPairingAccountIdentity({
    required AccountIdentity incoming,
    required String expectedSessionId,
    required String expectedAccountId,
  }) {
    return _facade.applyApprovedPairingAccountIdentity(
      incoming: incoming,
      expectedSessionId: expectedSessionId,
      expectedAccountId: expectedAccountId,
    );
  }

  @override
  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  }) {
    return _facade.issueRevokedAccountIdentity(
      revokedDeviceIds: revokedDeviceIds,
    );
  }

  @override
  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) {
    return _facade.signAccountMembershipUpdate(
      identity: identity,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
    );
  }

  @override
  Future<AccountIdentity> applyAccountMembershipUpdate({
    required AccountIdentity incoming,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  }) {
    return _facade.applyAccountMembershipUpdate(
      incoming: incoming,
      actorDeviceId: actorDeviceId,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
      signature: signature,
    );
  }

  @override
  Future<void> submitModerationReport(Map<String, dynamic> report) =>
      _facade.submitModerationReport(report);

  @override
  Future<void> submitModerationAppeal(String text) =>
      _facade.submitModerationAppeal(text);

  @override
  Future<Map<String, dynamic>?> fetchModerationStatus() =>
      _facade.fetchModerationStatus();

  @override
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
    return _facade.sendPayload(
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

  @override
  Future<void> updateRelayGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  }) {
    return _facade.updateRelayGroupMembers(
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
    );
  }

  @override
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
    return _facade.uploadBlob(
      scopeKind: scopeKind,
      targetId: targetId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      blobId: blobId,
      onProgress: onProgress,
    );
  }

  @override
  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    return _facade.downloadBlob(blobId, onProgress: onProgress);
  }

  @override
  Future<Uint8List> encryptDirectBytes(String peerId, Uint8List plainBytes) =>
      _facade.encryptDirectBytes(peerId, plainBytes);

  @override
  Future<Uint8List> decryptDirectBytes(
    String peerId,
    Uint8List encryptedBytes,
  ) {
    return _facade.decryptDirectBytes(peerId, encryptedBytes);
  }

  @override
  Future<void> discardPendingPayload({
    required ChatPayloadTargetKind targetKind,
    required String targetId,
    required String messageId,
  }) {
    return _facade.discardPendingPayload(
      targetKind: targetKind,
      targetId: targetId,
      messageId: messageId,
    );
  }

  @override
  Future<void> sendDeleteMessage(String peerId, String messageId) =>
      _facade.sendDeleteMessage(peerId, messageId);

  @override
  Future<void> sendPlainControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _facade.sendPlainControlMessage(peerId, kind: kind, text: text);
  }

  @override
  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _facade.sendControlMessage(peerId, kind: kind, text: text);
  }

  @override
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
    return _facade.sendFile(
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

  @override
  Future<void> sendAccountMembershipUpdatePushEvent({
    required String directPeerId,
    required AccountMembershipUpdatePayload update,
  }) {
    return _facade.sendAccountMembershipUpdatePushEvent(
      directPeerId: directPeerId,
      update: update,
    );
  }

  @override
  Future<void> connectToPeer(String peerId) => _facade.connectToPeer(peerId);
  @override
  List<String> get bootstrapServers => _facade.bootstrapServers;
  @override
  List<String> get relayServers => _facade.relayServers;
  @override
  List<RelayServerStatus> get relayServerStatuses =>
      _facade.relayServerStatuses;
  @override
  List<TurnServerConfig> get turnServers => _facade.turnServers;
  @override
  List<String> get connectedBootstrapServers =>
      _facade.connectedBootstrapServers;
  @override
  bool? turnServerHealthy(String url) => _facade.turnServerHealthy(url);
  @override
  TurnAllocator get turnAllocator => _facade.turnAllocator;
  @override
  String? get activeBootstrapServer => _facade.activeBootstrapServer;
  @override
  SignalingConnectionStatus get bootstrapConnectionStatus =>
      _facade.bootstrapConnectionStatus;
  @override
  Stream<SignalingConnectionStatus> get bootstrapConnectionStatusStream =>
      _facade.bootstrapConnectionStatusStream;
  @override
  String? get bootstrapLastError => _facade.bootstrapLastError;
  @override
  Stream<String?> get bootstrapLastErrorStream =>
      _facade.bootstrapLastErrorStream;
  @override
  Stream<List<String>> get discoveredPeersStream =>
      _facade.discoveredPeersStream;
  @override
  Stream<PeerPresenceUpdate> get peerPresenceStream =>
      _facade.peerPresenceStream;
  @override
  bool isPeerOnline(String peerId) => _facade.isPeerOnline(peerId);
  @override
  DateTime? peerLastSeenAt(String peerId) => _facade.peerLastSeenAt(peerId);
  @override
  Future<void> addBootstrapServer(String endpoint) =>
      _facade.addBootstrapServer(endpoint);
  @override
  Future<void> removeBootstrapServer(String endpoint) =>
      _facade.removeBootstrapServer(endpoint);
  @override
  Future<void> configureBootstrapServers(List<String> endpoints) =>
      _facade.configureBootstrapServers(endpoints);
  @override
  Future<void> addRelayServer(String endpoint) =>
      _facade.addRelayServer(endpoint);
  @override
  Future<void> removeRelayServer(String endpoint) =>
      _facade.removeRelayServer(endpoint);
  @override
  Future<void> configureRelayServers(List<String> endpoints) =>
      _facade.configureRelayServers(endpoints);
  @override
  Future<void> configureTurnServers(List<TurnServerConfig> servers) =>
      _facade.configureTurnServers(servers);
  @override
  Future<void> updateFcmToken(String? token) => _facade.updateFcmToken(token);
  @override
  Future<void> registerPushDeviceToken(String? token, {bool force = false}) =>
      _facade.registerPushDeviceToken(token, force: force);
  @override
  Future<void> syncPushDeviceState({
    required String reason,
    bool forceRegister = false,
    bool forcePolicy = true,
  }) {
    return _facade.syncPushDeviceState(
      reason: reason,
      forceRegister: forceRegister,
      forcePolicy: forcePolicy,
    );
  }

  @override
  Future<void> unregisterPushDeviceToken(String token) =>
      _facade.unregisterPushDeviceToken(token);
  @override
  Future<void> registerVoipDeviceToken(String token) =>
      _facade.registerVoipDeviceToken(token);
  @override
  Future<void> unregisterVoipDeviceToken(String token) =>
      _facade.unregisterVoipDeviceToken(token);
  @override
  Future<void> syncPushAccessPolicy({
    required String reason,
    bool force = false,
  }) {
    return _facade.syncPushAccessPolicy(reason: reason, force: force);
  }

  @override
  Future<void> retryPendingPushAccessPolicySync({required String reason}) =>
      _facade.retryPendingPushAccessPolicySync(reason: reason);
  @override
  Future<void> retryPendingPushDeviceStateSync({required String reason}) =>
      _facade.retryPendingPushDeviceStateSync(reason: reason);
  @override
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
    return _facade.sendGroupPushEvent(
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

  @override
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
    return _facade.sendDirectPushEvent(
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

  @override
  Future<int> pollRelay({List<String>? relayServers}) =>
      _facade.pollRelay(relayServers: relayServers);

  @override
  CallState get callState => _facade.callState;
  @override
  Stream<CallState> get callStateStream => _facade.callStateStream;
  @override
  Future<void> startCall(String peerId) => _facade.startCall(peerId);
  @override
  Future<void> startVideoCall(String peerId) => _facade.startVideoCall(peerId);
  @override
  Future<void> acceptIncomingCall() => _facade.acceptIncomingCall();
  @override
  Future<void> rejectIncomingCall() => _facade.rejectIncomingCall();
  @override
  Future<void> endCall() => _facade.endCall();
  @override
  Future<void> toggleCallMuted() => _facade.toggleCallMuted();
  @override
  Future<void> toggleCallVideo() => _facade.toggleCallVideo();
  @override
  Future<void> flipCallCamera() => _facade.flipCallCamera();
  @override
  Future<void> setCallSpeakerOn(bool enabled) =>
      _facade.setCallSpeakerOn(enabled);
  @override
  Future<void> presentIncomingCallFromPush({
    required String peerId,
    required String callId,
    CallMediaType mediaType = CallMediaType.audio,
  }) {
    return _facade.presentIncomingCallFromPush(
      peerId: peerId,
      callId: callId,
      mediaType: mediaType,
    );
  }

  @override
  Future<void> endCallFromRemotePush({
    required String peerId,
    required String callId,
  }) {
    return _facade.endCallFromRemotePush(peerId: peerId, callId: callId);
  }

  @override
  Stream<NetworkEvent> get messageEvents => _facade.messageEvents;
  @override
  NetworkEventHandlerRegistration addMessageEventHandler(
    NetworkEventHandler handler,
  ) {
    return _facade.addMessageEventHandler(handler);
  }

  @override
  Stream<String> get peerConnectedStream => _facade.peerConnectedStream;
  @override
  Stream<String> get peerDisconnectedStream => _facade.peerDisconnectedStream;
}
