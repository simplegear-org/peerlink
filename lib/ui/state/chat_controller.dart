import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/notification/notification_service.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/group_message_crypto_service.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../../core/runtime/avatar_service.dart';
import 'chat_account_payload_decoder.dart';
import 'chat_controller_models.dart';
import 'chat_controller_lifecycle_service.dart';
import 'chat_controller_media.dart';
import 'chat_controller_dependencies.dart';
import 'chat_controller_coordinator_factory.dart';
import 'chat_cleanup_coordinator.dart';
import 'chat_direct_lifecycle_service.dart';
import 'chat_file_progress_coordinator.dart';
import 'chat_file_send_coordinator.dart';
import 'chat_file_transfer_coordinator.dart';
import 'chat_group_crypto_coordinator.dart';
import 'chat_group_flow_service.dart';
import 'chat_group_inbound_coordinator.dart';
import 'chat_group_outbound_coordinator.dart';
import 'chat_history_load_coordinator.dart';
import 'chat_inbound_service.dart';
import 'chat_inbound_classifier.dart';
import 'chat_inbound_subscription_coordinator.dart';
import 'chat_incoming_media_restore_coordinator.dart';
import 'chat_media_restore_service.dart';
import 'chat_message_send_coordinator.dart';
import 'chat_message_mutation_service.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_service.dart';
import 'chat_outgoing_relay_media_resume_service.dart';
import '../../core/relay/relay_media_transfer_service.dart';
import 'chat_file_queue_service.dart';
import 'chat_contacts_service.dart';
import 'chat_group_service.dart';
import 'chat_read_state_service.dart';
import 'chat_repository.dart';
import 'chat_reply_metadata_resolver.dart';
import 'chat_summary_service.dart';

class ChatController with WidgetsBindingObserver {
  static int _lastGeneratedMessageId = 0;
  static const String _groupDeletePrefix = '__peerlink_group_delete_v1__:';
  static const String _incomingRelayFetchStatus =
      RelayMediaTransferService.incomingFetchStatus;
  static const String _incomingRelayNotConfiguredStatus =
      RelayMediaTransferService.incomingRelayNotConfiguredStatus;
  static const String _incomingRelayErrorStatus =
      RelayMediaTransferService.incomingErrorStatus;
  static const String _incomingRelayUnavailableStatus =
      RelayMediaTransferService.incomingRelayUnavailableStatus;
  final NodeFacade facade;
  final StorageService _storage;
  late final SecureStorageBox _settingsBox;
  late final GroupKeyService _groupKeyService;
  final RelayMediaTransferService _relayMediaTransfer =
      const RelayMediaTransferService();
  late final RelayMediaRetryCoordinator _relayMediaRetry;
  late final ChatGroupFlowService _groupFlowService;
  late final ChatMediaRestoreService _mediaRestoreService;
  late final ChatOutboundCodec _outboundCodec;
  late final ChatInboundClassifier _inboundClassifier;
  late final ChatRepository _chatRepository;
  late final ChatSummaryService _chatSummaryService;
  late final ChatFileQueueService _chatFileQueueService;
  late final ChatOutboundService _chatOutboundService;
  late final ChatControllerLifecycleService _lifecycleService;
  late final ChatOutgoingRelayMediaResumeService
  _outgoingRelayMediaResumeService;
  late final ChatInboundService _chatInboundService;
  late final ChatReadStateService _chatReadStateService;
  late final ChatContactsService _chatContactsService;
  late final ChatGroupService _chatGroupService;
  late final ChatDirectLifecycleService _directLifecycleService;
  late final ChatMessageMutationService _messageMutationService;
  late final ChatFileTransferCoordinator _fileTransferCoordinator;
  late final ChatFileProgressCoordinator _fileProgressCoordinator;
  late final ChatFileSendCoordinator _fileSendCoordinator;
  late final ChatIncomingMediaRestoreCoordinator
  _incomingMediaRestoreCoordinator;
  late final ChatGroupInboundCoordinator _groupInboundCoordinator;
  late final ChatInboundSubscriptionCoordinator _inboundSubscriptionCoordinator;
  late final ChatGroupCryptoCoordinator _groupCryptoCoordinator;
  late final ChatGroupOutboundCoordinator _groupOutboundCoordinator;
  late final ChatHistoryLoadCoordinator _historyLoadCoordinator;
  late final ChatCleanupCoordinator _cleanupCoordinator;
  late final ChatMessageSendCoordinator _messageSendCoordinator;
  late final GroupMessageCryptoService _groupMessageCryptoService;
  late final ChatReplyMetadataResolver _replyMetadataResolver;

