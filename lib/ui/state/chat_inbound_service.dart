import 'dart:typed_data';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/relay/relay_models.dart';
import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../../core/runtime/avatar_service.dart';
import 'chat_account_inbound_handler.dart';
import 'chat_controller_models.dart';
import 'chat_direct_blob_inbound_handler.dart';
import 'chat_group_control_inbound_handler.dart';
import 'chat_group_content_inbound_handler.dart';
import 'chat_inbound_classifier.dart';

class ChatInboundService {
  final NodeFacade facade;
  final SecureStorageBox settingsBox;
  final AvatarService avatarService;
  final ChatInboundClassifier inboundClassifier;
  late final ChatAccountInboundHandler _accountInboundHandler;
  final ChatGroupControlInboundHandler _groupControlInboundHandler =
      const ChatGroupControlInboundHandler();
  final ChatDirectBlobInboundHandler _directBlobInboundHandler =
      const ChatDirectBlobInboundHandler();
  final ChatGroupContentInboundHandler _groupContentInboundHandler =
      const ChatGroupContentInboundHandler();

  ChatInboundService({
    required this.facade,
    required this.settingsBox,
    required this.avatarService,
    required this.inboundClassifier,
  }) {
    _accountInboundHandler = ChatAccountInboundHandler(
      facade: facade,
      settingsBox: settingsBox,
    );
  }

  String _sourcePeerId(ChatMessage msg) =>
      _groupControlInboundHandler.sourcePeerId(msg);

