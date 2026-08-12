import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../../core/runtime/app_file_logger.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';

class ChatGroupControlInboundHandler {
  const ChatGroupControlInboundHandler();

  String sourcePeerId(ChatMessage msg) {
    final senderPeerId = msg.senderPeerId?.trim();
    if (senderPeerId != null && senderPeerId.isNotEmpty) {
      return senderPeerId;
    }
    return msg.peerId.trim();
  }

  void logGroupFlow(String message) {
    developer.log(message, name: 'chat');
    AppFileLogger.log('[chat_group] $message');
  }

  Future<void> handleInvite(
    ChatMessage msg, {
    required IncomingGroupInvitePayload? payload,
    required IncomingGroupInvitePayload? Function(String text) normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Map<String, Chat> chats,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required void Function(String peerId) notifyMessageUpdated,
    required String localPeerId,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeer = sourcePeerId(msg);
    logGroupFlow(
      'invite start source=$sourcePeer target=${msg.peerId} id=${msg.id}',
    );
    if (resolvedPayload == null) {
      logGroupFlow(
        'group invite drop: invalid payload from=$sourcePeer id=${msg.id}',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupName = resolvedPayload.groupName;
    if (groupId.isEmpty || groupName.isEmpty) {
      logGroupFlow(
        'group invite drop: missing group fields from=$sourcePeer id=${msg.id}',
      );
      return;
    }
    final memberPeerIds = <String>{...resolvedPayload.memberPeerIds};
    memberPeerIds.add(sourcePeer);
    memberPeerIds.add(localPeerId);
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final resolvedOwner = (ownerPeerId != null && ownerPeerId.isNotEmpty)
        ? ownerPeerId
        : sourcePeer;
    if (isGroupDeleted(groupId)) {
      if (resolvedOwner != localPeerId) {
        logGroupFlow(
          'group invite drop: group is deleted group=$groupId from=$sourcePeer',
        );
        return;
      }
      await restoreDeletedGroup(groupId);
    }

    final chat =
        chats[groupId] ??
        Chat(
          peerId: groupId,
          name: groupName,
          isGroup: true,
          memberPeerIds: memberPeerIds.toList(growable: false),
          ownerPeerId: resolvedOwner,
          messagesLoaded: true,
          hasMoreMessages: false,
        );

    chat.name = groupName;
    chat.isGroup = true;
    chat.memberPeerIds = memberPeerIds.toList(growable: false);
    chat.ownerPeerId = resolvedOwner;
    chats[groupId] = chat;
    logGroupFlow(
      'group invite applied group=$groupId from=$sourcePeer members=${chat.memberPeerIds.length}',
    );

    final invitationMessage = Message(
      id: msg.id,
      peerId: groupId,
      text: 'Вас пригласили в чат "$groupName"',
      senderPeerId: sourcePeer,
      incoming: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      isRead: false,
    );
    await appendMessage(groupId, invitationMessage);
    notifyMessageUpdated(groupId);
  }

  Future<void> handleKey(
    ChatMessage msg, {
    required IncomingGroupKeyPayload? payload,
    required IncomingGroupKeyPayload? Function(String text) normalizePayload,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function({
      required String groupId,
      required String groupKeyBase64,
      required int keyVersion,
    })
    applyIncomingGroupKey,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    if (resolvedPayload == null) {
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupKey = resolvedPayload.groupKey;
    if (groupId.isEmpty || groupKey.isEmpty || isGroupDeleted(groupId)) {
      return;
    }
    await applyIncomingGroupKey(
      groupId: groupId,
      groupKeyBase64: groupKey,
      keyVersion: resolvedPayload.keyVersion,
    );
  }

  Future<void> handleDelete(
    ChatMessage msg, {
    required IncomingGroupDeletePayload? payload,
    required IncomingGroupDeletePayload? Function(String text) normalizePayload,
    required Future<bool> Function(
      String peerId,
      String messageId,
      String authorPeerId,
    )
    removeMessageByAuthorWithMediaCleanup,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    if (resolvedPayload == null) {
      developer.log(
        'group delete drop: invalid payload from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupMessageId = resolvedPayload.groupMessageId;
    if (groupId.isEmpty || groupMessageId.isEmpty) {
      developer.log(
        'group delete drop: missing fields from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final removed = await removeMessageByAuthorWithMediaCleanup(
      groupId,
      groupMessageId,
      sourcePeerId(msg),
    );
    if (!removed) {
      developer.log(
        '[chat] group delete out-of-sync group=$groupId messageId=$groupMessageId',
        name: 'chat',
      );
    }
    notifyMessageUpdated(groupId);
  }

  Future<void> handleChatDelete(
    ChatMessage msg, {
    required IncomingGroupChatDeletePayload? payload,
    required IncomingGroupChatDeletePayload? Function(String text)
    normalizePayload,
    required String? Function(String groupId) knownGroupOwnerPeerId,
    required Future<void> Function(
      String peerId, {
      bool rememberDeletedGroup,
      String? deletedByPeerId,
    })
    deleteChatLocal,
  }) async {
    final resolvedPayload = payload ?? normalizePayload(msg.text);
    final sourcePeer = sourcePeerId(msg);
    if (resolvedPayload == null) {
      developer.log(
        'group chat delete drop: invalid payload from=$sourcePeer id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    final groupId = resolvedPayload.groupId;
    if (groupId.isEmpty) {
      developer.log(
        'group chat delete drop: missing groupId from=$sourcePeer id=${msg.id}',
        name: 'chat',
      );
      return;
    }
    if (!_isTrustedGroupChatDeleteOwner(
      sourcePeer,
      resolvedPayload,
      knownGroupOwnerPeerId: knownGroupOwnerPeerId,
    )) {
      developer.log(
        'group chat delete drop: sender is not owner group=$groupId sender=$sourcePeer',
        name: 'chat',
      );
      return;
    }
    await deleteChatLocal(
      groupId,
      rememberDeletedGroup: true,
      deletedByPeerId: sourcePeer,
    );
    developer.log(
      'group chat delete applied group=$groupId from=$sourcePeer',
      name: 'chat',
    );
  }

  bool _isTrustedGroupChatDeleteOwner(
    String senderPeerId,
    IncomingGroupChatDeletePayload payload, {
    required String? Function(String groupId) knownGroupOwnerPeerId,
  }) {
    final sender = senderPeerId.trim();
    if (sender.isEmpty) {
      return false;
    }
    final declaredSender = payload.senderPeerId?.trim();
    if (declaredSender != null &&
        declaredSender.isNotEmpty &&
        declaredSender != sender) {
      return false;
    }
    final knownOwner = knownGroupOwnerPeerId(payload.groupId);
    if (knownOwner == null || knownOwner != sender) {
      return false;
    }
    final payloadOwner = payload.ownerPeerId?.trim();
    if (payloadOwner != null &&
        payloadOwner.isNotEmpty &&
        payloadOwner != knownOwner) {
      return false;
    }
    return true;
  }
}
