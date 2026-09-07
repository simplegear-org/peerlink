// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/runtime/account_membership_update_payload.dart';
import 'package:peerlink/core/runtime/account_pairing_payload.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';

abstract interface class ChatPresentationStatePort {
  Map<String, Chat> get chats;

  String Function(String peerId, {String? fallback}) get contactNameFor;

  Chat ensureChat(String peerId, {String? fallbackName});

  Future<void> ensureChatLoaded(String peerId);

  Future<void> persistLoadedChat(String peerId);

  void schedulePersistLoadedChat(String peerId);

  Future<void> persistChatSummary(Chat chat);

  void schedulePersistChatSummary(String peerId);

  bool isInitialUnreadAnchor(Message message);
}

abstract interface class ChatConnectionStatePort {
  void setStatus(String peerId, ChatConnectionStatus status, {String? error});
}

abstract interface class ChatMessageStatePort {
  String nextLocalMessageId();

  Future<Message?> findMessage(String peerId, String messageId);

  Future<void> appendMessage(String peerId, Message message);

  Future<void> replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  );

  Future<bool> removeMessage(String peerId, String messageId);

  Future<bool> removeMessageWithMediaCleanup(String peerId, String messageId);

  Future<bool> removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  );

  Future<void> deleteManagedMediaForMessage(Message? message);

  Future<void> updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  );
}

abstract interface class ChatMediaStatePort {
  Future<void> updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  });

  void clearProgressUpdate(String peerId, String messageId);

  Future<String?> ensureThumbnail(Message message);

  String mediaKeyFor(String peerId, String messageId);

  Future<Uint8List> decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  });

  Future<void> rememberOutgoingRelayMediaState(OutgoingRelayMediaState state);

  Future<void> forgetOutgoingRelayMediaState(String peerId, String messageId);

  String transferStatusForError(Object error, {required String fallback});

  void restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force,
  });

  Future<String?> restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  });
}

abstract interface class ChatGroupStatePort {
  Future<void> handleIncomingGroupMembersUpdate(
    ChatMessage message, {
    IncomingGroupMembersPayload? payload,
  });

  Future<void> rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  });

  Future<void> runGroupKeyGc();

  bool isGroupDeleted(String groupId);

  Future<void> restoreDeletedGroup(String groupId);

  Future<String?> decryptGroupText(String text);

  Future<Uint8List?> decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  });

  Future<void> saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  });

  Future<void> rotateGroupKey(Chat chat, {required List<String> recipients});

  Future<void> syncGroupMembershipWithRelay(Chat chat);

  Future<void> broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  });

  Future<void> deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup,
    String? deletedByPeerId,
  });

  bool isGroupDeletePayload(String text);
}

abstract interface class ChatNotificationPort {
  void syncBadgeCount();

  void notifyMessageUpdated(String peerId);

  bool isMessageUpdatesClosed();

  int unreadMessagesCount();

  void Function(int unreadCount)? get onUnreadBadgeCountChanged;

  void notifyNewMessage(ChatMessage message);
}

abstract interface class ChatLifecyclePort {
  void logQueue(String message);

  void resumeRecoverableFileQueue();

  Future<void> resumePendingOutgoingRelayMedia({required String reason});

  Future<void> resumeInterruptedIncomingMediaQueue({required String reason});

  Future<void> waitUntilReady();
}

abstract interface class ChatInboundPort {
  Future<void> handleIncomingDirectBlobRef(
    ChatMessage message,
    IncomingBlobRefPayload blobRef,
  );

  Future<void> handleIncomingMessageReceipt(
    IncomingMessageReceiptPayload payload,
  );
}

abstract interface class ChatAccountPayloadPort {
  AccountPairingRequestPayloadDecoder get decodeAccountPairRequest;

  AccountPairingApprovalPayloadDecoder get decodeAccountPairApproval;

  AccountPairingRejectionPayloadDecoder get decodeAccountPairRejection;

  AccountMembershipUpdatePayloadDecoder get decodeAccountMembershipUpdate;
}

typedef AccountPairingRequestPayloadDecoder =
    AccountPairingRequestPayload? Function(ChatMessage message);
typedef AccountPairingApprovalPayloadDecoder =
    AccountPairingApprovalPayload? Function(ChatMessage message);
typedef AccountPairingRejectionPayloadDecoder =
    AccountPairingRejectedPayload? Function(ChatMessage message);
typedef AccountMembershipUpdatePayloadDecoder =
    AccountMembershipUpdatePayload? Function(ChatMessage message);
