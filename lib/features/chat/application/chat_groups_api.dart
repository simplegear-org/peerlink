// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_group_crypto_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_inbound_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_outbound_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_service.dart';
import 'package:peerlink/features/chat/application/chat_history_load_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_summary_service.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_coordinator.dart';
import 'package:peerlink/features/chat/domain/chat.dart';

abstract interface class ChatGroupsApi {
  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberPeerIds,
    bool sendInvites,
  });

  Future<void> addGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  });

  Future<void> removeGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  });

  Future<void> renameGroupChat({
    required String groupId,
    required String newName,
  });

  Future<void> setGroupAvatar({
    required String groupId,
    required Uint8List bytes,
    String mimeType,
  });

  Future<void> saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  });

  Future<void> requestDeleteForEveryone(String peerId, String messageId);

  Future<void> applyGroupMembersUpdateFromPush(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  });

  Future<void> handleIncomingGroupMembersUpdate(
    ChatMessage message, {
    IncomingGroupMembersPayload? payload,
  });

  Future<void> rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  });

  Future<void> syncGroupMembershipWithRelay(Chat groupChat);

  Future<String?> decryptGroupText(String text);

  Future<Uint8List?> decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  });

  Future<Uint8List> decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  });

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

  bool isGroupDeletePayload(String text);

  bool isGroupDeleted(String groupId);

  Future<void> rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  });

  Future<void> restoreDeletedGroup(String groupId);

  Future<void> runGroupKeyGc();

  Future<void> deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup,
    String? deletedByPeerId,
  });
}

class ChatControllerGroupsApi implements ChatGroupsApi {
  const ChatControllerGroupsApi({
    required ChatGroupService groupService,
    required ChatGroupCryptoCoordinator groupCryptoCoordinator,
    required ChatGroupOutboundCoordinator groupOutboundCoordinator,
    required ChatGroupInboundCoordinator groupInboundCoordinator,
    required ChatSummaryService summaryService,
    required ChatHistoryLoadCoordinator historyLoadCoordinator,
    required ChatCleanupCoordinator cleanupCoordinator,
    required Map<String, Chat> chats,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
    required String groupDeletePrefix,
  }) : _groupService = groupService,
       _groupCryptoCoordinator = groupCryptoCoordinator,
       _groupOutboundCoordinator = groupOutboundCoordinator,
       _groupInboundCoordinator = groupInboundCoordinator,
       _summaryService = summaryService,
       _historyLoadCoordinator = historyLoadCoordinator,
       _cleanupCoordinator = cleanupCoordinator,
       _chats = chats,
       _persistChatSummary = persistChatSummary,
       _notifyMessageUpdated = notifyMessageUpdated,
       _groupDeletePrefix = groupDeletePrefix;

  final ChatGroupService _groupService;
  final ChatGroupCryptoCoordinator _groupCryptoCoordinator;
  final ChatGroupOutboundCoordinator _groupOutboundCoordinator;
  final ChatGroupInboundCoordinator _groupInboundCoordinator;
  final ChatSummaryService _summaryService;
  final ChatHistoryLoadCoordinator _historyLoadCoordinator;
  final ChatCleanupCoordinator _cleanupCoordinator;
  final Map<String, Chat> _chats;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final void Function(String peerId) _notifyMessageUpdated;
  final String _groupDeletePrefix;

  @override
  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberPeerIds,
    bool sendInvites = true,
  }) {
    return _groupService.createGroupChat(
      name: name,
      memberPeerIds: memberPeerIds,
      chats: _chats,
      sendInvites: sendInvites,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  @override
  Future<void> addGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) {
    return _groupService.addGroupParticipants(
      groupId: groupId,
      participantPeerIds: participantPeerIds,
      chats: _chats,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  @override
  Future<void> removeGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) {
    return _groupService.removeGroupParticipants(
      groupId: groupId,
      participantPeerIds: participantPeerIds,
      chats: _chats,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  @override
  Future<void> renameGroupChat({
    required String groupId,
    required String newName,
  }) {
    return _groupService.renameGroupChat(
      groupId: groupId,
      newName: newName,
      chats: _chats,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  @override
  Future<void> setGroupAvatar({
    required String groupId,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) {
    return _groupService.setGroupAvatar(
      groupId: groupId,
      chats: _chats,
      bytes: bytes,
      mimeType: mimeType,
      persistChatSummary: _persistChatSummary,
      encryptGroupBytes: _groupCryptoCoordinator.encryptGroupBytes,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  @override
  Future<void> saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) {
    return _groupService.saveGroupAvatarBytes(
      groupChat: groupChat,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: updatedAtMs,
      persistChatSummary: _persistChatSummary,
    );
  }

  @override
  Future<void> requestDeleteForEveryone(String peerId, String messageId) {
    return _groupOutboundCoordinator.requestDeleteForEveryone(
      peerId,
      messageId,
      chat: _chats[peerId],
    );
  }

  @override
  Future<void> applyGroupMembersUpdateFromPush(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  }) {
    return _groupOutboundCoordinator.applyGroupMembersUpdateFromPush(
      payload,
      sourcePeerId: sourcePeerId,
    );
  }

  @override
  Future<void> handleIncomingGroupMembersUpdate(
    ChatMessage message, {
    IncomingGroupMembersPayload? payload,
  }) {
    return _groupInboundCoordinator.handleMembersUpdate(
      message,
      payload: payload,
    );
  }

  @override
  Future<void> rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) {
    return _groupCryptoCoordinator.rotateGroupKey(
      groupChat,
      recipients: recipients,
    );
  }

  @override
  Future<void> syncGroupMembershipWithRelay(Chat groupChat) {
    return _groupCryptoCoordinator.syncGroupMembershipWithRelay(groupChat);
  }

  @override
  Future<String?> decryptGroupText(String text) {
    return _groupCryptoCoordinator.decryptGroupText(text);
  }

  @override
  Future<Uint8List?> decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) {
    return _groupCryptoCoordinator.decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  @override
  Future<Uint8List> decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) {
    return _groupCryptoCoordinator.decodeGroupBlobBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  @override
  Future<void> broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) {
    return _groupOutboundCoordinator.broadcastGroupMembersUpdate(
      groupChat: groupChat,
      recipients: recipients,
      action: action,
      changedPeerIds: changedPeerIds,
      avatarBlobId: avatarBlobId,
      avatarMimeType: avatarMimeType,
      avatarFileSizeBytes: avatarFileSizeBytes,
      avatarUpdatedAtMs: avatarUpdatedAtMs,
    );
  }

  @override
  bool isGroupDeletePayload(String text) {
    return text.startsWith(_groupDeletePrefix);
  }

  @override
  bool isGroupDeleted(String groupId) {
    return _summaryService.isGroupDeleted(groupId);
  }

  @override
  Future<void> rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  }) {
    return _summaryService.rememberDeletedGroup(
      groupId,
      deletedByPeerId: deletedByPeerId,
      chat: chat,
    );
  }

  @override
  Future<void> restoreDeletedGroup(String groupId) {
    return _summaryService.restoreDeletedGroup(groupId);
  }

  @override
  Future<void> runGroupKeyGc() {
    return _historyLoadCoordinator.runGroupKeyGc();
  }

  @override
  Future<void> deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup = false,
    String? deletedByPeerId,
  }) {
    return _cleanupCoordinator.deleteChatLocal(
      peerId,
      rememberDeletedGroup: rememberDeletedGroup,
      deletedByPeerId: deletedByPeerId,
    );
  }
}
