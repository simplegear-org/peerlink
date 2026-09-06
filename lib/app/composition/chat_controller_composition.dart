// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/app/composition/chat_contacts_repository_adapter.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/core/runtime/moderation_report_service.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/security/group_key_service.dart';
import 'package:peerlink/core/security/group_message_crypto_service.dart';
import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_controller_dependencies.dart';
import 'package:peerlink/features/chat/application/chat_controller_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_direct_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_direct_media_crypto_service.dart';
import 'package:peerlink/features/chat/application/chat_file_progress_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_file_queue_service.dart';
import 'package:peerlink/features/chat/application/chat_file_transfer_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_crypto_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_flow_service.dart';
import 'package:peerlink/features/chat/application/chat_group_inbound_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_outbound_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_service.dart';
import 'package:peerlink/features/chat/application/chat_history_load_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_incoming_media_restore_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_inbound_classifier.dart';
import 'package:peerlink/features/chat/application/chat_inbound_service.dart';
import 'package:peerlink/features/chat/application/chat_inbound_subscription_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_media_restore_service.dart';
import 'package:peerlink/features/chat/application/chat_media_thumbnail_service.dart';
import 'package:peerlink/features/chat/application/chat_message_mutation_service.dart';
import 'package:peerlink/features/chat/application/chat_message_send_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_outbound_service.dart';
import 'package:peerlink/features/chat/application/chat_outgoing_relay_media_resume_service.dart';
import 'package:peerlink/features/chat/application/chat_read_state_service.dart';
import 'package:peerlink/features/chat/application/chat_receipt_service.dart';
import 'package:peerlink/features/chat/application/chat_reply_metadata_resolver.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/application/chat_summary_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/profile/application/avatar_service.dart';

class ChatControllerComposition {
  const ChatControllerComposition._();