  final Map<String, Chat> chats = {};
  final Map<String, ChatConnectionStatus> _connectionStatus = {};
  final Map<String, String?> _connectionErrors = {};
  final _connectionStatusController = StreamController<String>.broadcast();
  final _messageUpdatesController = StreamController<String>.broadcast();
  final _newMessageNotificationController =
      StreamController<ChatMessage>.broadcast();
  final void Function(int unreadCount)? _onUnreadBadgeCountChanged;

  ChatController(
    this.facade, {
    required StorageService storage,
    required AvatarService avatarService,
    void Function(int unreadCount)? onUnreadBadgeCountChanged,
  }) : _storage = storage,
       _onUnreadBadgeCountChanged = onUnreadBadgeCountChanged {
    final dependencies = ChatControllerDependencies.create(
      facade: facade,
      storage: storage,
      avatarService: avatarService,
      relayMediaTransfer: _relayMediaTransfer,
      nextLocalMessageId: _nextLocalMessageId,
      ensureChat: _ensureChat,
      persistChatSummary: _persistChatSummary,
      isInitialUnreadAnchor: isInitialUnreadAnchor,
      decodeAccountPairRequest: ChatAccountPayloadDecoder.decodePairRequest,
      decodeAccountPairApproval: ChatAccountPayloadDecoder.decodePairApproval,
      decodeAccountPairRejection: ChatAccountPayloadDecoder.decodePairRejection,
      decodeAccountMembershipUpdate:
          ChatAccountPayloadDecoder.decodeMembershipUpdate,
    );
    _settingsBox = dependencies.settingsBox;
    _groupKeyService = dependencies.groupKeyService;
    _outboundCodec = dependencies.outboundCodec;
    _chatOutboundService = dependencies.outboundService;
    _groupFlowService = dependencies.groupFlowService;
    _chatSummaryService = dependencies.summaryService;
    _chatReadStateService = dependencies.readStateService;
    _chatContactsService = dependencies.contactsService;
    _chatFileQueueService = dependencies.fileQueueService;
    _chatGroupService = dependencies.groupService;
    _directLifecycleService = ChatControllerCoordinatorFactory.directLifecycle(
      facade: facade,
      chats: chats,
      contactNameFor: _contactNameFor,
      persistChatSummary: _persistChatSummary,
      schedulePersistChatSummary: _schedulePersistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
      setStatus: _setStatus,
    );
    _groupMessageCryptoService = dependencies.groupMessageCryptoService;
    _chatRepository = dependencies.repository;
    _inboundClassifier = dependencies.inboundClassifier;
    _chatInboundService = dependencies.inboundService;
    _replyMetadataResolver = ChatReplyMetadataResolver(
      contactNameFor: _contactNameFor,
    );
    _relayMediaRetry = RelayMediaRetryCoordinator(settingsBox: _settingsBox);
    _outgoingRelayMediaResumeService = ChatOutgoingRelayMediaResumeService(
      facade: facade,
      settingsBox: _settingsBox,
      outboundCodec: _outboundCodec,
    );
    _lifecycleService = ChatControllerLifecycleService(
      facade: facade,
      setPeerStatus: _setStatus,
      syncBadgeCount: _syncBadgeCount,
      logQueue: _logQueue,
      resumeRecoverableFileQueue: _resumeRecoverableFileQueue,
      resumePendingOutgoingRelayMedia: _resumePendingOutgoingRelayMedia,
      resumeInterruptedIncomingMediaQueue: _resumeInterruptedIncomingMediaQueue,
    );
    _messageMutationService = ChatMessageMutationService(
      storage: _storage,
      chatRepository: _chatRepository,
      chats: chats,
    );
    _groupCryptoCoordinator = ChatGroupCryptoCoordinator(
      groupFlowService: _groupFlowService,
      groupMessageCryptoService: _groupMessageCryptoService,
    );
    _groupOutboundCoordinator = ChatGroupOutboundCoordinator(
      facade: facade,
      outboundService: _chatOutboundService,
      groupFlowService: _groupFlowService,
      outboundCodec: _outboundCodec,
      storage: _storage,
      persistChatSummary: _persistChatSummary,
      ensureGroupKey: _ensureGroupKey,
      encryptGroupBytes: _encryptGroupBytes,
      encryptGroupText: _encryptGroupText,
      collectGroupRecipients: _collectGroupRecipients,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      updateFileProgress: _updateFileProgress,
      rememberOutgoingRelayMediaState: _rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      transferStatusForError: _transferStatusForError,
      setStatus: _setStatus,
      notifyMessageUpdated: _notifyMessageUpdated,
      updateMessageStatusById: _updateMessageStatusById,
      handleIncomingGroupMembersUpdate: _handleIncomingGroupMembersUpdate,
    );
    _fileTransferCoordinator = ChatFileTransferCoordinator(
      fileQueueService: _chatFileQueueService,
      outboundService: _chatOutboundService,
      storage: _storage,
      localPeerId: facade.peerId,
      chats: chats,
      logQueue: _logQueue,
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      schedulePersistLoadedChat: _schedulePersistLoadedChat,
      notifyMessageUpdated: _notifyMessageUpdated,
      updateFileProgress: _updateFileProgress,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      setStatus: _setStatus,
      rememberOutgoingRelayMediaState: _rememberOutgoingRelayMediaState,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      unreadMessagesCount: unreadMessagesCount,
      onUnreadBadgeCountChanged: _onUnreadBadgeCountChanged,
      transferStatusForError: _transferStatusForError,
      sendGroupFile: _sendGroupFileAsync,
    );
    _messageSendCoordinator = ChatMessageSendCoordinator(
      localPeerId: facade.peerId,
      outboundService: _chatOutboundService,
      fileTransferCoordinator: _fileTransferCoordinator,
      groupOutboundCoordinator: _groupOutboundCoordinator,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: (peerId) => _ensureChat(peerId),
      nextLocalMessageId: _nextLocalMessageId,
      persistLoadedChat: _persistLoadedChat,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      replaceMessage: _replaceMessage,
      setStatus: _setStatus,
      syncBadgeCount: _syncBadgeCount,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
    _historyLoadCoordinator = ChatHistoryLoadCoordinator(
      storage: _storage,
      facade: facade,
      groupKeyService: _groupKeyService,
      chatRepository: _chatRepository,
      chatSummaryService: _chatSummaryService,
      fileTransferCoordinator: _fileTransferCoordinator,
      chats: chats,
      contactNameFor: _contactNameFor,
      persistChatSummary: _persistChatSummary,
      deleteManagedMediaForMessage: _deleteManagedMediaForMessage,
      syncBadgeCount: _syncBadgeCount,
      notifyMessageUpdated: _notifyMessageUpdated,
      resumeInterruptedIncomingMediaForChat:
          _resumeInterruptedIncomingMediaForChat,
      resumePendingOutgoingRelayMedia: _resumePendingOutgoingRelayMedia,
    );
    _cleanupCoordinator = ChatCleanupCoordinator(
      facade: facade,
      storage: _storage,
      groupKeyService: _groupKeyService,
      chatRepository: _chatRepository,
      chatSummaryService: _chatSummaryService,
      chatFileQueueService: _chatFileQueueService,
      groupOutboundCoordinator: _groupOutboundCoordinator,
      chats: chats,
      deleteManagedMediaForMessage: _deleteManagedMediaForMessage,
      removeMessage: _removeMessage,
      persistChatSummary: _persistChatSummary,
      rememberDeletedGroup: _rememberDeletedGroup,
      runGroupKeyGc: _runGroupKeyGc,
      syncBadgeCount: _syncBadgeCount,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
    _mediaRestoreService = ChatMediaRestoreService(
      relayMediaTransfer: _relayMediaTransfer,
      relayMediaRetry: _relayMediaRetry,
      findMessage: _findMessage,
      replaceMessage: _replaceMessage,
      updateFileProgress: _updateFileProgress,
      saveMediaBytes:
          ({
            required peerId,
            required messageId,
            required fileName,
            required bytes,
          }) {
            return _storage.saveMediaBytes(
              peerId: peerId,
              messageId: messageId,
              fileName: fileName,
              bytes: bytes,
            );
          },
      clearProgressUpdate: _clearProgressUpdate,
      notifyMessageUpdated: (peerId) => _messageUpdatesController.add(peerId),
      mediaKeyFor: _incomingMediaKey,
      isMessageUpdatesClosed: () => _messageUpdatesController.isClosed,
    );
    _incomingMediaRestoreCoordinator = ChatIncomingMediaRestoreCoordinator(
      mediaRestoreService: _mediaRestoreService,
      outboundCodec: _outboundCodec,
      facade: facade,
      decodeGroupBlobBytes: _decodeGroupBlobBytes,
    );
    _fileProgressCoordinator = ChatControllerCoordinatorFactory.fileProgress(
      fileQueueService: _chatFileQueueService,
      chats: chats,
      incomingMediaRestoreCoordinator: _incomingMediaRestoreCoordinator,
      incomingRelayErrorStatus: _incomingRelayErrorStatus,
      incomingRelayNotConfiguredStatus: _incomingRelayNotConfiguredStatus,
      incomingRelayUnavailableStatus: _incomingRelayUnavailableStatus,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
    _groupInboundCoordinator = ChatGroupInboundCoordinator(
      facade: facade,
      inboundService: _chatInboundService,
      inboundClassifier: _inboundClassifier,
      chatSummaryService: _chatSummaryService,
      groupFlowService: _groupFlowService,
      groupKeyService: _groupKeyService,
      outboundCodec: _outboundCodec,
      chats: chats,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      persistChatSummary: _persistChatSummary,
      appendMessage: _appendMessage,
      removeMessageByAuthorWithMediaCleanup:
          _removeMessageByAuthorWithMediaCleanup,
      notifyMessageUpdated: _notifyMessageUpdated,
      notifyNewMessage: _newMessageNotificationController.add,
      unreadMessagesCount: unreadMessagesCount,
      decryptGroupText: _decryptGroupText,
      decryptGroupBytes: _decryptGroupBytes,
      decodeGroupBlobBytes: _decodeGroupBlobBytes,
      saveGroupAvatarBytes: _saveGroupAvatarBytes,
      rotateGroupKey: _rotateGroupKey,
      syncGroupMembershipWithRelay: _syncGroupMembershipWithRelay,
      broadcastGroupMembersUpdate: _broadcastGroupMembersUpdate,
      deleteChatLocal: _deleteChatLocal,
      restoreGroupBlobText: _restoreGroupBlobText,
      restoreMediaInBackground: _restoreMediaInBackground,
    );
    _inboundSubscriptionCoordinator = ChatInboundSubscriptionCoordinator(
      facade: facade,
      inboundService: _chatInboundService,
      isGroupDeletePayload: _isGroupDeletePayload,
      handleIncomingGroupInvite: _handleIncomingGroupInvite,
      handleIncomingGroupKey: _handleIncomingGroupKey,
      handleIncomingGroupDelete: _handleIncomingGroupDelete,
      handleIncomingGroupChatDelete: _handleIncomingGroupChatDelete,
      handleIncomingGroupMembersUpdate: _handleIncomingGroupMembersUpdate,
      handleIncomingGroupMessage: _handleIncomingGroupMessage,
      handleIncomingGroupSecureMessage: _handleIncomingGroupSecureMessage,
      handleIncomingDirectBlobRef: _handleIncomingDirectBlobRef,
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      removeMessageByAuthorWithMediaCleanup:
          _removeMessageByAuthorWithMediaCleanup,
      setStatus: _setStatus,
      appendMessage: _appendMessage,
      unreadMessagesCount: unreadMessagesCount,
      notifyMessageUpdated: _notifyMessageUpdated,
      notifyNewMessage: _newMessageNotificationController.add,
    );
    _fileSendCoordinator = ChatControllerCoordinatorFactory.fileSend(
      fileTransferCoordinator: _fileTransferCoordinator,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: (peerId) => _ensureChat(peerId),
      nextLocalMessageId: _nextLocalMessageId,
      persistLoadedChat: _persistLoadedChat,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      logQueue: _logQueue,
      notifyMessageUpdated: _notifyMessageUpdated,
      refreshQueuedFileStatuses: _refreshQueuedFileStatuses,
      drainFileQueue: _drainFileQueue,
      sendGroupFile: _sendGroupFileAsync,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadChats());
    unawaited(_groupKeyService.initialize());
    _syncBadgeCount();
    _inboundSubscriptionCoordinator.start();
    _lifecycleService.start();
    unawaited(facade.pollRelay());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _lifecycleService.handleAppResumed();
    }
  }

  Future<void> _loadChats() async {
    await _historyLoadCoordinator.loadChats();
  }

  bool _isGroupDeleted(String groupId) {
    return _chatSummaryService.isGroupDeleted(groupId);
  }

  Future<void> _rememberDeletedGroup(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  }) async {
    await _chatSummaryService.rememberDeletedGroup(
      groupId,
      deletedByPeerId: deletedByPeerId,
      chat: chat,
    );
  }

  Future<void> _restoreDeletedGroup(String groupId) async {
    await _chatSummaryService.restoreDeletedGroup(groupId);
  }

  Future<void> _runGroupKeyGc() async {
    await _historyLoadCoordinator.runGroupKeyGc();
  }

  String _contactNameFor(String peerId, {String? fallback}) {
    return _chatContactsService.resolveChatName(peerId, fallback: fallback);
  }

  String? _replySenderLabel(String chatPeerId, Message? replyTo) {
    return _replyMetadataResolver.senderLabel(chatPeerId, replyTo);
  }

  String? _replyTextPreview(Message? replyTo) {
    return _replyMetadataResolver.textPreview(replyTo);
  }

  String? _replyKind(Message? replyTo) {
    return _replyMetadataResolver.kind(replyTo);
  }

  Chat _ensureChat(String peerId, {String? fallbackName}) {
    return _directLifecycleService.ensureChat(
      peerId,
      fallbackName: fallbackName,
    );
  }

  Future<void> ensureChatLoaded(String peerId) async {
    await _historyLoadCoordinator.ensureChatLoaded(
      peerId,
      ensureChat: (peerId) => _ensureChat(peerId),
    );
  }

  Future<void> _rememberOutgoingRelayMediaState(
    OutgoingRelayMediaState state,
  ) async {
    await _outgoingRelayMediaResumeService.remember(state);
  }

  Future<void> _forgetOutgoingRelayMediaState(
    String peerId,
    String messageId,
  ) async {
    await _outgoingRelayMediaResumeService.forget(peerId, messageId);
  }

  Future<void> _resumePendingOutgoingRelayMedia({
    required String reason,
  }) async {
    await _outgoingRelayMediaResumeService.resumePending(
      reason: reason,
      ensureChatLoaded: ensureChatLoaded,
      findChat: (peerId) => chats[peerId],
      updateFileProgress: _updateFileProgress,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      setStatus: _setStatus,
      notifyMessageUpdated: _notifyMessageUpdated,
      logQueue: _logQueue,
    );
  }

  /// Загружает следующую страницу сообщений (при прокрутке вверх)
  Future<bool> loadMoreMessages(String peerId) async {
    return _historyLoadCoordinator.loadMoreMessages(peerId);
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _historyLoadCoordinator.messageOffsetFromNewest(peerId, messageId);
  }

  Future<void> _persistChatSummary(Chat chat) async {
    await _chatSummaryService.persistChatSummary(chat);
  }

  void _schedulePersistChatSummary(String peerId) {
    final chat = chats[peerId];
    if (chat == null) {
      return;
    }
    unawaited(_persistChatSummary(chat));
  }

  Future<void> _persistLoadedChat(String peerId) async {
    await _historyLoadCoordinator.persistLoadedChat(peerId);
  }

  void _schedulePersistLoadedChat(String peerId) {
    _historyLoadCoordinator.schedulePersistLoadedChat(peerId);
  }

  Future<void> _appendMessage(String peerId, Message message) async {
    await _messageMutationService.appendMessage(peerId, message);
  }

  Future<bool> _removeMessage(String peerId, String messageId) async {
    return _messageMutationService.removeMessage(peerId, messageId);
  }

  Future<Message?> _findMessage(String peerId, String messageId) async {
    return _messageMutationService.findMessage(peerId, messageId);
  }

  Future<void> _deleteManagedMediaForMessage(Message? message) async {
    await _messageMutationService.deleteManagedMediaForMessage(message);
  }

  Future<bool> _removeMessageWithMediaCleanup(
    String peerId,
    String messageId,
  ) async {
    return _messageMutationService.removeMessageWithMediaCleanup(
      peerId,
      messageId,
    );
  }

  Future<bool> _removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  ) async {
    return _messageMutationService.removeMessageByAuthorWithMediaCleanup(
      peerId,
      messageId,
      authorPeerId,
    );
  }

