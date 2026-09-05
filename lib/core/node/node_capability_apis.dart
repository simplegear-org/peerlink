// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import '../calls/call_models.dart';
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
import 'peer_presence.dart';

abstract interface class IdentityApi {
  String get peerId;
  String get accountId;
  String get activeAccountId;
  String get homeAccountId;
  String get deviceId;
  AccountIdentity get accountIdentity;
  String? get endpointId;
  String? get fcmTokenHash;
  Map<String, dynamic> get identityBundleV3Json;

  Future<bool> trustPeerIdentityBundleV3(
    Map<String, dynamic> bundle, {
    String? expectedPeerId,
  });

  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity incoming);
  Future<AccountIdentity> resetToNewLocalAccount();
  Future<void> clearPersistedIdentity({required bool preserveDeviceKeys});
  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  });
  Future<AccountIdentity> applyApprovedPairingAccountIdentity({
    required AccountIdentity incoming,
    required String expectedSessionId,
    required String expectedAccountId,
  });
  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  });
  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  });
  Future<AccountIdentity> applyAccountMembershipUpdate({
    required AccountIdentity incoming,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  });
}

abstract interface class ModerationApi {
  Future<void> submitModerationReport(Map<String, dynamic> report);
  Future<void> submitModerationAppeal(String text);
  Future<Map<String, dynamic>?> fetchModerationStatus();
}

abstract interface class MessagingApi {
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
  });

  Future<void> updateRelayGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  });

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
  });

  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  });

  Future<Uint8List> encryptDirectBytes(String peerId, Uint8List plainBytes);
  Future<Uint8List> decryptDirectBytes(String peerId, Uint8List encryptedBytes);
  Future<void> discardPendingPayload({
    required ChatPayloadTargetKind targetKind,
    required String targetId,
    required String messageId,
  });
  Future<void> sendDeleteMessage(String peerId, String messageId);
  Future<void> sendPlainControlMessage(
    String peerId, {
    required String kind,
    required String text,
  });
  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  });
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
  });
}

abstract interface class NetworkApi {
  Future<void> sendAccountMembershipUpdatePushEvent({
    required String directPeerId,
    required AccountMembershipUpdatePayload update,
  });
  Future<void> connectToPeer(String peerId);
  List<String> get bootstrapServers;
  List<String> get relayServers;
  List<RelayServerStatus> get relayServerStatuses;
  List<TurnServerConfig> get turnServers;
  List<String> get connectedBootstrapServers;
  bool? turnServerHealthy(String url);
  TurnAllocator get turnAllocator;
  String? get activeBootstrapServer;
  SignalingConnectionStatus get bootstrapConnectionStatus;
  Stream<SignalingConnectionStatus> get bootstrapConnectionStatusStream;
  String? get bootstrapLastError;
  Stream<String?> get bootstrapLastErrorStream;
  Stream<List<String>> get discoveredPeersStream;
  Stream<PeerPresenceUpdate> get peerPresenceStream;
  bool isPeerOnline(String peerId);
  DateTime? peerLastSeenAt(String peerId);
  Future<void> addBootstrapServer(String endpoint);
  Future<void> removeBootstrapServer(String endpoint);
  Future<void> configureBootstrapServers(List<String> endpoints);
  Future<void> addRelayServer(String endpoint);
  Future<void> removeRelayServer(String endpoint);
  Future<void> configureRelayServers(List<String> endpoints);
  Future<void> configureTurnServers(List<TurnServerConfig> servers);
  Future<void> updateFcmToken(String? token);
  Future<void> registerPushDeviceToken(String? token, {bool force = false});
  Future<void> syncPushDeviceState({
    required String reason,
    bool forceRegister = false,
    bool forcePolicy = true,
  });
  Future<void> unregisterPushDeviceToken(String token);
  Future<void> registerVoipDeviceToken(String token);
  Future<void> unregisterVoipDeviceToken(String token);
  Future<void> syncPushAccessPolicy({
    required String reason,
    bool force = false,
  });
  Future<void> retryPendingPushAccessPolicySync({required String reason});
  Future<void> retryPendingPushDeviceStateSync({required String reason});
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
  });
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
  });
  Future<int> pollRelay({List<String>? relayServers});
}

abstract interface class CallsApi {
  CallState get callState;
  Stream<CallState> get callStateStream;
  Future<void> startCall(String peerId);
  Future<void> startVideoCall(String peerId);
  Future<void> acceptIncomingCall();
  Future<void> rejectIncomingCall();
  Future<void> endCall();
  Future<void> toggleCallMuted();
  Future<void> toggleCallVideo();
  Future<void> flipCallCamera();
  Future<void> setCallSpeakerOn(bool enabled);
  Future<void> presentIncomingCallFromPush({
    required String peerId,
    required String callId,
    CallMediaType mediaType = CallMediaType.audio,
  });
  Future<void> endCallFromRemotePush({
    required String peerId,
    required String callId,
  });
}

abstract interface class RuntimeEventsApi {
  Stream<NetworkEvent> get messageEvents;
  NetworkEventHandlerRegistration addMessageEventHandler(
    NetworkEventHandler handler,
  );
  Stream<String> get peerConnectedStream;
  Stream<String> get peerDisconnectedStream;
}