  static ChatControllerDependencies create({
    required ChatRuntimeApi runtime,
    required StorageService storage,
    required AvatarService avatarService,
    required RelayMediaTransferService relayMediaTransfer,
    required Map<String, Chat> chats,
    required String Function() nextLocalMessageId,
    required String Function(String peerId, {String? fallback}) contactNameFor,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function() syncBadgeCount,
    required void Function(String message) logQueue,
    required void Function() resumeRecoverableFileQueue,
    required Future<void> Function({required String reason})
    resumePendingOutgoingRelayMedia,
    required Future<void> Function({required String reason})
    resumeInterruptedIncomingMediaQueue,
    required void Function(String peerId) schedulePersistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
    required bool Function() isMessageUpdatesClosed,
    required Future<Message?> Function(String peerId, String messageId)
    findMessage,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    updateFileProgress,
    required void Function(String peerId, String messageId) clearProgressUpdate,
    required Future<String?> Function(Message message) ensureThumbnail,
    required String Function(String peerId, String messageId) mediaKeyFor,
    required Future<Uint8List> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decodeGroupBlobBytes,
    required Future<Uint8List> Function({
      required String peerId,
      required Uint8List encryptedBytes,
    })
    decodeDirectBlobBytes,
    required Future<void> Function(OutgoingRelayMediaState state)
    rememberOutgoingRelayMediaState,
    required Future<void> Function(String peerId, String messageId)
    forgetOutgoingRelayMediaState,
    required String Function(Object error, {required String fallback})
    transferStatusForError,
    required Future<void> Function(
      String peerId,
      String messageId,
      MessageStatus status,
    )
    updateMessageStatusById,
    required Future<void> Function(
      ChatMessage message, {
      IncomingGroupMembersPayload? payload,
    })
    handleIncomingGroupMembersUpdate,
    required Future<bool> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required void Function(String peerId) schedulePersistLoadedChat,
    required int Function() unreadMessagesCount,
    required void Function(int unreadCount)? onUnreadBadgeCountChanged,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Future<void> Function(String peerId) persistLoadedChat,
    required Future<void> Function(Message? message)
    deleteManagedMediaForMessage,
    required Future<bool> Function(String peerId, String messageId)
    removeMessage,
    required Future<void> Function(
      String groupId, {
      required String deletedByPeerId,
      Chat? chat,
    })
    rememberDeletedGroup,
    required Future<void> Function() runGroupKeyGc,
    required bool Function(String groupId) isGroupDeleted,
    required Future<void> Function(String groupId) restoreDeletedGroup,
    required Future<void> Function(String peerId, Message message)
    appendMessage,
    required Future<bool> Function(
      String peerId,
      String messageId,
      String authorPeerId,
    )
    removeMessageByAuthorWithMediaCleanup,
    required void Function(ChatMessage message) notifyNewMessage,
    required Future<String?> Function(String text) decryptGroupText,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decryptGroupBytes,
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
    required Future<void> Function() waitUntilReady,
    required bool Function(String text) isGroupDeletePayload,
    required Future<void> Function(
      ChatMessage message,
      IncomingBlobRefPayload blobRef,
    )
    handleIncomingDirectBlobRef,
    required Future<void> Function(IncomingMessageReceiptPayload payload)
    handleIncomingMessageReceipt,
    required Chat Function(String peerId, {String? fallbackName}) ensureChat,
    required Future<void> Function(Chat chat) persistChatSummary,
    required bool Function(Message message) isInitialUnreadAnchor,
    required AccountPairingRequestPayloadDecoder decodeAccountPairRequest,
    required AccountPairingApprovalPayloadDecoder decodeAccountPairApproval,
    required AccountPairingRejectionPayloadDecoder decodeAccountPairRejection,
    required AccountMembershipUpdatePayloadDecoder
    decodeAccountMembershipUpdate,
  }) {
    final settingsBox = storage.getSettings();
    final groupMetaBox = storage.getGroupMeta();
    final contactsRepository = ContactsRepository(storage: storage);
    final accessControl = PeerAccessControlService(
      settingsBox: settingsBox,
      contactsRepository: contactsRepository,
    );
    final groupKeyService = GroupKeyService.forSecureStorageBox(
      storage.getGroupKeys(),
    );
    final outboundCodec = ChatOutboundCodec(
      localPeerIdProvider: () => runtime.peerId,
    );
    const summaryStore = ChatDatabaseSummaryStore();
    final outboundService = ChatOutboundService(
      facade: runtime,
      relayMediaTransfer: relayMediaTransfer,
      outboundCodec: outboundCodec,
    );
    final groupFlowService = ChatGroupFlowService(
      facade: runtime,
      groupKeyService: groupKeyService,
      outboundCodec: outboundCodec,
      nextLocalMessageId: nextLocalMessageId,
    );
    final summaryService = ChatSummaryService(
      summaryStore: summaryStore,
      settingsBox: settingsBox,
      groupMetaBox: groupMetaBox,
    );
    final groupMessageCryptoService = GroupMessageCryptoService(
      groupKeyService: groupKeyService,
      securePayloadPrefix: ChatOutboundCodec.groupSecurePrefix,
    );
    final repository = ChatRepository(
      storage: storage,
      ensureChat: ensureChat,
      persistChatSummary: persistChatSummary,
      isInitialUnreadAnchor: isInitialUnreadAnchor,
      summaryStore: summaryStore,
    );
    final inboundClassifier = ChatInboundClassifier(
      decodeGroupInvitePayload: outboundCodec.decodeGroupInvitePayload,
      decodeGroupKeyPayload: outboundCodec.decodeGroupKeyPayload,
      decodeGroupDeletePayload: outboundCodec.decodeGroupDeletePayload,
      decodeGroupChatDeletePayload: outboundCodec.decodeGroupChatDeletePayload,
      decodeGroupMembersPayload: outboundCodec.decodeGroupMembersPayload,
      decodeGroupMessagePayload: outboundCodec.decodeGroupMessagePayload,
      decodeGroupSecurePayloadRaw: outboundCodec.decodeGroupSecurePayloadRaw,
      decodeGroupKeyRequestPayload: outboundCodec.decodeGroupKeyRequestPayload,
      decodeDirectBlobRefPayload: outboundCodec.decodeDirectBlobRefPayload,
      decodeGroupBlobRefPayload: outboundCodec.decodeGroupBlobRefPayload,
      decodeMessageReceiptPayload: outboundCodec.decodeMessageReceiptPayload,
      decodeAccountPairRequestPayload: decodeAccountPairRequest,
      decodeAccountPairApprovalPayload: decodeAccountPairApproval,
      decodeAccountPairRejectionPayload: decodeAccountPairRejection,
      decodeAccountMembershipUpdatePayload: decodeAccountMembershipUpdate,
    );
    final inboundService = ChatInboundService(
      facade: runtime,
      settingsBox: settingsBox,
      avatarService: avatarService,
      inboundClassifier: inboundClassifier,
      accessControl: accessControl,
    );
    final fileQueueService = ChatFileQueueService();
    final relayMediaRetry = RelayMediaRetryCoordinator(
      settingsBox: settingsBox,
    );
    final mediaRestoreService = ChatMediaRestoreService(
      relayMediaTransfer: relayMediaTransfer,
      relayMediaRetry: relayMediaRetry,
      findMessage: findMessage,
      replaceMessage: replaceMessage,
      updateFileProgress: updateFileProgress,
      saveMediaBytes:
          ({
            required peerId,
            required messageId,
            required fileName,
            required bytes,
          }) {
            return storage.saveMediaBytes(
              peerId: peerId,
              messageId: messageId,
              fileName: fileName,
              bytes: bytes,
            );
          },
      ensureThumbnail: ensureThumbnail,
      clearProgressUpdate: clearProgressUpdate,
      notifyMessageUpdated: notifyMessageUpdated,
      mediaKeyFor: mediaKeyFor,
      isMessageUpdatesClosed: isMessageUpdatesClosed,
    );
    final incomingMediaRestoreCoordinator = ChatIncomingMediaRestoreCoordinator(
      mediaRestoreService: mediaRestoreService,
      outboundCodec: outboundCodec,
      facade: runtime,
      decodeGroupBlobBytes: decodeGroupBlobBytes,
      decodeDirectBlobBytes: decodeDirectBlobBytes,
    );
    final fileProgressCoordinator = ChatFileProgressCoordinator(
      fileQueueService: fileQueueService,
      chats: chats,
      incomingMediaRestoreCoordinator: incomingMediaRestoreCoordinator,
      incomingRelayErrorStatus: RelayMediaTransferService.incomingErrorStatus,
      incomingRelayNotConfiguredStatus:
          RelayMediaTransferService.incomingRelayNotConfiguredStatus,
      incomingRelayUnavailableStatus:
          RelayMediaTransferService.incomingRelayUnavailableStatus,
      notifyMessageUpdated: notifyMessageUpdated,
    );
    final replyMetadataResolver = ChatReplyMetadataResolver(
      contactNameFor: contactNameFor,
    );
    final groupCryptoCoordinator = ChatGroupCryptoCoordinator(
      groupFlowService: groupFlowService,
      groupMessageCryptoService: groupMessageCryptoService,
    );
    final groupOutboundCoordinator = ChatGroupOutboundCoordinator(
      facade: runtime,
      outboundService: outboundService,
      groupFlowService: groupFlowService,
      outboundCodec: outboundCodec,
      storage: storage,
      persistChatSummary: persistChatSummary,
      ensureGroupKey: groupCryptoCoordinator.ensureGroupKey,
      encryptGroupBytes: groupCryptoCoordinator.encryptGroupBytes,
      encryptGroupText: groupCryptoCoordinator.encryptGroupText,
      collectGroupRecipients: groupCryptoCoordinator.collectGroupRecipients,
      replySenderLabel: replyMetadataResolver.senderLabel,
      replyTextPreview: replyMetadataResolver.textPreview,
      replyKind: replyMetadataResolver.kind,
      updateFileProgress: updateFileProgress,
      rememberOutgoingRelayMediaState: rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: forgetOutgoingRelayMediaState,
      replaceMessage: replaceMessage,
      clearProgressUpdate: clearProgressUpdate,
      transferStatusForError: transferStatusForError,
      ensureThumbnail: ensureThumbnail,
      setStatus: setStatus,
      notifyMessageUpdated: notifyMessageUpdated,
      updateMessageStatusById: updateMessageStatusById,
      handleIncomingGroupMembersUpdate: handleIncomingGroupMembersUpdate,
    );
    final fileTransferCoordinator = ChatFileTransferCoordinator(
      fileQueueService: fileQueueService,
      outboundService: outboundService,
      storage: storage,
      localPeerId: runtime.peerId,
      chats: chats,
      logQueue: logQueue,
      removeMessageWithMediaCleanup: removeMessageWithMediaCleanup,
      forgetOutgoingRelayMediaState: forgetOutgoingRelayMediaState,
      schedulePersistLoadedChat: schedulePersistLoadedChat,
      notifyMessageUpdated: notifyMessageUpdated,
      updateFileProgress: updateFileProgress,
      replaceMessage: replaceMessage,
      clearProgressUpdate: clearProgressUpdate,
      setStatus: setStatus,
      rememberOutgoingRelayMediaState: rememberOutgoingRelayMediaState,
      replySenderLabel: replyMetadataResolver.senderLabel,
      replyTextPreview: replyMetadataResolver.textPreview,
      replyKind: replyMetadataResolver.kind,
      unreadMessagesCount: unreadMessagesCount,
      onUnreadBadgeCountChanged: onUnreadBadgeCountChanged,
      transferStatusForError: transferStatusForError,
      ensureThumbnail: ensureThumbnail,
      sendGroupFile: groupOutboundCoordinator.sendGroupFile,
    );
    final messageSendCoordinator = ChatMessageSendCoordinator(
      localPeerId: runtime.peerId,
      outboundService: outboundService,
      fileTransferCoordinator: fileTransferCoordinator,
      groupOutboundCoordinator: groupOutboundCoordinator,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: (peerId) => ensureChat(peerId),
      nextLocalMessageId: nextLocalMessageId,
      persistLoadedChat: persistLoadedChat,
      replySenderLabel: replyMetadataResolver.senderLabel,
      replyTextPreview: replyMetadataResolver.textPreview,
      replyKind: replyMetadataResolver.kind,
      replaceMessage: replaceMessage,
      setStatus: setStatus,
      syncBadgeCount: syncBadgeCount,
      notifyMessageUpdated: notifyMessageUpdated,
    );
    final historyLoadCoordinator = ChatHistoryLoadCoordinator(
      storage: storage,
      facade: runtime,
      groupKeyService: groupKeyService,
      chatRepository: repository,
      chatSummaryStore: summaryStore,
      chatSummaryService: summaryService,
      fileTransferCoordinator: fileTransferCoordinator,
      chats: chats,
      contactNameFor: contactNameFor,
      persistChatSummary: persistChatSummary,
      deleteManagedMediaForMessage: deleteManagedMediaForMessage,
      syncBadgeCount: syncBadgeCount,
      notifyMessageUpdated: notifyMessageUpdated,
      resumeInterruptedIncomingMediaForChat:
          incomingMediaRestoreCoordinator.resumeInterruptedIncomingMediaForChat,
      resumePendingOutgoingRelayMedia: resumePendingOutgoingRelayMedia,
      ensureThumbnail: ensureThumbnail,
    );
    final cleanupCoordinator = ChatCleanupCoordinator(
      facade: runtime,
      storage: storage,
      groupKeyService: groupKeyService,
      chatRepository: repository,
      chatSummaryStore: summaryStore,
      chatSummaryService: summaryService,
      chatFileQueueService: fileQueueService,
      groupOutboundCoordinator: groupOutboundCoordinator,
      chats: chats,
      deleteManagedMediaForMessage: deleteManagedMediaForMessage,
      removeMessage: removeMessage,
      persistChatSummary: persistChatSummary,
      rememberDeletedGroup: rememberDeletedGroup,
      runGroupKeyGc: runGroupKeyGc,
      syncBadgeCount: syncBadgeCount,
      notifyMessageUpdated: notifyMessageUpdated,
    );
    final groupInboundCoordinator = ChatGroupInboundCoordinator(
      facade: runtime,
      inboundService: inboundService,
      inboundClassifier: inboundClassifier,
      chatSummaryService: summaryService,
      groupFlowService: groupFlowService,
      groupKeyService: groupKeyService,
      outboundCodec: outboundCodec,
      chats: chats,
      isGroupDeleted: isGroupDeleted,
      restoreDeletedGroup: restoreDeletedGroup,
      persistChatSummary: persistChatSummary,
      appendMessage: appendMessage,
      removeMessageByAuthorWithMediaCleanup:
          removeMessageByAuthorWithMediaCleanup,
      notifyMessageUpdated: notifyMessageUpdated,
      notifyNewMessage: notifyNewMessage,
      unreadMessagesCount: unreadMessagesCount,
      decryptGroupText: decryptGroupText,
      decryptGroupBytes: decryptGroupBytes,
      decodeGroupBlobBytes: decodeGroupBlobBytes,
      saveGroupAvatarBytes: saveGroupAvatarBytes,
      rotateGroupKey: rotateGroupKey,
      syncGroupMembershipWithRelay: syncGroupMembershipWithRelay,
      broadcastGroupMembersUpdate: broadcastGroupMembersUpdate,
      deleteChatLocal: deleteChatLocal,
      restoreGroupBlobText: restoreGroupBlobText,
      restoreMediaInBackground: restoreMediaInBackground,
    );
    final inboundSubscriptionCoordinator = ChatInboundSubscriptionCoordinator(
      facade: runtime,
      inboundService: inboundService,
      waitUntilReady: waitUntilReady,
      isGroupDeletePayload: isGroupDeletePayload,
      handleIncomingGroupInvite: groupInboundCoordinator.handleInvite,
      handleIncomingGroupKey: groupInboundCoordinator.handleKey,
      handleIncomingGroupKeyRequest: groupInboundCoordinator.handleKeyRequest,
      handleIncomingGroupDelete: groupInboundCoordinator.handleDelete,
      handleIncomingGroupChatDelete: groupInboundCoordinator.handleChatDelete,
      handleIncomingGroupMembersUpdate:
          groupInboundCoordinator.handleMembersUpdate,
      handleIncomingGroupMessage: groupInboundCoordinator.handleMessage,
      handleIncomingGroupSecureMessage:
          groupInboundCoordinator.handleSecureMessage,
      handleIncomingDirectBlobRef: handleIncomingDirectBlobRef,
      handleIncomingMessageReceipt: handleIncomingMessageReceipt,
      removeMessageWithMediaCleanup: removeMessageWithMediaCleanup,
      removeMessageByAuthorWithMediaCleanup:
          removeMessageByAuthorWithMediaCleanup,
      setStatus: setStatus,
      appendMessage: appendMessage,
      unreadMessagesCount: unreadMessagesCount,
      notifyMessageUpdated: notifyMessageUpdated,
      notifyNewMessage: notifyNewMessage,
    );
    return ChatControllerDependencies(
      settingsBox: settingsBox,
      groupMetaBox: groupMetaBox,
      groupKeyService: groupKeyService,
      outboundCodec: outboundCodec,
      outboundService: outboundService,
      groupFlowService: groupFlowService,
      summaryService: summaryService,
      readStateService: const ChatReadStateService(),
      contactsService: ChatContactsService(
        repository: ChatContactsRepositoryAdapter(contactsRepository),
      ),
      fileQueueService: fileQueueService,
      groupService: ChatGroupService(
        facade: runtime,
        storage: storage,
        groupFlowService: groupFlowService,
      ),
      groupMessageCryptoService: groupMessageCryptoService,
      directLifecycleService: ChatDirectLifecycleService(
        facade: runtime,
        chats: chats,
        contactNameFor: contactNameFor,
        persistChatSummary: persistChatSummary,
        schedulePersistChatSummary: schedulePersistChatSummary,
        notifyMessageUpdated: notifyMessageUpdated,
        setStatus: setStatus,
      ),
      lifecycleService: ChatControllerLifecycleService(
        facade: runtime,
        setPeerStatus: setStatus,
        syncBadgeCount: syncBadgeCount,
        logQueue: logQueue,
        resumeRecoverableFileQueue: resumeRecoverableFileQueue,
        resumePendingOutgoingRelayMedia: resumePendingOutgoingRelayMedia,
        resumeInterruptedIncomingMediaQueue:
            resumeInterruptedIncomingMediaQueue,
      ),
      groupCryptoCoordinator: groupCryptoCoordinator,
      groupOutboundCoordinator: groupOutboundCoordinator,
      receiptService: ChatReceiptService(
        facade: runtime,
        outboundCodec: outboundCodec,
      ),
      directMediaCryptoService: ChatDirectMediaCryptoService(
        encryptBytes: runtime.encryptDirectBytes,
        decryptBytes: runtime.decryptDirectBytes,
      ),
      relayMediaRetry: relayMediaRetry,
      outgoingRelayMediaResumeService: ChatOutgoingRelayMediaResumeService(
        facade: runtime,
        settingsBox: settingsBox,
        outboundCodec: outboundCodec,
      ),
      messageMutationService: ChatMessageMutationService(
        storage: storage,
        chatRepository: repository,
        chats: chats,
      ),
      replyMetadataResolver: replyMetadataResolver,
      mediaThumbnailService: const ChatMediaThumbnailService(),
      mediaRestoreService: mediaRestoreService,
      incomingMediaRestoreCoordinator: incomingMediaRestoreCoordinator,
      fileProgressCoordinator: fileProgressCoordinator,
      fileTransferCoordinator: fileTransferCoordinator,
      messageSendCoordinator: messageSendCoordinator,
      historyLoadCoordinator: historyLoadCoordinator,
      cleanupCoordinator: cleanupCoordinator,
      groupInboundCoordinator: groupInboundCoordinator,
      inboundSubscriptionCoordinator: inboundSubscriptionCoordinator,
      repository: repository,
      inboundClassifier: inboundClassifier,
      inboundService: inboundService,
      accessControl: accessControl,
      moderationReports: ModerationReportService(
        settingsBox: settingsBox,
        localPeerId: () => runtime.peerId,
        deliverReport: runtime.submitModerationReport,
      ),
    );
  }
}