  Future<void> handleIncomingMessage(
    ChatMessage msg, {
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupInvitePayload? payload,
    )
    handleIncomingGroupInvite,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupKeyPayload? payload,
    )
    handleIncomingGroupKey,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupDeletePayload? payload,
    )
    handleIncomingGroupDelete,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupChatDeletePayload? payload,
    )
    handleIncomingGroupChatDelete,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupMembersPayload? payload,
    )
    handleIncomingGroupMembersUpdate,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupMessagePayload? payload,
    )
    handleIncomingGroupMessage,
    required Future<void> Function(
      ChatMessage msg,
      IncomingGroupSecurePayload? payload,
    )
    handleIncomingGroupSecureMessage,
    required Future<void> Function(
      ChatMessage msg,
      IncomingBlobRefPayload blobRef,
    )
    handleIncomingDirectBlobRef,
    required Future<bool> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required Future<bool> Function(
      String peerId,
      String messageId,
      String authorPeerId,
    )
    removeMessageByAuthorWithMediaCleanup,
    required bool Function(String text) isGroupDeletePayload,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required int Function() unreadMessagesCount,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(ChatMessage msg) notifyNewMessage,
    required Future<void> Function({
      required String fromPeerId,
      required String message,
      required int badgeCount,
    })
    showMessageNotification,
  }) async {
    final dispatch = inboundClassifier.classifyIncomingMessage(msg);
    switch (dispatch) {
      case IncomingDeleteDispatch():
        if (msg.text.isNotEmpty) {
          if (isGroupDeletePayload(msg.text)) {
            await handleIncomingGroupDelete(msg, null);
            return;
          }
          final removed = await removeMessageByAuthorWithMediaCleanup(
            msg.peerId,
            msg.text,
            _sourcePeerId(msg),
          );
          if (!removed) {
            developer.log(
              '[chat] delete out-of-sync peer=${msg.peerId} messageId=${msg.text}',
              name: 'chat',
            );
          }
          notifyMessageUpdated(msg.peerId);
        }
        return;
      case IncomingProfileAvatarDispatch():
        await avatarService.handleIncomingAvatarAnnouncement(
          msg.peerId,
          msg.text,
        );
        return;
      case IncomingProfileAvatarRemoveDispatch():
        await avatarService.handleIncomingAvatarRemoval(msg.peerId, msg.text);
        return;
      case IncomingProfileAvatarQueryDispatch():
        await avatarService.handleIncomingAvatarQuery(msg.peerId, msg.text);
        return;
      case IncomingGroupInviteDispatch(payload: final payload):
        await handleIncomingGroupInvite(msg, payload);
        return;
      case IncomingGroupKeyDispatch(payload: final payload):
        await handleIncomingGroupKey(msg, payload);
        return;
      case IncomingGroupDeleteDispatch(payload: final payload):
        await handleIncomingGroupDelete(msg, payload);
        return;
      case IncomingGroupChatDeleteDispatch(payload: final payload):
        await handleIncomingGroupChatDelete(msg, payload);
        return;
      case IncomingGroupMembersDispatch(payload: final payload):
        await handleIncomingGroupMembersUpdate(msg, payload);
        return;
      case IncomingGroupMessageDispatch(payload: final payload):
        await handleIncomingGroupMessage(msg, payload);
        return;
      case IncomingGroupSecureDispatch(payload: final payload):
        await handleIncomingGroupSecureMessage(msg, payload);
        return;
      case IncomingDirectBlobRefDispatch(blobRef: final blobRef):
        await handleIncomingDirectBlobRef(msg, blobRef);
        return;
      case IncomingAccountPairRequestDispatch(payload: final payload):
        await _accountInboundHandler.handlePairRequest(msg, payload);
        return;
      case IncomingAccountPairApprovalDispatch(payload: final payload):
        await _accountInboundHandler.handlePairApproval(msg, payload);
        return;
      case IncomingAccountPairRejectionDispatch(payload: final payload):
        await _accountInboundHandler.handlePairRejection(msg, payload);
        return;
      case IncomingAccountMembershipUpdateDispatch(payload: final payload):
        await _accountInboundHandler.handleMembershipUpdate(msg, payload);
        return;
      case IncomingDisplayableDispatch():
        setStatus(msg.peerId, ChatConnectionStatus.connected);
        final message = Message(
          id: msg.id,
          peerId: msg.peerId,
          text: msg.text,
          senderPeerId: msg.peerId,
          incoming: true,
          timestamp: DateTime.now(),
          kind: msg.kind == 'file' ? MessageKind.file : MessageKind.text,
          fileName: msg.fileName,
          mimeType: msg.mimeType,
          fileDataBase64: msg.fileDataBase64,
          replyToMessageId: msg.replyToMessageId,
          replyToSenderPeerId: msg.replyToSenderPeerId,
          replyToSenderLabel: msg.replyToSenderLabel,
          replyToTextPreview: msg.replyToTextPreview,
          replyToKind: msg.replyToKind,
          status: MessageStatus.sent,
          isRead: false,
        );
        await appendMessage(msg.peerId, message);
        notifyMessageUpdated(msg.peerId);
        notifyNewMessage(msg);
        await showMessageNotification(
          fromPeerId: msg.peerId,
          message: msg.text,
          badgeCount: unreadMessagesCount(),
        ).catchError((error) {
          developer.log('notification error: $error', name: 'chat');
        });
        return;
      case IncomingIgnoredDispatch():
        developer.log(
          '[chat] ignored non-display message kind=${msg.kind} from=${msg.peerId} id=${msg.id}',
          name: 'chat',
        );
        return;
    }
  }

  Future<void> handleIncomingGroupInvite(
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
    await _groupControlInboundHandler.handleInvite(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      isGroupDeleted: isGroupDeleted,
      restoreDeletedGroup: restoreDeletedGroup,
      chats: chats,
      appendMessage: appendMessage,
      notifyMessageUpdated: notifyMessageUpdated,
      localPeerId: localPeerId,
    );
  }

  Future<void> handleIncomingGroupKey(
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
    await _groupControlInboundHandler.handleKey(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      isGroupDeleted: isGroupDeleted,
      applyIncomingGroupKey: applyIncomingGroupKey,
    );
  }

  Future<void> handleIncomingGroupDelete(
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
    await _groupControlInboundHandler.handleDelete(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      removeMessageByAuthorWithMediaCleanup:
          removeMessageByAuthorWithMediaCleanup,
      notifyMessageUpdated: notifyMessageUpdated,
    );
  }

  Future<void> handleIncomingGroupChatDelete(
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
    await _groupControlInboundHandler.handleChatDelete(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      knownGroupOwnerPeerId: knownGroupOwnerPeerId,
      deleteChatLocal: deleteChatLocal,
    );
  }

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
    await _groupContentInboundHandler.handleIncomingGroupSecureMessage(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      isGroupDeleted: isGroupDeleted,
      shouldRestoreDeletedGroup: shouldRestoreDeletedGroup,
      restoreDeletedGroup: restoreDeletedGroup,
      decryptGroupText: decryptGroupText,
      handleGroupSecureDecryptFailed: handleGroupSecureDecryptFailed,
      chats: chats,
      localPeerId: localPeerId,
      decodeIncomingBlobRefPayload: decodeIncomingBlobRefPayload,
      handleIncomingGroupBlobRef: handleIncomingGroupBlobRef,
      persistChatSummary: persistChatSummary,
      appendMessage: appendMessage,
      notifyMessageUpdated: notifyMessageUpdated,
      notifyNewMessage: notifyNewMessage,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification: showMessageNotification,
    );
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
    await _groupContentInboundHandler.handleIncomingGroupMessage(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      isGroupDeleted: isGroupDeleted,
      restoreDeletedGroup: restoreDeletedGroup,
      chats: chats,
      localPeerId: localPeerId,
      decodeIncomingBlobRefPayload: decodeIncomingBlobRefPayload,
      handleIncomingGroupBlobRef: handleIncomingGroupBlobRef,
      persistChatSummary: persistChatSummary,
      appendMessage: appendMessage,
      notifyMessageUpdated: notifyMessageUpdated,
      notifyNewMessage: notifyNewMessage,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification: showMessageNotification,
    );
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
    await _groupContentInboundHandler.handleIncomingGroupMembersUpdate(
      msg,
      payload: payload,
      normalizePayload: normalizePayload,
      isGroupDeleted: isGroupDeleted,
      restoreDeletedGroup: restoreDeletedGroup,
      chats: chats,
      localPeerId: localPeerId,
      persistChatSummary: persistChatSummary,
      saveGroupAvatarBytes: saveGroupAvatarBytes,
      downloadBlob: downloadBlob,
      decryptGroupBytes: decryptGroupBytes,
      handleIncomingGroupLeave: handleIncomingGroupLeave,
      notifyMessageUpdated: notifyMessageUpdated,
    );
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
    await _groupContentInboundHandler.handleIncomingGroupLeave(
      msg,
      payload: payload,
      chats: chats,
      localPeerId: localPeerId,
      persistChatSummary: persistChatSummary,
      syncGroupMembershipWithRelay: syncGroupMembershipWithRelay,
      rotateGroupKey: rotateGroupKey,
      broadcastGroupMembersUpdate: broadcastGroupMembersUpdate,
      notifyMessageUpdated: notifyMessageUpdated,
    );
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
    await _groupContentInboundHandler.handleIncomingGroupBlobRef(
      msg,
      groupId: groupId,
      groupChat: groupChat,
      existingGroupChat: existingGroupChat,
      blobRef: blobRef,
      notificationSenderLabel: notificationSenderLabel,
      localPeerId: localPeerId,
      restoreGroupBlobText: restoreGroupBlobText,
      downloadBlob: downloadBlob,
      decodeGroupBlobBytes: decodeGroupBlobBytes,
      saveGroupAvatarBytes: saveGroupAvatarBytes,
      persistChatSummary: persistChatSummary,
      groupBlobTransferId: groupBlobTransferId,
      appendMessage: appendMessage,
      notifyMessageUpdated: notifyMessageUpdated,
      restoreMediaInBackground: restoreMediaInBackground,
      notifyNewMessage: notifyNewMessage,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification: showMessageNotification,
    );
  }

  Future<void> handleIncomingDirectBlobRef(
    ChatMessage msg,
    IncomingBlobRefPayload blobRef, {
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat Function(String peerId, {String? fallbackName}) ensureChat,
    required Future<void> Function(String peerId) persistLoadedChat,
    required String Function({
      required String peerId,
      required String messageId,
      required String blobId,
    })
    directBlobTransferId,
    required void Function(String peerId) notifyMessageUpdated,
    required bool Function(Message message) shouldAutoRestoreIncomingMedia,
    required String incomingRelayFetchStatus,
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
    await _directBlobInboundHandler.handleIncomingDirectBlobRef(
      msg,
      blobRef,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: ensureChat,
      persistLoadedChat: persistLoadedChat,
      directBlobTransferId: directBlobTransferId,
      notifyMessageUpdated: notifyMessageUpdated,
      shouldAutoRestoreIncomingMedia: shouldAutoRestoreIncomingMedia,
      incomingRelayFetchStatus: incomingRelayFetchStatus,
      restoreMediaInBackground: restoreMediaInBackground,
      notifyNewMessage: notifyNewMessage,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification: showMessageNotification,
    );
  }
}
