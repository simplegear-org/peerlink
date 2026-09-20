// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/app/composition/chat_contacts_repository_adapter.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/features/moderation/application/moderation_report_service.dart';
import 'package:peerlink/features/chat/application/chat_safety_service.dart';
import 'package:peerlink/features/moderation/application/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/security/group_key_service.dart';
import 'package:peerlink/core/security/group_message_crypto_service.dart';
import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_api.dart';
import 'package:peerlink/features/chat/application/chat_controller_dependencies.dart';
import 'package:peerlink/features/chat/application/chat_controller_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_ports.dart';
import 'package:peerlink/features/chat/application/chat_direct_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_direct_media_crypto_service.dart';
import 'package:peerlink/features/chat/application/chat_file_progress_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_file_queue_service.dart';
import 'package:peerlink/features/chat/application/chat_file_send_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_file_transfer_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_crypto_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_flow_service.dart';
import 'package:peerlink/features/chat/application/chat_group_inbound_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_outbound_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_group_service.dart';
import 'package:peerlink/features/chat/application/chat_groups_api.dart';
import 'package:peerlink/features/chat/application/chat_history_api.dart';
import 'package:peerlink/features/chat/application/chat_history_load_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_incoming_media_restore_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_inbound_classifier.dart';
import 'package:peerlink/features/chat/application/chat_inbound_service.dart';
import 'package:peerlink/features/chat/application/chat_inbound_subscription_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_media_restore_service.dart';
import 'package:peerlink/features/chat/application/chat_media_api.dart';
import 'package:peerlink/features/chat/application/chat_controller_media.dart';
import 'package:peerlink/features/chat/application/chat_media_thumbnail_service.dart';
import 'package:peerlink/features/chat/application/chat_messages_api.dart';
import 'package:peerlink/features/chat/application/chat_message_mutation_service.dart';
import 'package:peerlink/features/chat/application/chat_message_send_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_outbound_service.dart';
import 'package:peerlink/features/chat/application/chat_outgoing_relay_media_resume_service.dart';
import 'package:peerlink/features/chat/application/chat_read_state_service.dart';
import 'package:peerlink/features/chat/application/chat_receipt_service.dart';
import 'package:peerlink/features/chat/application/chat_reply_metadata_resolver.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/application/chat_safety_api.dart';
import 'package:peerlink/features/chat/application/chat_summary_service.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/profile/application/profile_inbound_handler.dart';
import 'package:peerlink/features/moderation/infrastructure/storage_moderation_report_outbox.dart';

class ChatControllerComposition {
  const ChatControllerComposition._();