  Future<void> _replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) async {
    await _messageMutationService.replaceMessage(peerId, messageId, transform);
  }

  bool _isGroupDeletePayload(String text) {
    return text.startsWith(_groupDeletePrefix);
  }

  Future<void> _rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) async {
    await _groupFlowService.rotateGroupKey(groupChat, recipients: recipients);
  }

  Future<String> _ensureGroupKey(Chat groupChat) async {
    return _groupCryptoCoordinator.ensureGroupKey(groupChat);
  }

  Future<void> _syncGroupMembershipWithRelay(Chat groupChat) async {
    await _groupCryptoCoordinator.syncGroupMembershipWithRelay(groupChat);
  }

  Future<String?> _encryptGroupText({
    required String groupId,
    required String plainText,
  }) async {
    return _groupCryptoCoordinator.encryptGroupText(
      groupId: groupId,
      plainText: plainText,
    );
  }

  Future<Uint8List?> _encryptGroupBytes({
    required String groupId,
    required Uint8List plainBytes,
  }) async {
    return _groupCryptoCoordinator.encryptGroupBytes(
      groupId: groupId,
      plainBytes: plainBytes,
    );
  }

  Future<String?> _decryptGroupText(String text) async {
    return _groupCryptoCoordinator.decryptGroupText(text);
  }

  Future<Uint8List?> _decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    return _groupCryptoCoordinator.decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  List<String> _collectGroupRecipients(Chat groupChat) {
    return _groupCryptoCoordinator.collectGroupRecipients(groupChat);
  }

  Future<void> _handleIncomingGroupInvite(
    ChatMessage msg, {
    IncomingGroupInvitePayload? payload,
  }) async {
    await _groupInboundCoordinator.handleInvite(msg, payload: payload);
  }

  Future<void> _handleIncomingGroupKey(
    ChatMessage msg, {
    IncomingGroupKeyPayload? payload,
  }) async {
    await _groupInboundCoordinator.handleKey(msg, payload: payload);
  }

  Future<void> _handleIncomingGroupDelete(
    ChatMessage msg, {
    IncomingGroupDeletePayload? payload,
  }) async {
    await _groupInboundCoordinator.handleDelete(msg, payload: payload);
  }

  Future<void> _handleIncomingGroupChatDelete(
    ChatMessage msg, {
    IncomingGroupChatDeletePayload? payload,
  }) async {
    await _groupInboundCoordinator.handleChatDelete(msg, payload: payload);
  }

  Future<void> _handleIncomingGroupSecureMessage(
    ChatMessage msg, {
    IncomingGroupSecurePayload? payload,
  }) async {
    await _groupInboundCoordinator.handleSecureMessage(msg, payload: payload);
  }

  Future<void> _handleIncomingGroupMessage(
    ChatMessage msg, {
    IncomingGroupMessagePayload? payload,
  }) async {
    await _groupInboundCoordinator.handleMessage(msg, payload: payload);
  }

  Future<void> _handleIncomingGroupMembersUpdate(
    ChatMessage msg, {
    IncomingGroupMembersPayload? payload,
  }) async {
    await _groupInboundCoordinator.handleMembersUpdate(msg, payload: payload);
  }

  Future<void> _handleIncomingDirectBlobRef(
    ChatMessage msg,
    IncomingBlobRefPayload blobRef,
  ) async {
    await _chatInboundService.handleIncomingDirectBlobRef(
      msg,
      blobRef,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: _ensureChat,
      persistLoadedChat: _persistLoadedChat,
      directBlobTransferId: _outboundCodec.directBlobTransferId,
      notifyMessageUpdated: _notifyMessageUpdated,
      shouldAutoRestoreIncomingMedia: _shouldAutoRestoreIncomingMedia,
      incomingRelayFetchStatus: _incomingRelayFetchStatus,
      restoreMediaInBackground: _restoreMediaInBackground,
      notifyNewMessage: _newMessageNotificationController.add,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification:
          NotificationService.instance.showMessageNotification,
    );
  }

  Stream<ChatMessage> get newMessageNotifications =>
      _newMessageNotificationController.stream;

  Stream<String> get connectionStatusStream =>
      _connectionStatusController.stream;
  Stream<String> get messageUpdatesStream => _messageUpdatesController.stream;
  String get localPeerId => facade.peerId;

  ChatConnectionStatus connectionStatus(String peerId) =>
      _connectionStatus[peerId] ?? ChatConnectionStatus.disconnected;

  String? connectionError(String peerId) => _connectionErrors[peerId];

  int unreadMessagesCount() {
    return _chatReadStateService.unreadMessagesCount(chats);
  }

  void _syncBadgeCount() {
    _chatReadStateService.syncBadgeCount(
      chats,
      setBadgeCount:
          _onUnreadBadgeCountChanged ??
          NotificationService.instance.setBadgeCount,
    );
  }

  String _nextLocalMessageId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now <= _lastGeneratedMessageId) {
      _lastGeneratedMessageId += 1;
    } else {
      _lastGeneratedMessageId = now;
    }
    return _lastGeneratedMessageId.toString();
  }

  String? contactNameForPeer(String peerId) {
    return _chatContactsService.contactNameForPeer(peerId);
  }

  List<Contact> getContacts() {
    return _chatContactsService.getContacts();
  }

  Future<void> addOrUpdateContact({
    required String peerId,
    required String name,
  }) async {
    await _chatContactsService.addOrUpdateContact(
      peerId: peerId,
      name: name,
      chats: chats,
      schedulePersistChatSummary: _schedulePersistChatSummary,
      notifyContactsUpdated: () {
        _messageUpdatesController.add('');
      },
    );
  }

  Future<void> setGroupAvatar({
    required String groupId,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {
    await _chatGroupService.setGroupAvatar(
      groupId: groupId,
      chats: chats,
      bytes: bytes,
      mimeType: mimeType,
      persistChatSummary: _persistChatSummary,
      encryptGroupBytes: _encryptGroupBytes,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> _saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) async {
    await _chatGroupService.saveGroupAvatarBytes(
      groupChat: groupChat,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: updatedAtMs,
      persistChatSummary: _persistChatSummary,
    );
  }

  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberPeerIds,
    bool sendInvites = true,
  }) async {
    return _chatGroupService.createGroupChat(
      name: name,
      memberPeerIds: memberPeerIds,
      chats: chats,
      sendInvites: sendInvites,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<Chat> createDirectChat({required String peerId, String? name}) async {
    return _directLifecycleService.createDirectChat(peerId: peerId, name: name);
  }

  Future<void> addGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) async {
    await _chatGroupService.addGroupParticipants(
      groupId: groupId,
      participantPeerIds: participantPeerIds,
      chats: chats,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> removeGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) async {
    await _chatGroupService.removeGroupParticipants(
      groupId: groupId,
      participantPeerIds: participantPeerIds,
      chats: chats,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> renameGroupChat({
    required String groupId,
    required String newName,
  }) async {
    await _chatGroupService.renameGroupChat(
      groupId: groupId,
      newName: newName,
      chats: chats,
      persistChatSummary: _persistChatSummary,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> sendMessage(
    String peerId,
    String text, {
    Message? replyTo,
  }) async {
    await _messageSendCoordinator.sendMessage(peerId, text, replyTo: replyTo);
  }

  Future<void> sendFile(
    String peerId, {
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    int? fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) async {
    await _fileSendCoordinator.sendFile(
      peerId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
    );
  }

  Future<void> _sendGroupFileAsync(
    Chat groupChat, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) async {
    await _groupOutboundCoordinator.sendGroupFile(
      groupChat,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
    );
  }

  Future<void> requestDeleteForEveryone(String peerId, String messageId) async {
    await _groupOutboundCoordinator.requestDeleteForEveryone(
      peerId,
      messageId,
      chat: chats[peerId],
    );
  }

  Future<void> _drainFileQueue() async {
    await _fileTransferCoordinator.drainFileQueue();
  }

  void _resumeRecoverableFileQueue() {
    _fileTransferCoordinator.resumeRecoverableFileQueue();
  }

  Future<void> _broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) async {
    await _groupOutboundCoordinator.broadcastGroupMembersUpdate(
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

  Future<void> applyGroupMembersUpdateFromPush(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  }) async {
    await _groupOutboundCoordinator.applyGroupMembersUpdateFromPush(
      payload,
      sourcePeerId: sourcePeerId,
    );
  }

  Future<void> cancelFileTransfer(String peerId, String messageId) async {
    await _fileTransferCoordinator.cancelFileTransfer(peerId, messageId);
  }

  Future<void> retryMessage(String peerId, String messageId) async {
    await _messageSendCoordinator.retryMessage(peerId, messageId);
  }

  Future<void> connect(String peerId) async {
    await _directLifecycleService.connect(peerId);
  }

  List<Chat> getChatsSorted() {
    return _directLifecycleService.getChatsSorted();
  }

  Future<void> clearManagedMediaReferencesInMemory() async {
    await _cleanupCoordinator.clearManagedMediaReferencesInMemory();
  }

  void clearAllChatsFromMemory() {
    _cleanupCoordinator.clearAllChatsFromMemory();
  }

  Chat openChat(String peerId, String name) {
    return _directLifecycleService.openChat(peerId, name);
  }

  Future<void> addMessage(String peerId, Message message) async {
    await ensureChatLoaded(peerId);
    final chat = _ensureChat(peerId);
    chat.messages.add(message);
    await _persistLoadedChat(peerId);
    _messageUpdatesController.add(peerId);
  }

  Future<void> deleteMessage(String peerId, String messageId) async {
    await _cleanupCoordinator.deleteMessage(peerId, messageId);
  }

  Future<void> deleteChat(String peerId) async {
    await _cleanupCoordinator.deleteChat(peerId);
  }

  Future<void> _deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup = false,
    String? deletedByPeerId,
  }) async {
    await _cleanupCoordinator.deleteChatLocal(
      peerId,
      rememberDeletedGroup: rememberDeletedGroup,
      deletedByPeerId: deletedByPeerId,
    );
  }

  Future<void> markChatAsRead(String peerId) async {
    try {
      await _chatReadStateService.markChatAsRead(
        peerId,
        chats: chats,
        chatRepository: _chatRepository,
        persistLoadedChat: _persistLoadedChat,
        persistChatSummary: _persistChatSummary,
        notifyMessageUpdated: _notifyMessageUpdated,
      );
      _syncBadgeCount();
    } catch (e, stack) {
      developer.log(
        '[chat] markChatAsRead failed peer=$peerId error=$e\n$stack',
        name: 'chat',
      );
    }
  }

  Future<void> _updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  ) async {
    await _messageSendCoordinator.updateMessageStatusById(
      peerId,
      messageId,
      status,
    );
  }

  String _transferStatusForError(Object error, {required String fallback}) {
    return _fileProgressCoordinator.transferStatusForError(
      error,
      fallback: fallback,
    );
  }

  Future<void> _updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    await _fileProgressCoordinator.updateFileProgress(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
    );
  }

  void _clearProgressUpdate(String peerId, String messageId) {
    _fileProgressCoordinator.clearProgressUpdate(peerId, messageId);
  }

  String _incomingMediaKey(String peerId, String messageId) =>
      RelayMediaRetryCoordinator.mediaKey(peerId, messageId);

  Future<void> _resumeInterruptedIncomingMediaQueue({
    required String reason,
  }) async {
    await _incomingMediaRestoreCoordinator.resumeInterruptedIncomingMediaQueue(
      chats: chats.values,
      reason: reason,
    );
  }

  Future<int> _resumeInterruptedIncomingMediaForChat(
    Chat chat, {
    required String reason,
  }) async {
    return _incomingMediaRestoreCoordinator
        .resumeInterruptedIncomingMediaForChat(chat, reason: reason);
  }

  void _refreshQueuedFileStatuses() {
    _fileTransferCoordinator.refreshQueuedFileStatuses();
  }

  Future<String?> restoreMediaFromEmbedded(String peerId, Message message) {
    return ChatControllerMedia.restoreMediaFromEmbedded(
      storage: _storage,
      peerId: peerId,
      message: message,
      replaceMessage: _replaceMessage,
    );
  }

  Future<String?> restoreGroupBlobMedia(Message message) {
    return _incomingMediaRestoreCoordinator.restoreGroupBlobMedia(message);
  }

  Future<String?> restoreDirectBlobMedia(Message message) {
    return _incomingMediaRestoreCoordinator.restoreDirectBlobMedia(message);
  }

  void _restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
  }) {
    _incomingMediaRestoreCoordinator.restoreMediaInBackground(
      message,
      isGroup: isGroup,
      force: force,
    );
  }

  bool isIncomingRelayMediaRestoreInProgress(Message message) {
    return _incomingMediaRestoreCoordinator
        .isIncomingRelayMediaRestoreInProgress(message);
  }

  bool isIncomingRelayMediaRestoreFailed(Message message) {
    return _incomingMediaRestoreCoordinator.isIncomingRelayMediaRestoreFailed(
      message,
    );
  }

  bool isInitialUnreadAnchor(Message message) {
    return _incomingMediaRestoreCoordinator.isInitialUnreadAnchor(message);
  }

  bool _shouldAutoRestoreIncomingMedia(Message message) {
    return _incomingMediaRestoreCoordinator.shouldAutoRestoreIncomingMedia(
      message,
    );
  }

  Future<Uint8List> _decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    return _groupCryptoCoordinator.decodeGroupBlobBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  Future<String?> _restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  }) async {
    return _incomingMediaRestoreCoordinator.restoreGroupBlobText(
      groupId: groupId,
      blobId: blobId,
      fallback: fallback,
    );
  }

  void _setStatus(String peerId, ChatConnectionStatus status, {String? error}) {
    _connectionStatus[peerId] = status;
    _connectionErrors[peerId] = error;
    _connectionStatusController.add(peerId);
  }

  void _notifyMessageUpdated(String peerId) {
    _messageUpdatesController.add(peerId);
  }

  void _logQueue(String message) {
    developer.log('queue:$message', name: 'chat');
    AppFileLogger.log('[chat_queue] $message');
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    _chatFileQueueService.dispose();
    _relayMediaRetry.dispose();
    _mediaRestoreService.dispose();
    await _inboundSubscriptionCoordinator.dispose();
    await _lifecycleService.dispose();
    await _connectionStatusController.close();
    await _messageUpdatesController.close();
    await _newMessageNotificationController.close();
  }

  Stream<List<String>> get discoveredPeersStream =>
      facade.discoveredPeersStream;

  Future<void> startCall(String peerId) => facade.startCall(peerId);
}
