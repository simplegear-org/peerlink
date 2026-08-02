import 'dart:typed_data';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../../core/relay/relay_models.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_group_control_inbound_handler.dart';

class ChatGroupContentInboundHandler {
  const ChatGroupContentInboundHandler();

  String sourcePeerId(ChatMessage msg) =>
      const ChatGroupControlInboundHandler().sourcePeerId(msg);

  void logGroupFlow(String message) =>
      const ChatGroupControlInboundHandler().logGroupFlow(message);

  Future<void> handleIncomingGroupSecureMessage(
    ChatMessage msg, {
    required IncomingGroupSecurePayload? payload,
    required IncomingGroupSecurePayload? Function(String text) normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required bool Function(String groupId) shouldRestoreDeletedGroup,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Future<String?> Function(String text) decryptGroupText,
    required Future<void> Function({
      required String groupId,
      required String sourcePeerId,
      required String messageId,
    })
    handleGroupSecureDecryptFailed,
    required Map<String, Chat> chats,
    required String localPeerId,
    required IncomingBlobRefPayload? Function(String text)
    decodeIncomingBlobRefPayload,
    required Future<void> Function(
      ChatMessage msg, {
      required String groupId,
      required Chat groupChat,
      required Chat? existingGroupChat,
      required IncomingBlobRefPayload blobRef,
      required String notificationSenderLabel,
    })
    handleIncomingGroupBlobRef,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = this.sourcePeerId(msg);
    logGroupFlow(
      'secure start source=$sourcePeerId target=${msg.peerId} id=${msg.id}',
    );
    if (resolvedPayload == null) {
      logGroupFlow(
        'group secure drop: classifier returned null source=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    if (groupId.isEmpty) {
      logGroupFlow('group secure drop: empty groupId source=$sourcePeerId');
      return;
    }
    if (isGroupDeleted(groupId)) {
      if (!shouldRestoreDeletedGroup(groupId)) {
        logGroupFlow(
          'group secure message drop: group is deleted group=$groupId from=$sourcePeerId',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }
    final clearText = await decryptGroupText(msg.text);
    if (clearText == null || clearText.isEmpty) {
      logGroupFlow(
        'group secure message drop: decrypt failed group=$groupId from=$sourcePeerId',
      );
      await handleGroupSecureDecryptFailed(
        groupId: groupId,
        sourcePeerId: sourcePeerId,
        messageId: msg.id,
      );
      return;
    }
    logGroupFlow(
      'group secure decrypted group=$groupId source=$sourcePeerId textLen=${clearText.length}',
    );

    final existingChat = chats[groupId];
    final chat =
        existingChat ??
        Chat(
          peerId: groupId,
          name: groupId,
          isGroup: true,
          memberPeerIds: <String>[localPeerId, sourcePeerId],
          ownerPeerId: sourcePeerId,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    chats[groupId] = chat;

    if (existingChat != null) {
      if (!chat.memberPeerIds.contains(localPeerId)) {
        logGroupFlow(
          'group secure message drop: self is not a member group=$groupId',
        );
        return;
      }
      if (!chat.memberPeerIds.contains(sourcePeerId)) {
        logGroupFlow(
          'group secure message drop: sender is not a member group=$groupId sender=$sourcePeerId',
        );
        return;
      }
    }
    final groupName = chat.name;
    await persistChatSummary(chat);
    final blobRef = decodeIncomingBlobRefPayload(clearText);
    if (blobRef != null && blobRef.isGroup) {
      logGroupFlow(
        'group secure blob-ref group=$groupId source=$sourcePeerId blob=${blobRef.blobId}',
      );
      await handleIncomingGroupBlobRef(
        msg,
        groupId: groupId,
        groupChat: chat,
        existingGroupChat: existingChat,
        blobRef: blobRef,
        notificationSenderLabel: groupName,
      );
      return;
    }

    final incoming = Message(
      id: msg.id,
      peerId: groupId,
      text: clearText,
      senderPeerId: sourcePeerId,
      incoming: true,
      timestamp: DateTime.now(),
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, incoming);
    logGroupFlow(
      'group secure appended group=$groupId source=$sourcePeerId messageId=${incoming.id}',
    );
    notifyMessageUpdated(groupId);
    notifyNewMessage(ChatMessage(id: msg.id, peerId: groupId, text: clearText));
    await showMessageNotification(
      fromPeerId: groupName,
      message: clearText,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }

  Future<void> handleIncomingGroupMessage(
    ChatMessage msg, {
    required IncomingGroupMessagePayload? payload,
    required IncomingGroupMessagePayload? Function(String text)
    normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Map<String, Chat> chats,
    required String localPeerId,
    required IncomingBlobRefPayload? Function(String text)
    decodeIncomingBlobRefPayload,
    required Future<void> Function(
      ChatMessage msg, {
      required String groupId,
      required Chat groupChat,
      required Chat? existingGroupChat,
      required IncomingBlobRefPayload blobRef,
      required String notificationSenderLabel,
    })
    handleIncomingGroupBlobRef,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = this.sourcePeerId(msg);
    logGroupFlow(
      'message start source=$sourcePeerId target=${msg.peerId} id=${msg.id}',
    );
    if (resolvedPayload == null) {
      logGroupFlow(
        'group message drop: invalid payload from=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupMessageId = resolvedPayload.groupMessageId;
    final text = resolvedPayload.text;
    final groupName = resolvedPayload.groupName;
    if (groupId.isEmpty || groupMessageId.isEmpty || text.isEmpty) {
      logGroupFlow(
        'group message drop: missing fields from=$sourcePeerId id=${msg.id}',
      );
      return;
    }
    final members = <String>{...resolvedPayload.memberPeerIds};
    members.add(sourcePeerId);
    members.add(localPeerId);
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final resolvedOwner = (ownerPeerId != null && ownerPeerId.isNotEmpty)
        ? ownerPeerId
        : sourcePeerId;
    if (isGroupDeleted(groupId)) {
      if (resolvedOwner != localPeerId) {
        logGroupFlow(
          'group message drop: group is deleted group=$groupId from=$sourcePeerId',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }
    final existing = chats[groupId];
    final chat =
        existing ??
        Chat(
          peerId: groupId,
          name: groupName.isNotEmpty ? groupName : groupId,
          isGroup: true,
          memberPeerIds: members.toList(growable: false),
          ownerPeerId: resolvedOwner,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    if (groupName.isNotEmpty) {
      chat.name = groupName;
    }
    if (existing == null) {
      chat.memberPeerIds = members.toList(growable: false);
      chat.ownerPeerId = resolvedOwner;
    } else if ((chat.ownerPeerId == null || chat.ownerPeerId!.isEmpty) &&
        resolvedOwner.isNotEmpty) {
      chat.ownerPeerId = resolvedOwner;
    }
    chats[groupId] = chat;
    await persistChatSummary(chat);

    if (!chat.memberPeerIds.contains(localPeerId)) {
      logGroupFlow('group message drop: self is not a member group=$groupId');
      return;
    }
    if (!chat.memberPeerIds.contains(sourcePeerId)) {
      logGroupFlow(
        'group message drop: sender is not a member group=$groupId sender=$sourcePeerId',
      );
      return;
    }

    final blobRef = decodeIncomingBlobRefPayload(text);
    if (blobRef != null && blobRef.isGroup) {
      logGroupFlow(
        'group message blob-ref group=$groupId source=$sourcePeerId blob=${blobRef.blobId} content=${blobRef.contentKind}',
      );
      await handleIncomingGroupBlobRef(
        msg,
        groupId: groupId,
        groupChat: chat,
        existingGroupChat: existing,
        blobRef: blobRef,
        notificationSenderLabel: groupName.isNotEmpty ? groupName : chat.name,
      );
      return;
    }

    final incoming = Message(
      id: groupMessageId,
      peerId: groupId,
      text: text,
      senderPeerId: sourcePeerId,
      incoming: true,
      timestamp: DateTime.now(),
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, incoming);
    logGroupFlow(
      'group message appended group=$groupId source=$sourcePeerId messageId=${incoming.id}',
    );
    notifyMessageUpdated(groupId);
    notifyNewMessage(ChatMessage(id: msg.id, peerId: groupId, text: text));
    await showMessageNotification(
      fromPeerId: groupName.isNotEmpty ? groupName : groupId,
      message: text,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }

  Future<void> handleIncomingGroupMembersUpdate(
    ChatMessage msg, {
    required IncomingGroupMembersPayload? payload,
    required IncomingGroupMembersPayload? Function(String text)
    normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Map<String, Chat> chats,
    required String localPeerId,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function({
      required Chat groupChat,
      required Uint8List bytes,
      required String mimeType,
      required int updatedAtMs,
    })
    saveGroupAvatarBytes,
    required Future<RelayBlobDownload> Function(String blobId) downloadBlob,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decryptGroupBytes,
    required Future<void> Function(
      ChatMessage msg, {
      required IncomingGroupMembersPayload payload,
    })
    handleIncomingGroupLeave,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeerId = this.sourcePeerId(msg);
    if (resolvedPayload == null) {
      developer.log(
        'group members drop: invalid payload from=$sourcePeerId id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupName = resolvedPayload.groupName;
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final action = resolvedPayload.action;
    if (groupId.isEmpty) {
      return;
    }
    if (isGroupDeleted(groupId)) {
      if (ownerPeerId != localPeerId) {
        developer.log(
          'group members drop: group is deleted group=$groupId from=$sourcePeerId',
          name: 'chat',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }
    if (action == 'leave') {
      await handleIncomingGroupLeave(msg, payload: resolvedPayload);
      return;
    }

    final members = <String>{...resolvedPayload.memberPeerIds};
    if (sourcePeerId.isNotEmpty) {
      members.add(sourcePeerId);
    }
    final changedPeerIds = <String>{...resolvedPayload.changedPeerIds};
    final selfRemoved =
        action == 'remove' && changedPeerIds.contains(localPeerId);
    if (!selfRemoved) {
      members.add(localPeerId);
    }
    final chat =
        chats[groupId] ??
        Chat(
          peerId: groupId,
          name: groupName.isNotEmpty ? groupName : groupId,
          isGroup: true,
          memberPeerIds: members.toList(growable: false),
          ownerPeerId: ownerPeerId.isNotEmpty ? ownerPeerId : sourcePeerId,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    if (groupName.isNotEmpty) {
      chat.name = groupName;
    }
    chat.memberPeerIds = members.toList(growable: false);
    if (ownerPeerId.isNotEmpty) {
      chat.ownerPeerId = ownerPeerId;
    }
    chats[groupId] = chat;
    await persistChatSummary(chat);

    if (action == 'avatar') {
      final avatarBlobId = (resolvedPayload.avatarBlobId ?? '').trim();
      if (avatarBlobId.isNotEmpty) {
        final knownOwner = (chat.ownerPeerId ?? '').trim();
        if (knownOwner.isNotEmpty && sourcePeerId != knownOwner) {
          developer.log(
            'group avatar drop: sender is not owner group=$groupId sender=$sourcePeerId',
            name: 'chat',
          );
          notifyMessageUpdated(groupId);
          return;
        }
        try {
          final blob = await downloadBlob(avatarBlobId);
          if (blob.isNotFound) {
            notifyMessageUpdated(groupId);
            return;
          }
          final decrypted = await decryptGroupBytes(
            groupId: groupId,
            encryptedBytes: blob.payload,
          );
          final avatarBytes = decrypted ?? blob.payload;
          final avatarMime = resolvedPayload.avatarMimeType?.trim();
          final updatedAtMs =
              resolvedPayload.avatarUpdatedAtMs ??
              DateTime.now().millisecondsSinceEpoch;
          await saveGroupAvatarBytes(
            groupChat: chat,
            bytes: avatarBytes,
            mimeType: avatarMime?.isNotEmpty == true
                ? avatarMime!
                : 'image/png',
            updatedAtMs: updatedAtMs,
          );
        } catch (_) {}
      }
    }
    notifyMessageUpdated(groupId);
  }

  Future<void> handleIncomingGroupLeave(
    ChatMessage msg, {
    required IncomingGroupMembersPayload payload,
    required Map<String, Chat> chats,
    required String localPeerId,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(Chat chat) syncGroupMembershipWithRelay,
    required Future<void> Function(
      Chat chat, {
      required List<String> recipients,
    })
    rotateGroupKey,
    required Future<void> Function({
      required Chat groupChat,
      required List<String> recipients,
      required String action,
      required List<String> changedPeerIds,
    })
    broadcastGroupMembersUpdate,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final groupId = payload.groupId;
    final leavingPeerId = sourcePeerId(msg);
    if (groupId.isEmpty || leavingPeerId.isEmpty) {
      return;
    }
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      developer.log(
        'group leave drop: unknown group=$groupId from=$leavingPeerId',
        name: 'chat',
      );
      return;
    }
    final ownerPeerId = (chat.ownerPeerId ?? payload.ownerPeerId).trim();
    if (ownerPeerId.isNotEmpty && leavingPeerId == ownerPeerId) {
      developer.log(
        'group leave drop: owner cannot leave via leave action group=$groupId',
        name: 'chat',
      );
      return;
    }
    if (!chat.memberPeerIds.contains(leavingPeerId)) {
      developer.log(
        'group leave drop: sender is not member group=$groupId from=$leavingPeerId',
        name: 'chat',
      );
      return;
    }

    final previousMembers = chat.memberPeerIds.toList(growable: false);
    chat.memberPeerIds = previousMembers
        .where((peerId) => peerId != leavingPeerId)
        .toSet()
        .toList(growable: false);
    if (payload.groupName.isNotEmpty) {
      chat.name = payload.groupName;
    }
    if (ownerPeerId.isNotEmpty) {
      chat.ownerPeerId = ownerPeerId;
    }
    await persistChatSummary(chat);

    if (ownerPeerId == localPeerId) {
      await syncGroupMembershipWithRelay(chat);
      await rotateGroupKey(chat, recipients: chat.memberPeerIds);
      await broadcastGroupMembersUpdate(
        groupChat: chat,
        recipients: <String>{...previousMembers}.toList(growable: false),
        action: 'remove',
        changedPeerIds: <String>[leavingPeerId],
      );
    }
    notifyMessageUpdated(groupId);
  }

  Future<void> handleIncomingGroupBlobRef(
    ChatMessage msg, {
    required String groupId,
    required Chat groupChat,
    required Chat? existingGroupChat,
    required IncomingBlobRefPayload blobRef,
    required String notificationSenderLabel,
    required String localPeerId,
    required Future<String?> Function({
      required String groupId,
      required String blobId,
      String? fallback,
    })
    restoreGroupBlobText,
    required Future<RelayBlobDownload> Function(String blobId) downloadBlob,
    required Future<Uint8List> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decodeGroupBlobBytes,
    required Future<void> Function({
      required Chat groupChat,
      required Uint8List bytes,
      required String mimeType,
      required int updatedAtMs,
    })
    saveGroupAvatarBytes,
    required Future<void> Function(Chat chat) persistChatSummary,
    required String Function({
      required String groupId,
      required String messageId,
      required String blobId,
    })
    groupBlobTransferId,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(Message message, {required bool isGroup, bool force})
    restoreMediaInBackground,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    if (blobRef.chatPeerId != groupId || blobRef.blobId.isEmpty) {
      logGroupFlow(
        'group blob-ref drop group=$groupId source=${sourcePeerId(msg)} '
        'chatPeerId=${blobRef.chatPeerId} blob=${blobRef.blobId}',
      );
      return;
    }
    if (existingGroupChat == null && blobRef.memberPeerIds.isNotEmpty) {
      final members = <String>{
        ...blobRef.memberPeerIds,
        sourcePeerId(msg),
        localPeerId,
      };
      groupChat.memberPeerIds = members.toList(growable: false);
    }
    final groupName = blobRef.groupName?.trim();
    if (groupName != null && groupName.isNotEmpty) {
      groupChat.name = groupName;
    }
    final ownerPeerId = blobRef.ownerPeerId;
    if (ownerPeerId != null && ownerPeerId.isNotEmpty) {
      groupChat.ownerPeerId = ownerPeerId;
    }
    groupChat.isGroup = true;
    await persistChatSummary(groupChat);

    if (blobRef.contentKind == 'text') {
      logGroupFlow(
        'group blob-ref text start group=$groupId source=${sourcePeerId(msg)} blob=${blobRef.blobId}',
      );
      final text = await restoreGroupBlobText(
        groupId: groupId,
        blobId: blobRef.blobId,
        fallback: blobRef.textPreview,
      );
      if (text == null || text.isEmpty) {
        logGroupFlow(
          'group blob-ref text drop group=$groupId source=${sourcePeerId(msg)} blob=${blobRef.blobId}',
        );
        return;
      }
      final incoming = Message(
        id: blobRef.messageId,
        peerId: groupId,
        text: text,
        senderPeerId: sourcePeerId(msg),
        incoming: true,
        timestamp: DateTime.now(),
        replyToMessageId: msg.replyToMessageId,
        replyToSenderPeerId: msg.replyToSenderPeerId,
        replyToSenderLabel: msg.replyToSenderLabel,
        replyToTextPreview: msg.replyToTextPreview,
        replyToKind: msg.replyToKind,
        status: MessageStatus.sent,
        isRead: false,
      );
      await appendMessage(groupId, incoming);
      logGroupFlow(
        'group blob-ref text appended group=$groupId source=${sourcePeerId(msg)} messageId=${incoming.id}',
      );
      notifyMessageUpdated(groupId);
      notifyNewMessage(
        ChatMessage(id: blobRef.messageId, peerId: groupId, text: text),
      );
      await showMessageNotification(
        fromPeerId: notificationSenderLabel,
        message: text,
        badgeCount: unreadMessagesCount(),
      ).catchError((error) {
        developer.log('notification error: $error', name: 'chat');
      });
      return;
    }

    if (blobRef.contentKind == 'avatar') {
      logGroupFlow(
        'group blob-ref avatar start group=$groupId source=${sourcePeerId(msg)} blob=${blobRef.blobId}',
      );
      try {
        final blob = await downloadBlob(blobRef.blobId);
        if (blob.isNotFound) {
          return;
        }
        final avatarBytes = await decodeGroupBlobBytes(
          groupId: groupId,
          encryptedBytes: blob.payload,
        );
        final avatarMime = blobRef.mimeType;
        await saveGroupAvatarBytes(
          groupChat: groupChat,
          bytes: avatarBytes,
          mimeType: avatarMime?.isNotEmpty == true ? avatarMime! : 'image/png',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        notifyMessageUpdated(groupId);
      } catch (_) {}
      return;
    }

    if (blobRef.contentKind != 'media') {
      logGroupFlow(
        'group blob-ref drop unsupported content group=$groupId content=${blobRef.contentKind}',
      );
      return;
    }
    final fileName = (blobRef.fileName ?? '').trim();
    if (fileName.isEmpty) {
      return;
    }
    final incoming = Message(
      id: blobRef.messageId,
      peerId: groupId,
      text: fileName,
      senderPeerId: sourcePeerId(msg),
      incoming: true,
      timestamp: DateTime.now(),
      kind: MessageKind.file,
      fileName: fileName,
      mimeType: blobRef.mimeType,
      transferId: groupBlobTransferId(
        groupId: groupId,
        messageId: blobRef.messageId,
        blobId: blobRef.blobId,
      ),
      fileSizeBytes: blobRef.fileSizeBytes,
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, incoming);
    logGroupFlow(
      'group blob-ref media appended group=$groupId source=${sourcePeerId(msg)} messageId=${incoming.id}',
    );
    notifyMessageUpdated(groupId);
    restoreMediaInBackground(incoming, isGroup: true, force: false);
    notifyNewMessage(
      ChatMessage(
        id: blobRef.messageId,
        peerId: groupId,
        text: fileName,
        kind: 'file',
        fileName: fileName,
        mimeType: blobRef.mimeType,
      ),
    );
    await showMessageNotification(
      fromPeerId: notificationSenderLabel,
      message: fileName,
      badgeCount: unreadMessagesCount(),
    ).catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }
}