  static ChatControllerDependencies create({
    required ChatRuntimeApi runtime,
    required StorageService storage,
    required ProfileInboundHandler avatarService,
    required ChatPresentationStatePort presentationState,
    required ChatConnectionStatePort connectionState,
    required ChatMessageStatePort messageState,
    required ChatMediaStatePort mediaState,
    required ChatGroupStatePort groupState,
    required ChatNotificationPort notifications,
    required ChatLifecyclePort lifecycle,
    required ChatInboundPort inbound,
    required ChatAccountPayloadPort accountPayloads,
  }) {
    const relayMediaTransfer = RelayMediaTransferService();
    final chats = presentationState.chats;
    final contactNameFor = presentationState.contactNameFor;
    final ensureChat = presentationState.ensureChat;
    final ensureChatLoaded = presentationState.ensureChatLoaded;
    final persistChatSummary = presentationState.persistChatSummary;
    final schedulePersistChatSummary =
        presentationState.schedulePersistChatSummary;
    final isInitialUnreadAnchor = presentationState.isInitialUnreadAnchor;
    final setStatus = connectionState.setStatus;
    final nextLocalMessageId = messageState.nextLocalMessageId;
    final findMessage = messageState.findMessage;
    final appendMessage = messageState.appendMessage;
    final replaceMessage = messageState.replaceMessage;
    final removeMessage = messageState.removeMessage;
    final removeMessageWithMediaCleanup =
        messageState.removeMessageWithMediaCleanup;
    final removeMessageByAuthorWithMediaCleanup =
        messageState.removeMessageByAuthorWithMediaCleanup;
    final deleteManagedMediaForMessage =
        messageState.deleteManagedMediaForMessage;
    final updateMessageStatusById = messageState.updateMessageStatusById;
    final updateFileProgress = mediaState.updateFileProgress;
    final clearProgressUpdate = mediaState.clearProgressUpdate;
    final ensureThumbnail = mediaState.ensureThumbnail;
    final mediaKeyFor = mediaState.mediaKeyFor;
    final decodeGroupBlobBytes = mediaState.decodeGroupBlobBytes;
    final rememberOutgoingRelayMediaState =
        mediaState.rememberOutgoingRelayMediaState;
    final forgetOutgoingRelayMediaState =
        mediaState.forgetOutgoingRelayMediaState;
    final transferStatusForError = mediaState.transferStatusForError;
    final restoreMediaInBackground = mediaState.restoreMediaInBackground;
    final restoreGroupBlobText = mediaState.restoreGroupBlobText;
    final handleIncomingGroupMembersUpdate =
        groupState.handleIncomingGroupMembersUpdate;
    final rememberDeletedGroup = groupState.rememberDeletedGroup;
    final runGroupKeyGc = groupState.runGroupKeyGc;
    final isGroupDeleted = groupState.isGroupDeleted;
    final restoreDeletedGroup = groupState.restoreDeletedGroup;
    final decryptGroupText = groupState.decryptGroupText;
    final decryptGroupBytes = groupState.decryptGroupBytes;
    final saveGroupAvatarBytes = groupState.saveGroupAvatarBytes;
    final rotateGroupKey = groupState.rotateGroupKey;
    final syncGroupMembershipWithRelay =
        groupState.syncGroupMembershipWithRelay;
    final broadcastGroupMembersUpdate = groupState.broadcastGroupMembersUpdate;
    final deleteChatLocal = groupState.deleteChatLocal;
    final isGroupDeletePayload = groupState.isGroupDeletePayload;
    final syncBadgeCount = notifications.syncBadgeCount;
    final notifyMessageUpdated = notifications.notifyMessageUpdated;
    final isMessageUpdatesClosed = notifications.isMessageUpdatesClosed;
    final unreadMessagesCount = notifications.unreadMessagesCount;
    final onUnreadBadgeCountChanged = notifications.onUnreadBadgeCountChanged;
    final notifyNewMessage = notifications.notifyNewMessage;
    final logQueue = lifecycle.logQueue;
    final resumeRecoverableFileQueue = lifecycle.resumeRecoverableFileQueue;
    final resumePendingOutgoingRelayMedia =
        lifecycle.resumePendingOutgoingRelayMedia;
    final resumeInterruptedIncomingMediaQueue =
        lifecycle.resumeInterruptedIncomingMediaQueue;
    final waitUntilReady = lifecycle.waitUntilReady;
    final handleIncomingDirectBlobRef = inbound.handleIncomingDirectBlobRef;
    final handleIncomingMessageReceipt = inbound.handleIncomingMessageReceipt;
    final decodeAccountPairRequest = accountPayloads.decodeAccountPairRequest;
    final decodeAccountPairApproval = accountPayloads.decodeAccountPairApproval;
    final decodeAccountPairRejection =
        accountPayloads.decodeAccountPairRejection;
    final decodeAccountMembershipUpdate =
        accountPayloads.decodeAccountMembershipUpdate;
    late final ChatHistoryApi historyApi;
    Future<void> persistLoadedChat(String peerId) =>
        historyApi.persistLoadedChat(peerId);
    void schedulePersistLoadedChat(String peerId) =>
        historyApi.schedulePersistLoadedChat(peerId);
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
    final mediaThumbnailService = const ChatMediaThumbnailService();
    final directMediaCryptoService = ChatDirectMediaCryptoService(
      encryptBytes: runtime.encryptDirectBytes,
      decryptBytes: runtime.decryptDirectBytes,
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
      decodeDirectBlobBytes: ({required peerId, required encryptedBytes}) =>
          directMediaCryptoService.decryptFromPeer(
            peerId: peerId,
            payload: encryptedBytes,
          ),
    );
    final fileProgressCoordinator = ChatFileProgressCoordinator(
      fileQueueService: fileQueueService,
      chats: chats,
      incomingMediaRestoreCoordinator: incomingMediaRestoreCoordinator,
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
    final fileSendCoordinator = ChatFileSendCoordinator(
      fileTransferCoordinator: fileTransferCoordinator,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: (peerId) => ensureChat(peerId),
      nextLocalMessageId: nextLocalMessageId,
      persistLoadedChat: persistLoadedChat,
      replySenderLabel: replyMetadataResolver.senderLabel,
      replyTextPreview: replyMetadataResolver.textPreview,
      replyKind: replyMetadataResolver.kind,
      logQueue: logQueue,
      notifyMessageUpdated: notifyMessageUpdated,
      refreshQueuedFileStatuses:
          fileTransferCoordinator.refreshQueuedFileStatuses,
      drainFileQueue: fileTransferCoordinator.drainFileQueue,
      saveMediaFile:
          ({
            required peerId,
            required messageId,
            required fileName,
            required sourcePath,
          }) => storage.saveMediaFile(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            sourcePath: sourcePath,
          ),
      saveMediaBytes:
          ({
            required peerId,
            required messageId,
            required fileName,
            required bytes,
          }) => storage.saveMediaBytes(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            bytes: bytes,
          ),
      ensureThumbnail: ensureThumbnail,
    );
    final mediaApi = ChatControllerMediaApi(
      fileSendCoordinator: fileSendCoordinator,
      fileTransferCoordinator: fileTransferCoordinator,
      fileProgressCoordinator: fileProgressCoordinator,
      incomingMediaRestoreCoordinator: incomingMediaRestoreCoordinator,
      outgoingRelayMediaResumeService: ChatOutgoingRelayMediaResumeService(
        facade: runtime,
        settingsBox: settingsBox,
        outboundCodec: outboundCodec,
      ),
      mediaThumbnailService: mediaThumbnailService,
      mediaRestoreService: mediaRestoreService,
      relayMediaRetry: relayMediaRetry,
      fileQueueService: fileQueueService,
      chats: chats,
      ensureChatLoaded: ensureChatLoaded,
      findChat: (peerId) => chats[peerId],
      replaceMessage: replaceMessage,
      setStatus: setStatus,
      notifyMessageUpdated: notifyMessageUpdated,
      logQueue: logQueue,
      restoreMediaFromEmbedded: ({required peerId, required message}) =>
          ChatControllerMedia.restoreMediaFromEmbedded(
            storage: storage,
            peerId: peerId,
            message: message,
            replaceMessage: replaceMessage,
            ensureThumbnail: ensureThumbnail,
          ),
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
      ensureChat: ensureChat,
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
    historyApi = ChatControllerHistoryApi(historyLoadCoordinator);
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
    final cleanupApi = ChatControllerCleanupApi(cleanupCoordinator);
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
    final groupService = ChatGroupService(
      facade: runtime,
      storage: storage,
      groupFlowService: groupFlowService,
    );
    final groupsApi = ChatControllerGroupsApi(
      groupService: groupService,
      groupCryptoCoordinator: groupCryptoCoordinator,
      groupOutboundCoordinator: groupOutboundCoordinator,
      groupInboundCoordinator: groupInboundCoordinator,
      summaryService: summaryService,
      historyApi: historyApi,
      cleanupCoordinator: cleanupCoordinator,
      chats: chats,
      persistChatSummary: persistChatSummary,
      notifyMessageUpdated: notifyMessageUpdated,
      groupDeletePrefix: '__peerlink_group_delete_v1__:',
    );
    final readStateService = const ChatReadStateService();
    final receiptService = ChatReceiptService(
      facade: runtime,
      outboundCodec: outboundCodec,
    );
    final messageMutationService = ChatMessageMutationService(
      storage: storage,
      chatRepository: repository,
      chats: chats,
    );
    final messagesApi = ChatControllerMessagesApi(
      messageSendCoordinator: messageSendCoordinator,
      messageMutationService: messageMutationService,
      readStateService: readStateService,
      receiptService: receiptService,
      chatRepository: repository,
      chats: chats,
      persistLoadedChat: persistLoadedChat,
      persistChatSummary: persistChatSummary,
      notifyMessageUpdated: notifyMessageUpdated,
      onUnreadBadgeCountChanged: onUnreadBadgeCountChanged,
    );
    final moderationReports = ModerationReportService(
      settingsBox: settingsBox,
      outbox: StorageModerationReportOutbox(settingsBox),
      localPeerId: () => runtime.peerId,
      deliverReport: runtime.submitModerationReport,
    );
    return ChatControllerDependencies(
      persistence: ChatPersistenceDependencies(
        summaryService: summaryService,
        historyApi: historyApi,
      ),
      messaging: ChatMessagingDependencies(
        outboundCodec: outboundCodec,
        messagesApi: messagesApi,
      ),
      groups: ChatGroupDependencies(
        contactsService: ChatContactsService(
          repository: ChatContactsRepositoryAdapter(contactsRepository),
        ),
        groupsApi: groupsApi,
      ),
      mediaLifecycle: ChatMediaLifecycleDependencies(
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
        mediaApi: mediaApi,
        cleanupApi: cleanupApi,
        inboundService: inboundService,
        inboundSubscriptionCoordinator: inboundSubscriptionCoordinator,
      ),
      safety: ChatSafetyDependencies(
        safetyApi: ChatControllerSafetyApi(
          accessControl: accessControl,
          moderationReports: moderationReports,
          safetyService: ChatSafetyService(
            accessControl: accessControl,
            reports: moderationReports,
            chats: () => chats.values,
            notifyMessageUpdated: notifyMessageUpdated,
            syncPushPolicy: (reason) =>
                runtime.syncPushDeviceState(reason: reason, forcePolicy: true),
            log: logQueue,
          ),
        ),
      ),
    );
  }
}
