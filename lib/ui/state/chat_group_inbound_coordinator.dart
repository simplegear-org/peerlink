import 'dart:typed_data';

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/notification/notification_service.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_group_flow_service.dart';
import 'chat_inbound_classifier.dart';
import 'chat_inbound_service.dart';
import 'chat_outbound_codec.dart';
import 'chat_summary_service.dart';

class ChatGroupInboundCoordinator {
  const ChatGroupInboundCoordinator({
    required NodeFacade facade,
    required ChatInboundService inboundService,
    required ChatInboundClassifier inboundClassifier,
    required ChatSummaryService chatSummaryService,
    required ChatGroupFlowService groupFlowService,
    required GroupKeyService groupKeyService,
    required ChatOutboundCodec outboundCodec,
    required Map<String, Chat> chats,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required Future<bool> Function(
      String peerId,
      String messageId,
      String authorPeerId,
    )
    removeMessageByAuthorWithMediaCleanup,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required int Function() unreadMessagesCount,
    required Future<String?> Function(String text) decryptGroupText,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decryptGroupBytes,
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
    required Future<void> Function(
      Chat chat, {
      required List<String> recipients,
    })
    rotateGroupKey,
    required Future<void> Function(Chat chat) syncGroupMembershipWithRelay,
    required Future<void> Function({
      required Chat groupChat,
      required List<String> recipients,
      required String action,
      required List<String> changedPeerIds,
      String? avatarBlobId,
      String? avatarMimeType,
      int? avatarFileSizeBytes,
      int? avatarUpdatedAtMs,
    })
    broadcastGroupMembersUpdate,
    required Future<void> Function(
      String peerId, {
      bool rememberDeletedGroup,
      String? deletedByPeerId,
    })
    deleteChatLocal,
    required Future<String?> Function({
      required String groupId,
      required String blobId,
      String? fallback,
    })
    restoreGroupBlobText,
    required void Function(Message message, {required bool isGroup, bool force})
    restoreMediaInBackground,
  }) : _facade = facade,
       _inboundService = inboundService,
       _inboundClassifier = inboundClassifier,
       _chatSummaryService = chatSummaryService,
       _groupFlowService = groupFlowService,
       _groupKeyService = groupKeyService,
       _outboundCodec = outboundCodec,
       _chats = chats,
       _isGroupDeleted = isGroupDeleted,
       _restoreDeletedGroup = restoreDeletedGroup,
       _persistChatSummary = persistChatSummary,
       _appendMessage = appendMessage,
       _removeMessageByAuthorWithMediaCleanup =
           removeMessageByAuthorWithMediaCleanup,
       _notifyMessageUpdated = notifyMessageUpdated,
       _notifyNewMessage = notifyNewMessage,
       _unreadMessagesCount = unreadMessagesCount,
       _decryptGroupText = decryptGroupText,
       _decryptGroupBytes = decryptGroupBytes,
       _decodeGroupBlobBytes = decodeGroupBlobBytes,
       _saveGroupAvatarBytes = saveGroupAvatarBytes,
       _rotateGroupKey = rotateGroupKey,
       _syncGroupMembershipWithRelay = syncGroupMembershipWithRelay,
       _broadcastGroupMembersUpdate = broadcastGroupMembersUpdate,
       _deleteChatLocal = deleteChatLocal,
       _restoreGroupBlobText = restoreGroupBlobText,
       _restoreMediaInBackground = restoreMediaInBackground;

  final NodeFacade _facade;
  final ChatInboundService _inboundService;
  final ChatInboundClassifier _inboundClassifier;
  final ChatSummaryService _chatSummaryService;
  final ChatGroupFlowService _groupFlowService;
  final GroupKeyService _groupKeyService;
  final ChatOutboundCodec _outboundCodec;
  final Map<String, Chat> _chats;
  final bool Function(String groupId) _isGroupDeleted;
  final Future<void> Function(String groupId) _restoreDeletedGroup;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final Future<void> Function(String peerId, Message message) _appendMessage;
  final Future<bool> Function(
    String peerId,
    String messageId,
    String authorPeerId,
  )
  _removeMessageByAuthorWithMediaCleanup;
  final void Function(String peerId) _notifyMessageUpdated;
  final void Function(ChatMessage msg) _notifyNewMessage;
  final int Function() _unreadMessagesCount;
  final Future<String?> Function(String text) _decryptGroupText;
  final Future<Uint8List?> Function({
    required String groupId,
    required Uint8List encryptedBytes,
  })
  _decryptGroupBytes;
  final Future<Uint8List> Function({
    required String groupId,
    required Uint8List encryptedBytes,
  })
  _decodeGroupBlobBytes;
  final Future<void> Function({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  })
  _saveGroupAvatarBytes;
  final Future<void> Function(Chat chat, {required List<String> recipients})
  _rotateGroupKey;
  final Future<void> Function(Chat chat) _syncGroupMembershipWithRelay;
  final Future<void> Function({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  })
  _broadcastGroupMembersUpdate;
  final Future<void> Function(
    String peerId, {
    bool rememberDeletedGroup,
    String? deletedByPeerId,
  })
  _deleteChatLocal;
  final Future<String?> Function({
    required String groupId,
    required String blobId,
    String? fallback,
  })
  _restoreGroupBlobText;
  final void Function(Message message, {required bool isGroup, bool force})
  _restoreMediaInBackground;

