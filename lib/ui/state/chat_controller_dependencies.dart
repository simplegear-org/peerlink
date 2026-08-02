import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/relay/relay_media_transfer_service.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/avatar_service.dart';
import '../../core/runtime/contacts_repository.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/group_key_service.dart';
import '../../core/security/group_message_crypto_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_contacts_service.dart';
import 'chat_file_queue_service.dart';
import 'chat_group_flow_service.dart';
import 'chat_group_service.dart';
import 'chat_inbound_classifier.dart';
import 'chat_inbound_service.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_service.dart';
import 'chat_read_state_service.dart';
import 'chat_repository.dart';
import 'chat_summary_service.dart';

class ChatControllerDependencies {
  ChatControllerDependencies._({
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
    required this.repository,
    required this.inboundClassifier,
    required this.inboundService,
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
  final ChatRepository repository;
  final ChatInboundClassifier inboundClassifier;
  final ChatInboundService inboundService;

  factory ChatControllerDependencies.create({
    required NodeFacade facade,
    required StorageService storage,
    required AvatarService avatarService,
    required RelayMediaTransferService relayMediaTransfer,
    required String Function() nextLocalMessageId,
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
    final groupKeyService = GroupKeyService.forSecureStorageBox(
      storage.getGroupKeys(),
    );
    final outboundCodec = ChatOutboundCodec(
      localPeerIdProvider: () => facade.peerId,
    );
    final outboundService = ChatOutboundService(
      facade: facade,
      relayMediaTransfer: relayMediaTransfer,
      outboundCodec: outboundCodec,
    );
    final groupFlowService = ChatGroupFlowService(
      facade: facade,
      groupKeyService: groupKeyService,
      outboundCodec: outboundCodec,
      nextLocalMessageId: nextLocalMessageId,
    );
    final summaryService = ChatSummaryService(
      storage: storage,
      settingsBox: settingsBox,
      groupMetaBox: groupMetaBox,
    );
    final repository = ChatRepository(
      storage: storage,
      ensureChat: ensureChat,
      persistChatSummary: persistChatSummary,
      isInitialUnreadAnchor: isInitialUnreadAnchor,
    );
    final inboundClassifier = ChatInboundClassifier(
      decodeGroupInvitePayload: outboundCodec.decodeGroupInvitePayload,
      decodeGroupKeyPayload: outboundCodec.decodeGroupKeyPayload,
      decodeGroupDeletePayload: outboundCodec.decodeGroupDeletePayload,
      decodeGroupChatDeletePayload: outboundCodec.decodeGroupChatDeletePayload,
      decodeGroupMembersPayload: outboundCodec.decodeGroupMembersPayload,
      decodeGroupMessagePayload: outboundCodec.decodeGroupMessagePayload,
      decodeGroupSecurePayloadRaw: outboundCodec.decodeGroupSecurePayloadRaw,
      decodeDirectBlobRefPayload: outboundCodec.decodeDirectBlobRefPayload,
      decodeGroupBlobRefPayload: outboundCodec.decodeGroupBlobRefPayload,
      decodeAccountPairRequestPayload: decodeAccountPairRequest,
      decodeAccountPairApprovalPayload: decodeAccountPairApproval,
      decodeAccountPairRejectionPayload: decodeAccountPairRejection,
      decodeAccountMembershipUpdatePayload: decodeAccountMembershipUpdate,
    );
    return ChatControllerDependencies._(
      settingsBox: settingsBox,
      groupMetaBox: groupMetaBox,
      groupKeyService: groupKeyService,
      outboundCodec: outboundCodec,
      outboundService: outboundService,
      groupFlowService: groupFlowService,
      summaryService: summaryService,
      readStateService: const ChatReadStateService(),
      contactsService: ChatContactsService(
        repository: ContactsRepository(storage: storage),
      ),
      fileQueueService: ChatFileQueueService(),
      groupService: ChatGroupService(
        facade: facade,
        storage: storage,
        groupFlowService: groupFlowService,
      ),
      groupMessageCryptoService: GroupMessageCryptoService(
        groupKeyService: groupKeyService,
        securePayloadPrefix: ChatOutboundCodec.groupSecurePrefix,
      ),
      repository: repository,
      inboundClassifier: inboundClassifier,
      inboundService: ChatInboundService(
        facade: facade,
        settingsBox: settingsBox,
        avatarService: avatarService,
        inboundClassifier: inboundClassifier,
      ),
    );
  }
}

typedef AccountPairingRequestPayloadDecoder =
    AccountPairingRequestPayload? Function(ChatMessage message);
typedef AccountPairingApprovalPayloadDecoder =
    AccountPairingApprovalPayload? Function(ChatMessage message);
typedef AccountPairingRejectionPayloadDecoder =
    AccountPairingRejectedPayload? Function(ChatMessage message);
typedef AccountMembershipUpdatePayloadDecoder =
    AccountMembershipUpdatePayload? Function(ChatMessage message);
