import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:typed_data';

import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import 'chat_group_flow_service.dart';

class ChatGroupService {
  final NodeFacade facade;
  final StorageService storage;
  final ChatGroupFlowService groupFlowService;
  final Map<String, Future<Chat>> _groupCreateInFlight =
      <String, Future<Chat>>{};

  ChatGroupService({
    required this.facade,
    required this.storage,
    required this.groupFlowService,
  });

  Future<void> setGroupAvatar({
    required String groupId,
    required Map<String, Chat> chats,
    required Uint8List bytes,
    String mimeType = 'image/png',
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List plainBytes,
    })
    encryptGroupBytes,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw StateError('Group chat not found');
    }
    final owner = (chat.ownerPeerId ?? '').trim();
    if (owner.isNotEmpty && owner != facade.peerId) {
      throw StateError('Only group owner can change avatar');
    }
    if (bytes.isEmpty) {
      throw StateError('Avatar is empty');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final stagedPath = await _stageGroupAvatarBytes(
      groupId: chat.peerId,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: stamp,
    );
    final previousPath = chat.avatarPath;
    try {
      await _broadcastGroupAvatarUpdate(
        groupChat: chat,
        bytes: bytes,
        mimeType: mimeType,
        updatedAtMs: stamp,
        encryptGroupBytes: encryptGroupBytes,
      );
      await _commitGroupAvatarPath(
        groupChat: chat,
        nextPath: stagedPath,
        previousPath: previousPath,
        persistChatSummary: persistChatSummary,
      );
      notifyMessageUpdated(groupId);
    } catch (_) {
      await storage.deleteMediaFile(stagedPath);
      rethrow;
    }
  }

  Future<void> saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
    required Future<void> Function(Chat chat) persistChatSummary,
  }) async {
    final previous = groupChat.avatarPath;
    final stagedPath = await _stageGroupAvatarBytes(
      groupId: groupChat.peerId,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: updatedAtMs,
    );
    await _commitGroupAvatarPath(
      groupChat: groupChat,
      nextPath: stagedPath,
      previousPath: previous,
      persistChatSummary: persistChatSummary,
    );
  }

  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberPeerIds,
    required Map<String, Chat> chats,
    bool sendInvites = true,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final trimmedName = name.trim();
    final invitees = memberPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (trimmedName.isEmpty) {
      throw ArgumentError('Group name is required');
    }
    if (invitees.isEmpty) {
      throw ArgumentError('At least one member is required');
    }

    invitees.sort();
    final createFingerprint = '$trimmedName|${invitees.join('|')}';
    final activeCreate = _groupCreateInFlight[createFingerprint];
    if (activeCreate != null) {
      developer.log(
        'group create join in-flight fingerprint=$createFingerprint',
        name: 'chat',
      );
      return activeCreate;
    }

    final createFuture = _createGroupChatInternal(
      trimmedName: trimmedName,
      invitees: invitees,
      chats: chats,
      sendInvites: sendInvites,
      persistChatSummary: persistChatSummary,
      notifyMessageUpdated: notifyMessageUpdated,
    );
    _groupCreateInFlight[createFingerprint] = createFuture;
    try {
      return await createFuture;
    } finally {
      _groupCreateInFlight.remove(createFingerprint);
    }
  }

  Future<void> addGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
    required Map<String, Chat> chats,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw ArgumentError('Group chat not found');
    }
    final additions = participantPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where((item) => !chat.memberPeerIds.contains(item))
        .toSet()
        .toList(growable: false);
    if (additions.isEmpty) {
      return;
    }
    chat.memberPeerIds = _canonicalizePeerIds(<String>[
      ...chat.memberPeerIds,
      ...additions,
    ]);
    await persistChatSummary(chat);
    await groupFlowService.syncGroupMembershipWithRelay(chat);
    await groupFlowService.rotateGroupKey(chat, recipients: chat.memberPeerIds);
    await groupFlowService.sendGroupInvites(chat, recipients: additions);
    await groupFlowService.broadcastGroupMembersUpdate(
      groupChat: chat,
      recipients: <String>{...chat.memberPeerIds}.toList(growable: false),
      action: 'add',
      changedPeerIds: additions,
    );
    notifyMessageUpdated(groupId);
  }

  Future<void> removeGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
    required Map<String, Chat> chats,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw ArgumentError('Group chat not found');
    }
    final removals = participantPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where((item) => item != facade.peerId)
        .where((item) => item != chat.ownerPeerId)
        .where((item) => chat.memberPeerIds.contains(item))
        .toSet()
        .toList(growable: false);
    if (removals.isEmpty) {
      return;
    }

    final previousMembers = chat.memberPeerIds.toList(growable: false);
    chat.memberPeerIds = _canonicalizePeerIds(
      chat.memberPeerIds.where((peerId) => !removals.contains(peerId)).toList(),
    );
    await persistChatSummary(chat);
    await groupFlowService.syncGroupMembershipWithRelay(chat);
    await groupFlowService.rotateGroupKey(chat, recipients: chat.memberPeerIds);
    await groupFlowService.broadcastGroupMembersUpdate(
      groupChat: chat,
      recipients: <String>{...previousMembers}.toList(growable: false),
      action: 'remove',
      changedPeerIds: removals,
    );
    notifyMessageUpdated(groupId);
  }

  Future<void> renameGroupChat({
    required String groupId,
    required String newName,
    required Map<String, Chat> chats,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw ArgumentError('Group chat not found');
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Group name is required');
    }
    if (!chat.memberPeerIds.contains(facade.peerId)) {
      throw StateError('Only group members can rename group chat');
    }
    chat.name = trimmed;
    await persistChatSummary(chat);
    await groupFlowService.broadcastGroupMembersUpdate(
      groupChat: chat,
      recipients: <String>{...chat.memberPeerIds}.toList(growable: false),
      action: 'rename',
      changedPeerIds: const <String>[],
    );
    notifyMessageUpdated(groupId);
  }

  String _avatarExtensionForMime(String mimeType) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('png')) {
      return 'png';
    }
    if (normalized.contains('webp')) {
      return 'webp';
    }
    return 'jpg';
  }

  Future<void> _broadcastGroupAvatarUpdate({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List plainBytes,
    })
    encryptGroupBytes,
  }) async {
    final recipients = groupFlowService.collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      return;
    }

    final messageId = 'avatar:$updatedAtMs';
    await groupFlowService.ensureGroupKey(groupChat);
    final encryptedBytes = await encryptGroupBytes(
      groupId: groupChat.peerId,
      plainBytes: bytes,
    );
    final payloadBytes = encryptedBytes ?? bytes;
    final blobId = await facade.uploadBlob(
      scopeKind: RelayBlobScopeKind.group,
      targetId: groupChat.peerId,
      fileName: 'group_avatar.${_avatarExtensionForMime(mimeType)}',
      mimeType: mimeType,
      bytes: payloadBytes,
      blobId: 'blob:${groupChat.peerId}:$messageId',
    );
    await groupFlowService.broadcastGroupMembersUpdate(
      groupChat: groupChat,
      recipients: recipients,
      action: 'avatar',
      changedPeerIds: const <String>[],
      avatarBlobId: blobId,
      avatarMimeType: mimeType,
      avatarFileSizeBytes: bytes.length,
      avatarUpdatedAtMs: updatedAtMs,
    );
  }

  Future<Chat> _createGroupChatInternal({
    required String trimmedName,
    required List<String> invitees,
    required Map<String, Chat> chats,
    required bool sendInvites,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final groupId = 'group:${DateTime.now().microsecondsSinceEpoch}';
    final allMembers = _canonicalizePeerIds(<String>[
      ...invitees,
      facade.peerId,
    ]);
    final chat = Chat(
      peerId: groupId,
      name: trimmedName,
      isGroup: true,
      memberPeerIds: allMembers,
      ownerPeerId: facade.peerId,
      messagesLoaded: true,
      hasMoreMessages: false,
    );
    chats[groupId] = chat;
    await persistChatSummary(chat);
    await groupFlowService.ensureGroupKey(chat);
    await groupFlowService.syncGroupMembershipWithRelay(chat);
    if (sendInvites) {
      await groupFlowService.sendGroupInvites(chat, recipients: invitees);
      await groupFlowService.rotateGroupKey(chat, recipients: allMembers);
    }
    notifyMessageUpdated(groupId);
    return chat;
  }

  Future<String> _stageGroupAvatarBytes({
    required String groupId,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) async {
    final ext = _avatarExtensionForMime(mimeType);
    final path = await storage.saveMediaBytes(
      peerId: '_group_avatars',
      messageId: '${groupId}_$updatedAtMs',
      fileName: 'group_avatar.$ext',
      bytes: bytes,
    );
    if (path.isEmpty) {
      throw StateError('Failed to save avatar');
    }
    return path;
  }

  Future<void> _commitGroupAvatarPath({
    required Chat groupChat,
    required String nextPath,
    required String? previousPath,
    required Future<void> Function(Chat chat) persistChatSummary,
  }) async {
    groupChat.avatarPath = nextPath;
    await persistChatSummary(groupChat);
    if (previousPath != null &&
        previousPath.isNotEmpty &&
        previousPath != nextPath) {
      await storage.deleteMediaFile(previousPath);
    }
  }

  List<String> _canonicalizePeerIds(List<String> peerIds) {
    final normalized = peerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    normalized.sort();
    return normalized;
  }
}
