// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:typed_data';

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/core/runtime/account_membership_update_payload.dart';
import 'package:peerlink/core/runtime/account_pairing_payload.dart';
import 'package:peerlink/core/runtime/moderation_report_service.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/security/group_key_service.dart';
import 'package:peerlink/core/security/group_message_crypto_service.dart';
import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_direct_media_crypto_service.dart';
import 'package:peerlink/features/chat/application/chat_direct_lifecycle_service.dart';
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
import 'package:peerlink/features/chat/application/chat_message_mutation_service.dart';
import 'package:peerlink/features/chat/application/chat_message_send_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_media_thumbnail_service.dart';
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
import 'package:peerlink/features/profile/application/avatar_service.dart';

class ChatControllerDependencies {
  const ChatControllerDependencies({
    required this.settingsBox,
    required this.groupMetaBox,
    required this.groupKeyService,
    required this.outboundCodec,
    required this.outboundService,
    required this.groupFlowService,
    required this.summaryService,
    required this.readStateService,
    required this.contactsService,
    required this.fileQueueService,
    required this.groupService,
    required this.groupMessageCryptoService,
    required this.directLifecycleService,
    required this.lifecycleService,
    required this.groupCryptoCoordinator,
    required this.groupOutboundCoordinator,
    required this.receiptService,
    required this.directMediaCryptoService,
    required this.relayMediaRetry,
    required this.outgoingRelayMediaResumeService,
    required this.messageMutationService,
    required this.replyMetadataResolver,
    required this.mediaThumbnailService,
    required this.mediaRestoreService,
    required this.incomingMediaRestoreCoordinator,
    required this.fileProgressCoordinator,
    required this.fileTransferCoordinator,
    required this.messageSendCoordinator,
    required this.historyLoadCoordinator,
    required this.cleanupCoordinator,
    required this.groupInboundCoordinator,
    required this.inboundSubscriptionCoordinator,
    required this.repository,
    required this.inboundClassifier,
    required this.inboundService,
    required this.accessControl,
    required this.moderationReports,
  });

  final SecureStorageBox settingsBox;
  final SecureStorageBox groupMetaBox;
  final GroupKeyService groupKeyService;
  final ChatOutboundCodec outboundCodec;
  final ChatOutboundService outboundService;
  final ChatGroupFlowService groupFlowService;
  final ChatSummaryService summaryService;
  final ChatReadStateService readStateService;
  final ChatContactsService contactsService;
  final ChatFileQueueService fileQueueService;
  final ChatGroupService groupService;
  final GroupMessageCryptoService groupMessageCryptoService;
  final ChatDirectLifecycleService directLifecycleService;
  final ChatControllerLifecycleService lifecycleService;
  final ChatGroupCryptoCoordinator groupCryptoCoordinator;
  final ChatGroupOutboundCoordinator groupOutboundCoordinator;
  final ChatReceiptService receiptService;
  final ChatDirectMediaCryptoService directMediaCryptoService;
  final RelayMediaRetryCoordinator relayMediaRetry;
  final ChatOutgoingRelayMediaResumeService outgoingRelayMediaResumeService;
  final ChatMessageMutationService messageMutationService;
  final ChatReplyMetadataResolver replyMetadataResolver;
  final ChatMediaThumbnailService mediaThumbnailService;
  final ChatMediaRestoreService mediaRestoreService;
  final ChatIncomingMediaRestoreCoordinator incomingMediaRestoreCoordinator;
  final ChatFileProgressCoordinator fileProgressCoordinator;
  final ChatFileTransferCoordinator fileTransferCoordinator;
  final ChatMessageSendCoordinator messageSendCoordinator;
  final ChatHistoryLoadCoordinator historyLoadCoordinator;
  final ChatCleanupCoordinator cleanupCoordinator;
  final ChatGroupInboundCoordinator groupInboundCoordinator;
  final ChatInboundSubscriptionCoordinator inboundSubscriptionCoordinator;
  final ChatRepository repository;
  final ChatInboundClassifier inboundClassifier;
  final ChatInboundService inboundService;
  final PeerAccessControlService accessControl;
  final ModerationReportService moderationReports;
}

typedef ChatControllerDependenciesFactory =
    ChatControllerDependencies Function({
      required ChatRuntimeApi runtime,
      required StorageService storage,
      required AvatarService avatarService,
      required RelayMediaTransferService relayMediaTransfer,
      required Map<String, Chat> chats,
      required String Function() nextLocalMessageId,
      required String Function(String peerId, {String? fallback})
      contactNameFor,
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
      required void Function(String peerId, String messageId)
      clearProgressUpdate,
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
      required void Function(
        Message message, {
        required bool isGroup,
        bool force,
      })
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
    });

typedef AccountPairingRequestPayloadDecoder =
    AccountPairingRequestPayload? Function(ChatMessage message);
typedef AccountPairingApprovalPayloadDecoder =
    AccountPairingApprovalPayload? Function(ChatMessage message);
typedef AccountPairingRejectionPayloadDecoder =
    AccountPairingRejectedPayload? Function(ChatMessage message);
typedef AccountMembershipUpdatePayloadDecoder =
    AccountMembershipUpdatePayload? Function(ChatMessage message);