  Future<void> handleInvite(
    ChatMessage msg, {
    IncomingGroupInvitePayload? payload,
  }) {
    return _inboundService.handleIncomingGroupInvite(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupInvitePayload,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      chats: _chats,
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      localPeerId: _facade.peerId,
    );
  }

  Future<void> handleKey(ChatMessage msg, {IncomingGroupKeyPayload? payload}) {
    return _inboundService.handleIncomingGroupKey(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupKeyPayload,
      isGroupDeleted: _isGroupDeleted,
      applyIncomingGroupKey:
          ({required groupId, required groupKeyBase64, required keyVersion}) =>
              _groupKeyService.applyIncomingGroupKey(
                groupId: groupId,
                groupKeyBase64: groupKeyBase64,
                keyVersion: keyVersion,
              ),
    );
  }

  Future<void> handleDelete(
    ChatMessage msg, {
    IncomingGroupDeletePayload? payload,
  }) {
    return _inboundService.handleIncomingGroupDelete(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupDeletePayload,
      removeMessageByAuthorWithMediaCleanup:
          _removeMessageByAuthorWithMediaCleanup,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> handleChatDelete(
    ChatMessage msg, {
    IncomingGroupChatDeletePayload? payload,
  }) {
    return _inboundService.handleIncomingGroupChatDelete(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupChatDeletePayload,
      knownGroupOwnerPeerId: knownGroupOwnerPeerId,
      deleteChatLocal: _deleteChatLocal,
    );
  }

  Future<void> handleSecureMessage(
    ChatMessage msg, {
    IncomingGroupSecurePayload? payload,
  }) {
    return _inboundService.handleIncomingGroupSecureMessage(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupSecurePayload,
      isGroupDeleted: _isGroupDeleted,
      shouldRestoreDeletedGroup: (groupId) =>
          knownGroupOwnerPeerId(groupId) == _facade.peerId,
      restoreDeletedGroup: _restoreDeletedGroup,
      decryptGroupText: _decryptGroupText,
      handleGroupSecureDecryptFailed: handleSecureDecryptFailed,
      chats: _chats,
      localPeerId: _facade.peerId,
      decodeIncomingBlobRefPayload:
          _inboundClassifier.decodeIncomingBlobRefPayload,
      handleIncomingGroupBlobRef:
          (
            msg, {
            required groupId,
            required groupChat,
            required existingGroupChat,
            required blobRef,
            required notificationSenderLabel,
          }) => handleBlobRef(
            msg,
            groupId: groupId,
            groupChat: groupChat,
            existingGroupChat: existingGroupChat,
            blobRef: blobRef,
            notificationSenderLabel: notificationSenderLabel,
          ),
      persistChatSummary: _persistChatSummary,
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      notifyNewMessage: _notifyNewMessage,
      unreadMessagesCount: _unreadMessagesCount,
      showMessageNotification:
          NotificationService.instance.showMessageNotification,
    );
  }

  Future<void> handleMessage(
    ChatMessage msg, {
    IncomingGroupMessagePayload? payload,
  }) {
    return _inboundService.handleIncomingGroupMessage(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupMessagePayload,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      chats: _chats,
      localPeerId: _facade.peerId,
      decodeIncomingBlobRefPayload:
          _inboundClassifier.decodeIncomingBlobRefPayload,
      handleIncomingGroupBlobRef:
          (
            msg, {
            required groupId,
            required groupChat,
            required existingGroupChat,
            required blobRef,
            required notificationSenderLabel,
          }) => handleBlobRef(
            msg,
            groupId: groupId,
            groupChat: groupChat,
            existingGroupChat: existingGroupChat,
            blobRef: blobRef,
            notificationSenderLabel: notificationSenderLabel,
          ),
      persistChatSummary: _persistChatSummary,
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      notifyNewMessage: _notifyNewMessage,
      unreadMessagesCount: _unreadMessagesCount,
      showMessageNotification:
          NotificationService.instance.showMessageNotification,
    );
  }

  String? knownGroupOwnerPeerId(String groupId) {
    final chat = _chats[groupId];
    final chatOwner = chat?.ownerPeerId?.trim();
    if (chatOwner != null && chatOwner.isNotEmpty) {
      return chatOwner;
    }
    return _chatSummaryService.knownGroupOwnerPeerId(groupId);
  }

  Future<void> handleSecureDecryptFailed({
    required String groupId,
    required String sourcePeerId,
    required String messageId,
  }) async {
    if (knownGroupOwnerPeerId(groupId) != _facade.peerId) {
      return;
    }
    final groupChat =
        _chats[groupId] ?? _chatSummaryService.knownGroupChat(groupId);
    if (groupChat == null || !groupChat.isGroup) {
      return;
    }
    final members = <String>{
      ...groupChat.memberPeerIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
      _facade.peerId,
      sourcePeerId.trim(),
    }..removeWhere((item) => item.isEmpty);
    groupChat.memberPeerIds = members.toList(growable: false)..sort();
    groupChat.ownerPeerId = _facade.peerId;
    groupChat.isGroup = true;
    _chats[groupId] = groupChat;
    await _restoreDeletedGroup(groupId);
    await _persistChatSummary(groupChat);
    await _groupFlowService.sendGroupKeyToRecipients(
      groupChat,
      _groupFlowService.collectGroupRecipients(groupChat),
    );
    AppFileLogger.log(
      '[chat_group] resent group key after decrypt failed '
      'group=$groupId source=$sourcePeerId messageId=$messageId',
      name: 'chat',
    );
    _notifyMessageUpdated(groupId);
  }

  Future<void> handleMembersUpdate(
    ChatMessage msg, {
    IncomingGroupMembersPayload? payload,
  }) {
    return _inboundService.handleIncomingGroupMembersUpdate(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupMembersPayload,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      chats: _chats,
      localPeerId: _facade.peerId,
      persistChatSummary: _persistChatSummary,
      saveGroupAvatarBytes: _saveGroupAvatarBytes,
      downloadBlob: _facade.downloadBlob,
      decryptGroupBytes: _decryptGroupBytes,
      handleIncomingGroupLeave: (incomingMsg, {required payload}) =>
          handleLeave(incomingMsg, payload: payload),
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> handleLeave(
    ChatMessage msg, {
    required IncomingGroupMembersPayload payload,
  }) {
    return _inboundService.handleIncomingGroupLeave(
      msg,
      payload: payload,
      chats: _chats,
      localPeerId: _facade.peerId,
      persistChatSummary: _persistChatSummary,
      syncGroupMembershipWithRelay: _syncGroupMembershipWithRelay,
      rotateGroupKey: _rotateGroupKey,
      broadcastGroupMembersUpdate: _broadcastGroupMembersUpdate,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> handleBlobRef(
    ChatMessage msg, {
    required String groupId,
    required Chat groupChat,
    required Chat? existingGroupChat,
    required IncomingBlobRefPayload blobRef,
    required String notificationSenderLabel,
  }) {
    return _inboundService.handleIncomingGroupBlobRef(
      msg,
      groupId: groupId,
      groupChat: groupChat,
      existingGroupChat: existingGroupChat,
      blobRef: blobRef,
      notificationSenderLabel: notificationSenderLabel,
      localPeerId: _facade.peerId,
      restoreGroupBlobText: _restoreGroupBlobText,
      downloadBlob: _facade.downloadBlob,
      decodeGroupBlobBytes: _decodeGroupBlobBytes,
      saveGroupAvatarBytes: _saveGroupAvatarBytes,
      persistChatSummary: _persistChatSummary,
      groupBlobTransferId: _outboundCodec.groupBlobTransferId,
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      restoreMediaInBackground: _restoreMediaInBackground,
      notifyNewMessage: _notifyNewMessage,
      unreadMessagesCount: _unreadMessagesCount,
      showMessageNotification:
          NotificationService.instance.showMessageNotification,
    );
  }
}
