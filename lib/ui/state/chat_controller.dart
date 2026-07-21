import 'dart:async';
import 'dart:convert';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/notification/notification_service.dart';
import '../../core/relay/relay_models.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/network_event_bus.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/group_message_crypto_service.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import '../models/contact.dart';
import '../models/message.dart';
import '../../core/runtime/avatar_service.dart';
import 'chat_controller_models.dart';
import 'chat_controller_media.dart';
import 'chat_group_flow_service.dart';
import 'chat_inbound_service.dart';
import 'chat_inbound_classifier.dart';
import 'chat_media_restore_service.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_service.dart';
import 'chat_controller_parts.dart';
import '../../core/relay/relay_media_transfer_service.dart';
import 'chat_file_queue_service.dart';
import 'chat_contacts_service.dart';
import 'chat_group_service.dart';
import 'chat_read_state_service.dart';
import 'chat_repository.dart';
import 'chat_summary_service.dart';

class ChatController with WidgetsBindingObserver {
  static int _lastGeneratedMessageId = 0;
  static const String _groupDeletePrefix = '__peerlink_group_delete_v1__:';
  static const String _incomingRelayFetchStatus =
      RelayMediaTransferService.incomingFetchStatus;
  static const String _incomingRelayDecryptStatus =
      RelayMediaTransferService.incomingDecryptStatus;
  static const String _incomingRelayNotConfiguredStatus =
      RelayMediaTransferService.incomingRelayNotConfiguredStatus;
  static const String _incomingRelayErrorStatus =
      RelayMediaTransferService.incomingErrorStatus;
  static const String _incomingRelayUnavailableStatus =
      RelayMediaTransferService.incomingRelayUnavailableStatus;
  static const String _outgoingRelayMediaStateKey =
      'outgoing_relay_media_state.v1';
  final NodeFacade facade;
  final StorageService _storage;
  final SecureStorageBox _settingsBox;
  final SecureStorageBox _groupMetaBox;
  final GroupKeyService _groupKeyService;
  final AvatarService _avatarService;
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
  late final ChatInboundService _chatInboundService;
  late final ChatReadStateService _chatReadStateService;
  late final ChatContactsService _chatContactsService;
  late final ChatGroupService _chatGroupService;
  late final GroupMessageCryptoService _groupMessageCryptoService;

  final Map<String, Chat> chats = {};
  final Map<String, ChatConnectionStatus> _connectionStatus = {};
  final Map<String, String?> _connectionErrors = {};
  final _connectionStatusController = StreamController<String>.broadcast();
  final _messageUpdatesController = StreamController<String>.broadcast();
  final _newMessageNotificationController =
      StreamController<ChatMessage>.broadcast();
  StreamSubscription<String>? _peerConnectedSub;
  StreamSubscription<String>? _peerDisconnectedSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  NetworkEventHandlerRegistration? _messageEventRegistration;
  final Set<String> _outgoingRelayMediaResumeInFlight = <String>{};
  final void Function(int unreadCount)? _onUnreadBadgeCountChanged;

  ChatController(
    this.facade, {
    required StorageService storage,
    required AvatarService avatarService,
    void Function(int unreadCount)? onUnreadBadgeCountChanged,
  }) : _storage = storage,
       _avatarService = avatarService,
       _onUnreadBadgeCountChanged = onUnreadBadgeCountChanged,
       _settingsBox = storage.getSettings(),
       _groupMetaBox = storage.getGroupMeta(),
       _groupKeyService = GroupKeyService.forSecureStorageBox(
         storage.getGroupKeys(),
       ) {
    _relayMediaRetry = RelayMediaRetryCoordinator(settingsBox: _settingsBox);
    _outboundCodec = ChatOutboundCodec(
      localPeerIdProvider: () => facade.peerId,
    );
    _chatOutboundService = ChatOutboundService(
      facade: facade,
      relayMediaTransfer: _relayMediaTransfer,
      outboundCodec: _outboundCodec,
    );
    _groupFlowService = ChatGroupFlowService(
      facade: facade,
      groupKeyService: _groupKeyService,
      outboundCodec: _outboundCodec,
      nextLocalMessageId: _nextLocalMessageId,
    );
    _chatSummaryService = ChatSummaryService(
      storage: _storage,
      settingsBox: _settingsBox,
      groupMetaBox: _groupMetaBox,
    );
    _chatReadStateService = const ChatReadStateService();
    _chatContactsService = ChatContactsService(
      contactsBox: storage.getContacts(),
    );
    _chatFileQueueService = ChatFileQueueService();
    _chatGroupService = ChatGroupService(
      facade: facade,
      storage: _storage,
      groupFlowService: _groupFlowService,
    );
    _groupMessageCryptoService = GroupMessageCryptoService(
      groupKeyService: _groupKeyService,
      securePayloadPrefix: ChatOutboundCodec.groupSecurePrefix,
    );
    _chatRepository = ChatRepository(
      storage: _storage,
      ensureChat: _ensureChat,
      persistChatSummary: _persistChatSummary,
      isInitialUnreadAnchor: isInitialUnreadAnchor,
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
    _inboundClassifier = ChatInboundClassifier(
      decodeGroupInvitePayload: _outboundCodec.decodeGroupInvitePayload,
      decodeGroupKeyPayload: _outboundCodec.decodeGroupKeyPayload,
      decodeGroupDeletePayload: _outboundCodec.decodeGroupDeletePayload,
      decodeGroupChatDeletePayload: _outboundCodec.decodeGroupChatDeletePayload,
      decodeGroupMembersPayload: _outboundCodec.decodeGroupMembersPayload,
      decodeGroupMessagePayload: _outboundCodec.decodeGroupMessagePayload,
      decodeGroupSecurePayloadRaw: _outboundCodec.decodeGroupSecurePayloadRaw,
      decodeDirectBlobRefPayload: _outboundCodec.decodeDirectBlobRefPayload,
      decodeGroupBlobRefPayload: _outboundCodec.decodeGroupBlobRefPayload,
      decodeAccountPairRequestPayload: _decodeAccountPairRequestPayload,
      decodeAccountPairApprovalPayload: _decodeAccountPairApprovalPayload,
      decodeAccountPairRejectionPayload: _decodeAccountPairRejectionPayload,
      decodeAccountMembershipUpdatePayload:
          _decodeAccountMembershipUpdatePayload,
    );
    _chatInboundService = ChatInboundService(
      facade: facade,
      settingsBox: _settingsBox,
      avatarService: _avatarService,
      inboundClassifier: _inboundClassifier,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadChats());
    unawaited(_groupKeyService.initialize());
    _syncBadgeCount();
    _listenMessages();
    _peerConnectedSub = facade.peerConnectedStream.listen((peerId) {
      _setStatus(peerId, ChatConnectionStatus.connected);
    });
    _peerDisconnectedSub = facade.peerDisconnectedStream.listen((peerId) {
      _setStatus(peerId, ChatConnectionStatus.disconnected);
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (_hasNetworkConnectivity(results)) {
        unawaited(facade.pollRelay());
        unawaited(_resumePendingOutgoingRelayMedia(reason: 'connectivity'));
        unawaited(_resumeInterruptedIncomingMediaQueue(reason: 'connectivity'));
      }
    });
    unawaited(facade.pollRelay());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncBadgeCount();
      _logQueue('resume app lifecycle');
      _resumeRecoverableFileQueue();
      unawaited(facade.pollRelay());
      unawaited(_resumePendingOutgoingRelayMedia(reason: 'app-resume'));
      unawaited(_resumeInterruptedIncomingMediaQueue(reason: 'app-resume'));
    }
  }

  Future<void> _loadChats() async {
    _chatSummaryService.loadGroupMetaFromSettings();
    final summaries = await _storage.loadAllChatSummaries();
    for (final raw in summaries) {
      try {
        final chat = Chat.fromJson(Map<String, dynamic>.from(raw));
        if (_chatSummaryService.isGroupDeleted(chat.peerId)) {
          await _storage.deletePeerMediaDirectory(chat.peerId);
          await _storage.deleteChatSummaryMap(chat.peerId);
          await _storage.deleteChatMessages(chat.peerId);
          continue;
        }
        _chatSummaryService.applyGroupMeta(chat);
        if (!chat.isGroup && Chat.isGroupLikePeerId(chat.peerId)) {
          chat.isGroup = true;
        }
        chat.messagesLoaded = false;
        chat.name = _contactNameFor(chat.peerId, fallback: chat.name);
        chats[chat.peerId] = chat;
      } catch (_) {
        // Ignore invalid persisted chat entries.
      }
    }
    await _runGroupKeyGc();
    _syncBadgeCount();
    _messageUpdatesController.add('');
    unawaited(facade.pollRelay());
    unawaited(_resumePendingOutgoingRelayMedia(reason: 'startup'));
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
    final activeGroupIds = chats.values
        .where((chat) => chat.isGroup || Chat.isGroupLikePeerId(chat.peerId))
        .map((chat) => chat.peerId)
        .toSet();
    await _groupKeyService.runGc(activeGroupIds: activeGroupIds);
  }

  String _contactNameFor(String peerId, {String? fallback}) {
    return _chatContactsService.resolveChatName(peerId, fallback: fallback);
  }

  String _shortPeerId(String peerId) {
    if (peerId.length <= 8) {
      return peerId;
    }
    return '${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}';
  }

  String? _replySenderLabel(String chatPeerId, Message? replyTo) {
    if (replyTo == null) {
      return null;
    }
    if (!(replyTo.incoming)) {
      return 'Вы';
    }
    final senderPeerId = (replyTo.senderPeerId ?? chatPeerId).trim();
    if (senderPeerId.isEmpty) {
      return null;
    }
    final contactName = _contactNameFor(senderPeerId, fallback: null);
    if (contactName.isNotEmpty) {
      return contactName;
    }
    return _shortPeerId(senderPeerId);
  }

  String? _replyTextPreview(Message? replyTo) {
    if (replyTo == null) {
      return null;
    }
    if (replyTo.kind == MessageKind.file) {
      if (replyTo.isAudio) {
        return 'Голосовое сообщение';
      }
      if (replyTo.isImage) {
        return 'Фото';
      }
      if (replyTo.isVideo) {
        return 'Видео';
      }
      return replyTo.fileName?.trim().isNotEmpty == true
          ? replyTo.fileName!.trim()
          : 'Файл';
    }
    final text = replyTo.text.trim();
    if (text.isEmpty) {
      return 'Сообщение';
    }
    return text.length <= 120 ? text : '${text.substring(0, 120)}…';
  }

  String? _replyKind(Message? replyTo) {
    if (replyTo == null) {
      return null;
    }
    return replyTo.kind == MessageKind.file ? 'file' : 'text';
  }

  Chat _ensureChat(String peerId, {String? fallbackName}) {
    final chat = chats.putIfAbsent(
      peerId,
      () => Chat(
        peerId: peerId,
        name: _contactNameFor(peerId, fallback: fallbackName ?? peerId),
      ),
    );

    final resolvedName = _contactNameFor(peerId, fallback: chat.name);
    if (chat.name != resolvedName) {
      chat.name = resolvedName;
      _schedulePersistChatSummary(peerId);
    }
    if (!chat.isGroup && Chat.isGroupLikePeerId(chat.peerId)) {
      chat.isGroup = true;
      _schedulePersistChatSummary(peerId);
    }

    return chat;
  }

  static const int _initialLoadLimit = 50;
  static const int _paginationLimit = 50;

  Future<void> ensureChatLoaded(String peerId) async {
    final chat = _ensureChat(peerId);
    if (chat.messagesLoaded) {
      return;
    }

    // Загружаем только последние 50 сообщений + весь хвост непрочитанных.
    final stored = await _chatRepository.loadInitialMessages(
      peerId,
      _initialLoadLimit,
    );
    await _processLoadedMessages(peerId, stored);

    chat.messages = stored;
    chat.messagesLoaded = true;
    chat.hasMoreMessages = await _chatRepository.hasMoreMessages(
      peerId,
      stored.length,
    );
    _chatRepository.refreshSummaryFromMessages(chat, stored);
    _recoverPendingFileTransfersForChat(chat);
    developer.log(
      '[chat] ensureChatLoaded peer=$peerId initialLoaded=${stored.length} '
      'hasMore=${chat.hasMoreMessages}',
      name: 'chat',
    );

    _messageUpdatesController.add(peerId);
    unawaited(
      _resumeInterruptedIncomingMediaForChat(chat, reason: 'chat-load'),
    );
  }

  Map<String, OutgoingRelayMediaState> _loadOutgoingRelayMediaStates() {
    final raw = _settingsBox.get(_outgoingRelayMediaStateKey);
    if (raw is! Map) {
      return <String, OutgoingRelayMediaState>{};
    }
    final result = <String, OutgoingRelayMediaState>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) {
        return;
      }
      final state = OutgoingRelayMediaState.fromJson(
        Map<String, dynamic>.from(value),
      );
      if (state != null) {
        result[key] = state;
      }
    });
    return result;
  }

  Future<void> _saveOutgoingRelayMediaStates(
    Map<String, OutgoingRelayMediaState> states,
  ) {
    return _settingsBox.put(
      _outgoingRelayMediaStateKey,
      states.map(
        (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
      ),
    );
  }

  String _outgoingRelayMediaStateId(String peerId, String messageId) =>
      '$peerId::$messageId';

  Future<void> _rememberOutgoingRelayMediaState(
    OutgoingRelayMediaState state,
  ) async {
    final states = _loadOutgoingRelayMediaStates();
    states[_outgoingRelayMediaStateId(state.peerId, state.messageId)] = state;
    await _saveOutgoingRelayMediaStates(states);
  }

  Future<void> _forgetOutgoingRelayMediaState(
    String peerId,
    String messageId,
  ) async {
    final states = _loadOutgoingRelayMediaStates();
    if (states.remove(_outgoingRelayMediaStateId(peerId, messageId)) == null) {
      return;
    }
    await _saveOutgoingRelayMediaStates(states);
  }

  Future<void> _resumePendingOutgoingRelayMedia({
    required String reason,
  }) async {
    final states = _loadOutgoingRelayMediaStates();
    if (states.isEmpty) {
      return;
    }
    var resumed = 0;
    for (final entry in states.entries) {
      final state = entry.value;
      final key = entry.key;
      if (_outgoingRelayMediaResumeInFlight.contains(key)) {
        continue;
      }
      _outgoingRelayMediaResumeInFlight.add(key);
      resumed += 1;
      unawaited(
        _resumeOutgoingRelayMediaState(
          state,
          key: key,
          reason: reason,
        ).whenComplete(() {
          _outgoingRelayMediaResumeInFlight.remove(key);
        }),
      );
    }
    _logQueue('resume relay-media reason=$reason count=$resumed');
  }

  Future<void> _resumeOutgoingRelayMediaState(
    OutgoingRelayMediaState state, {
    required String key,
    required String reason,
  }) async {
    try {
      await ensureChatLoaded(state.peerId);
      final chat = chats[state.peerId];
      if (chat == null) {
        await _forgetOutgoingRelayMediaState(state.peerId, state.messageId);
        return;
      }
      final index = chat.messages.indexWhere(
        (message) => message.id == state.messageId,
      );
      if (index < 0) {
        await _forgetOutgoingRelayMediaState(state.peerId, state.messageId);
        return;
      }
      final message = chat.messages[index];
      final alreadySentTransferId = message.transferId?.trim() ?? '';
      if (message.status == MessageStatus.sent &&
          alreadySentTransferId.contains(state.blobId)) {
        await _forgetOutgoingRelayMediaState(state.peerId, state.messageId);
        return;
      }
      if (message.incoming || message.kind != MessageKind.file) {
        await _forgetOutgoingRelayMediaState(state.peerId, state.messageId);
        return;
      }

      await _updateFileProgress(
        state.peerId,
        state.messageId,
        sentBytes: message.fileSizeBytes ?? 0,
        totalBytes: message.fileSizeBytes ?? 0,
        statusText: 'Повторная отправка',
      );

      await facade.sendPayload(
        state.peerId,
        targetKind: state.targetKind == OutgoingRelayMediaTargetKind.group
            ? ChatPayloadTargetKind.group
            : ChatPayloadTargetKind.direct,
        recipients: state.recipients,
        text: state.payloadText,
        messageId: state.messageId,
        replyToMessageId: state.replyToMessageId,
        replyToSenderPeerId: state.replyToSenderPeerId,
        replyToSenderLabel: state.replyToSenderLabel,
        replyToTextPreview: state.replyToTextPreview,
        replyToKind: state.replyToKind,
      );

      await _replaceMessage(
        state.peerId,
        state.messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferId: state.targetKind == OutgoingRelayMediaTargetKind.group
              ? _outboundCodec.groupBlobTransferId(
                  groupId: state.peerId,
                  messageId: state.messageId,
                  blobId: state.blobId,
                )
              : _outboundCodec.directBlobTransferId(
                  peerId: state.peerId,
                  messageId: state.messageId,
                  blobId: state.blobId,
                ),
          localFilePath:
              current.localFilePath ??
              ((state.localFilePath?.isNotEmpty ?? false)
                  ? state.localFilePath
                  : current.localFilePath),
          transferredBytes: null,
          sendProgress: null,
          transferStatus: null,
          status: MessageStatus.sent,
        ),
      );
      _clearProgressUpdate(state.peerId, state.messageId);
      await _forgetOutgoingRelayMediaState(state.peerId, state.messageId);
      _setStatus(state.peerId, ChatConnectionStatus.connected);
      _messageUpdatesController.add(state.peerId);
      _logQueue(
        'resume relay-media done reason=$reason peer=${state.peerId} '
        'messageId=${state.messageId} blobId=${state.blobId}',
      );
    } catch (error) {
      _logQueue(
        'resume relay-media failed reason=$reason peer=${state.peerId} '
        'messageId=${state.messageId} error=$error',
      );
    }
  }

  /// Обрабатывает загруженные сообщения (восстанавливает медиа файлы)
  Future<void> _processLoadedMessages(String peerId, List<Message> stored) {
    return ChatControllerMedia.processLoadedMessages(
      storage: _storage,
      peerId: peerId,
      stored: stored,
      writeStoredMessages: _chatRepository.writeStoredMessages,
      upsertStoredMessages: _chatRepository.upsertStoredMessages,
      deleteStoredMessagesByIds: _chatRepository.deleteStoredMessagesByIds,
      persistChatSummary: (id) async => _persistChatSummary(_ensureChat(id)),
      deleteManagedMediaForMessage: _deleteManagedMediaForMessage,
    );
  }

  /// Загружает следующую страницу сообщений (при прокрутке вверх)
  Future<bool> loadMoreMessages(String peerId) async {
    final chat = chats[peerId];
    if (chat == null || !chat.messagesLoaded) {
      developer.log(
        '[chat] loadMore skipped peer=$peerId reason=chat-not-loaded',
        name: 'chat',
      );
      return false;
    }

    if (!chat.hasMoreMessages) {
      developer.log(
        '[chat] loadMore skipped peer=$peerId reason=no-more '
        'loaded=${chat.messages.length}',
        name: 'chat',
      );
      return false;
    }

    final currentCount = chat.messages.length;
    developer.log(
      '[chat] loadMore start peer=$peerId currentCount=$currentCount '
      'pageSize=$_paginationLimit',
      name: 'chat',
    );
    final olderMessages = await _chatRepository.readOlderMessages(
      peerId,
      currentCount,
      _paginationLimit,
    );

    if (olderMessages.isEmpty) {
      chat.hasMoreMessages = false;
      developer.log(
        '[chat] loadMore empty peer=$peerId currentCount=$currentCount',
        name: 'chat',
      );
      return false;
    }

    await _processLoadedMessages(peerId, olderMessages);

    // Вставляем загруженные сообщения в начало списка
    chat.messages.insertAll(0, olderMessages);
    chat.hasMoreMessages = olderMessages.length == _paginationLimit;
    developer.log(
      '[chat] loadMore success peer=$peerId fetched=${olderMessages.length} '
      'loadedNow=${chat.messages.length} hasMoreNow=${chat.hasMoreMessages}',
      name: 'chat',
    );

    _messageUpdatesController.add(peerId);
    unawaited(
      _resumeInterruptedIncomingMediaForChat(chat, reason: 'load-more'),
    );
    return true;
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _chatRepository.messageOffsetFromNewest(peerId, messageId);
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
    final chat = chats[peerId];
    if (chat == null) {
      return;
    }
    await _chatRepository.persistLoadedChat(chat);
  }

  void _schedulePersistLoadedChat(String peerId) {
    unawaited(_persistLoadedChat(peerId));
  }

  Future<void> _appendMessage(String peerId, Message message) async {
    await _chatRepository.appendMessage(peerId, message);
  }

  Future<bool> _removeMessage(String peerId, String messageId) async {
    return _chatRepository.removeMessage(
      peerId,
      messageId,
      loadedChat: chats[peerId],
    );
  }

  Future<Message?> _findMessage(String peerId, String messageId) async {
    return _chatRepository.findMessage(
      peerId,
      messageId,
      loadedChat: chats[peerId],
    );
  }

  Future<void> _deleteManagedMediaForMessage(Message? message) async {
    final path = message?.localFilePath;
    if (!_storage.isManagedMediaPath(path)) {
      return;
    }
    await _storage.deleteMediaFile(path);
  }

  Future<bool> _removeMessageWithMediaCleanup(
    String peerId,
    String messageId,
  ) async {
    final message = await _findMessage(peerId, messageId);
    await _deleteManagedMediaForMessage(message);
    return _removeMessage(peerId, messageId);
  }

  Future<bool> _removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  ) async {
    final message = await _findMessage(peerId, messageId);
    if (message == null) {
      return false;
    }
    final expectedAuthor = (message.senderPeerId ?? message.peerId).trim();
    final requestedAuthor = authorPeerId.trim();
    if (expectedAuthor.isEmpty ||
        requestedAuthor.isEmpty ||
        expectedAuthor != requestedAuthor) {
      developer.log(
        '[chat] delete ignored author mismatch peer=$peerId '
        'messageId=$messageId expected=$expectedAuthor requested=$requestedAuthor',
        name: 'chat',
      );
      return false;
    }
    await _deleteManagedMediaForMessage(message);
    return _removeMessage(peerId, messageId);
  }

  Future<void> _replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) async {
    await _chatRepository.replaceMessage(peerId, messageId, transform);
  }

  void _listenMessages() {
    _messageEventRegistration = facade.addMessageEventHandler((event) async {
      final msg = event.payload;
      await _chatInboundService.handleIncomingMessage(
        msg,
        handleIncomingGroupInvite: (msg, payload) =>
            _handleIncomingGroupInvite(msg, payload: payload),
        handleIncomingGroupKey: (msg, payload) =>
            _handleIncomingGroupKey(msg, payload: payload),
        handleIncomingGroupDelete: (msg, payload) =>
            _handleIncomingGroupDelete(msg, payload: payload),
        handleIncomingGroupChatDelete: (msg, payload) =>
            _handleIncomingGroupChatDelete(msg, payload: payload),
        handleIncomingGroupMembersUpdate: (msg, payload) =>
            _handleIncomingGroupMembersUpdate(msg, payload: payload),
        handleIncomingGroupMessage: (msg, payload) =>
            _handleIncomingGroupMessage(msg, payload: payload),
        handleIncomingGroupSecureMessage: (msg, payload) =>
            _handleIncomingGroupSecureMessage(msg, payload: payload),
        handleIncomingDirectBlobRef: _handleIncomingDirectBlobRef,
        removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
        removeMessageByAuthorWithMediaCleanup:
            _removeMessageByAuthorWithMediaCleanup,
        isGroupDeletePayload: _isGroupDeletePayload,
        setStatus: _setStatus,
        appendMessage: _appendMessage,
        unreadMessagesCount: unreadMessagesCount,
        notifyMessageUpdated: _notifyMessageUpdated,
        notifyNewMessage: (msg) => _newMessageNotificationController.add(msg),
        showMessageNotification:
            ({required fromPeerId, required message, required badgeCount}) =>
                NotificationService.instance.showMessageNotification(
                  fromPeerId: fromPeerId,
                  message: message,
                  badgeCount: badgeCount,
                ),
      );
    });
  }

  bool _isGroupDeletePayload(String text) {
    return text.startsWith(_groupDeletePrefix);
  }

  AccountPairingRequestPayload? _decodeAccountPairRequestPayload(
    ChatMessage msg,
  ) {
    if (msg.kind != 'accountPairRequest' || msg.text.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(msg.text);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingRequestPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  AccountPairingApprovalPayload? _decodeAccountPairApprovalPayload(
    ChatMessage msg,
  ) {
    if (msg.kind != 'accountPairApproval' || msg.text.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(msg.text);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingApprovalPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  AccountPairingRejectedPayload? _decodeAccountPairRejectionPayload(
    ChatMessage msg,
  ) {
    if (msg.kind != 'accountPairRejection' || msg.text.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(msg.text);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingRejectedPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  AccountMembershipUpdatePayload? _decodeAccountMembershipUpdatePayload(
    ChatMessage msg,
  ) {
    if (msg.kind != 'accountMembershipUpdate' || msg.text.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(msg.text);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountMembershipUpdatePayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) async {
    await _groupFlowService.rotateGroupKey(groupChat, recipients: recipients);
  }

  Future<String> _ensureGroupKey(Chat groupChat) async {
    return _groupFlowService.ensureGroupKey(groupChat);
  }

  Future<void> _syncGroupMembershipWithRelay(Chat groupChat) async {
    await _groupFlowService.syncGroupMembershipWithRelay(groupChat);
  }

  Future<String?> _encryptGroupText({
    required String groupId,
    required String plainText,
  }) async {
    return _groupMessageCryptoService.encryptGroupText(
      groupId: groupId,
      plainText: plainText,
    );
  }

  Future<Uint8List?> _encryptGroupBytes({
    required String groupId,
    required Uint8List plainBytes,
  }) async {
    return _groupMessageCryptoService.encryptGroupBytes(
      groupId: groupId,
      plainBytes: plainBytes,
    );
  }

  Future<String?> _decryptGroupText(String text) async {
    return _groupMessageCryptoService.decryptGroupText(text);
  }

  Future<Uint8List?> _decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    return _groupMessageCryptoService.decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  List<String> _collectGroupRecipients(Chat groupChat) {
    return _groupFlowService.collectGroupRecipients(groupChat);
  }

  Future<void> _handleIncomingGroupInvite(
    ChatMessage msg, {
    IncomingGroupInvitePayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupInvite(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupInvitePayload,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      chats: chats,
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      localPeerId: facade.peerId,
    );
  }

  Future<void> _handleIncomingGroupKey(
    ChatMessage msg, {
    IncomingGroupKeyPayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupKey(
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

  Future<void> _handleIncomingGroupDelete(
    ChatMessage msg, {
    IncomingGroupDeletePayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupDelete(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupDeletePayload,
      removeMessageByAuthorWithMediaCleanup:
          _removeMessageByAuthorWithMediaCleanup,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> _handleIncomingGroupChatDelete(
    ChatMessage msg, {
    IncomingGroupChatDeletePayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupChatDelete(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupChatDeletePayload,
      knownGroupOwnerPeerId: _knownGroupOwnerPeerId,
      deleteChatLocal:
          (
            peerId, {
            bool rememberDeletedGroup = false,
            String? deletedByPeerId,
          }) => _deleteChatLocal(
            peerId,
            rememberDeletedGroup: rememberDeletedGroup,
            deletedByPeerId: deletedByPeerId,
          ),
    );
  }

  Future<void> _handleIncomingGroupSecureMessage(
    ChatMessage msg, {
    IncomingGroupSecurePayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupSecureMessage(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupSecurePayload,
      isGroupDeleted: _isGroupDeleted,
      decryptGroupText: _decryptGroupText,
      chats: chats,
      localPeerId: facade.peerId,
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
          }) => _handleIncomingGroupBlobRef(
            msg,
            groupId: groupId,
            groupChat: groupChat,
            existingGroupChat: existingGroupChat,
            blobRef: blobRef,
            notificationSenderLabel: notificationSenderLabel,
          ),
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      notifyNewMessage: (msg) => _newMessageNotificationController.add(msg),
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification:
          ({required fromPeerId, required message, required badgeCount}) =>
              NotificationService.instance.showMessageNotification(
                fromPeerId: fromPeerId,
                message: message,
                badgeCount: badgeCount,
              ),
    );
  }

  Future<void> _handleIncomingGroupMessage(
    ChatMessage msg, {
    IncomingGroupMessagePayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupMessage(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupMessagePayload,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      chats: chats,
      localPeerId: facade.peerId,
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
          }) => _handleIncomingGroupBlobRef(
            msg,
            groupId: groupId,
            groupChat: groupChat,
            existingGroupChat: existingGroupChat,
            blobRef: blobRef,
            notificationSenderLabel: notificationSenderLabel,
          ),
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      notifyNewMessage: (msg) => _newMessageNotificationController.add(msg),
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification:
          ({required fromPeerId, required message, required badgeCount}) =>
              NotificationService.instance.showMessageNotification(
                fromPeerId: fromPeerId,
                message: message,
                badgeCount: badgeCount,
              ),
    );
  }

  String? _knownGroupOwnerPeerId(String groupId) {
    final chat = chats[groupId];
    final chatOwner = chat?.ownerPeerId?.trim();
    if (chatOwner != null && chatOwner.isNotEmpty) {
      return chatOwner;
    }
    return _chatSummaryService.knownGroupOwnerPeerId(groupId);
  }

  Future<void> _handleIncomingGroupMembersUpdate(
    ChatMessage msg, {
    IncomingGroupMembersPayload? payload,
  }) async {
    await _chatInboundService.handleIncomingGroupMembersUpdate(
      msg,
      payload: payload,
      normalizePayload: _inboundClassifier.normalizeGroupMembersPayload,
      isGroupDeleted: _isGroupDeleted,
      restoreDeletedGroup: _restoreDeletedGroup,
      chats: chats,
      localPeerId: facade.peerId,
      persistChatSummary: _persistChatSummary,
      saveGroupAvatarBytes: _saveGroupAvatarBytes,
      downloadBlob: facade.downloadBlob,
      decryptGroupBytes: _decryptGroupBytes,
      handleIncomingGroupLeave: (incomingMsg, {required payload}) =>
          _handleIncomingGroupLeave(incomingMsg, payload: payload),
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> _handleIncomingGroupLeave(
    ChatMessage msg, {
    required IncomingGroupMembersPayload payload,
  }) async {
    await _chatInboundService.handleIncomingGroupLeave(
      msg,
      payload: payload,
      chats: chats,
      localPeerId: facade.peerId,
      persistChatSummary: _persistChatSummary,
      syncGroupMembershipWithRelay: _syncGroupMembershipWithRelay,
      rotateGroupKey: _rotateGroupKey,
      broadcastGroupMembersUpdate: _broadcastGroupMembersUpdate,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> _handleIncomingGroupBlobRef(
    ChatMessage msg, {
    required String groupId,
    required Chat groupChat,
    required Chat? existingGroupChat,
    required IncomingBlobRefPayload blobRef,
    required String notificationSenderLabel,
  }) async {
    await _chatInboundService.handleIncomingGroupBlobRef(
      msg,
      groupId: groupId,
      groupChat: groupChat,
      existingGroupChat: existingGroupChat,
      blobRef: blobRef,
      notificationSenderLabel: notificationSenderLabel,
      localPeerId: facade.peerId,
      restoreGroupBlobText: _restoreGroupBlobText,
      downloadBlob: facade.downloadBlob,
      decodeGroupBlobBytes: _decodeGroupBlobBytes,
      saveGroupAvatarBytes: _saveGroupAvatarBytes,
      groupBlobTransferId: _outboundCodec.groupBlobTransferId,
      appendMessage: _appendMessage,
      notifyMessageUpdated: _notifyMessageUpdated,
      restoreMediaInBackground: _restoreMediaInBackground,
      notifyNewMessage: _newMessageNotificationController.add,
      unreadMessagesCount: unreadMessagesCount,
      showMessageNotification:
          NotificationService.instance.showMessageNotification,
    );
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
    final chat = _ensureChat(peerId, fallbackName: name);
    if (chat.isGroup || Chat.isGroupLikePeerId(chat.peerId)) {
      // Do not downgrade existing group chats to p2p.
      _messageUpdatesController.add(peerId);
      return chat;
    }
    chat.isGroup = false;
    chat.memberPeerIds = const <String>[];
    chat.ownerPeerId = null;
    await _persistChatSummary(chat);
    _messageUpdatesController.add(peerId);
    return chat;
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
    await ensureChatLoaded(peerId);

    final message = Message(
      id: _nextLocalMessageId(),
      peerId: peerId,
      text: text,
      senderPeerId: facade.peerId,
      incoming: false,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
      replyToMessageId: replyTo?.id,
      replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
      replyToSenderLabel: _replySenderLabel(peerId, replyTo),
      replyToTextPreview: _replyTextPreview(replyTo),
      replyToKind: _replyKind(replyTo),
    );

    final chat = _ensureChat(peerId);
    chat.messages.add(message);
    await _persistLoadedChat(peerId);
    _messageUpdatesController.add(peerId);
    if (chat.isGroup) {
      unawaited(_sendGroupMessageAsync(chat, message));
    } else {
      unawaited(_sendMessageAsync(peerId, message));
    }
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
    final resolvedSize = fileSizeBytes ?? fileBytes?.length;
    if ((fileBytes == null && filePath == null) || resolvedSize == null) {
      throw ArgumentError('Either fileBytes or filePath must be provided');
    }

    // Limit file size to 1 GB
    const maxFileSize = 1024 * 1024 * 1024; // 1 GB in bytes
    if (resolvedSize > maxFileSize) {
      throw StateError('File size exceeds maximum limit of 1 GB');
    }

    await ensureChatLoaded(peerId);
    final chat = _ensureChat(peerId);

    final messageId = _nextLocalMessageId();
    _logQueue(
      'add peer=$peerId messageId=$messageId file=$fileName size=$resolvedSize path=${filePath?.isNotEmpty == true}',
    );
    chat.messages.add(
      Message(
        id: messageId,
        peerId: peerId,
        text: fileName,
        incoming: false,
        timestamp: DateTime.now(),
        kind: MessageKind.file,
        fileName: fileName,
        mimeType: mimeType,
        localFilePath: filePath,
        transferId: messageId,
        fileSizeBytes: resolvedSize,
        transferredBytes: 0,
        sendProgress: 0.02,
        transferStatus: 'В очереди',
        status: MessageStatus.sending,
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: _replySenderLabel(peerId, replyTo),
        replyToTextPreview: _replyTextPreview(replyTo),
        replyToKind: _replyKind(replyTo),
      ),
    );

    await _persistLoadedChat(peerId);
    _messageUpdatesController.add(peerId);

    if (chat.isGroup) {
      unawaited(
        _sendGroupFileAsync(
          chat,
          messageId: messageId,
          fileName: fileName,
          fileBytes: fileBytes,
          filePath: filePath,
          fileSizeBytes: resolvedSize,
          mimeType: mimeType,
          replyTo: replyTo,
        ),
      );
      return;
    }

    _chatFileQueueService.enqueue(
      QueuedFileTransfer(
        peerId: peerId,
        messageId: messageId,
        fileName: fileName,
        fileBytes: fileBytes,
        filePath: filePath,
        fileSizeBytes: resolvedSize,
        mimeType: mimeType,
        replyTo: replyTo,
      ),
    );
    _refreshQueuedFileStatuses();
    unawaited(_drainFileQueue());
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
    await _chatOutboundService.sendGroupFile(
      groupChat,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      persistChatSummary: _persistChatSummary,
      collectGroupRecipients: _collectGroupRecipients,
      ensureGroupKey: _ensureGroupKey,
      encryptGroupBytes: _encryptGroupBytes,
      encryptGroupText: _encryptGroupText,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      updateFileProgress: _updateFileProgress,
      rememberOutgoingRelayMediaState: _rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      saveMediaFile:
          ({
            required peerId,
            required messageId,
            required fileName,
            required sourcePath,
          }) => _storage.saveMediaFile(
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
          }) => _storage.saveMediaBytes(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            bytes: bytes,
          ),
      transferStatusForError: _transferStatusForError,
      setStatus: _setStatus,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> requestDeleteForEveryone(String peerId, String messageId) async {
    try {
      final chat = chats[peerId];
      if (chat != null && chat.isGroup) {
        final recipients = chat.memberPeerIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item != facade.peerId)
            .toSet()
            .toList(growable: false);
        final payload = _outboundCodec.encodeGroupDeletePayload(
          groupId: chat.peerId,
          messageId: messageId,
        );
        for (var i = 0; i < recipients.length; i++) {
          await facade.sendPayload(
            recipients[i],
            text: payload,
            messageId: 'delete:$messageId:$i',
          );
        }
        return;
      }
      await facade.sendDeleteMessage(peerId, messageId);
    } catch (e, stack) {
      developer.log('[chat] delete request failed: $e\n$stack', name: 'chat');
    }
  }

  Future<void> _broadcastGroupChatDelete(Chat groupChat) async {
    await _groupFlowService.broadcastGroupChatDelete(groupChat);
  }

  Future<void> _sendGroupLeaveBeforeLocalDelete(Chat groupChat) async {
    await _groupFlowService.sendGroupLeaveBeforeLocalDelete(groupChat);
  }

  Future<void> _drainFileQueue() async {
    await _chatFileQueueService.drain(
      logQueue: _logQueue,
      sendFile: (item) {
        return _sendFileAsync(
          item.peerId,
          messageId: item.messageId,
          fileName: item.fileName,
          fileBytes: item.fileBytes,
          filePath: item.filePath,
          fileSizeBytes: item.fileSizeBytes,
          mimeType: item.mimeType,
        );
      },
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      refreshQueuedFileStatuses: _refreshQueuedFileStatuses,
    );
  }

  void _resumeRecoverableFileQueue() {
    _chatFileQueueService.resumeRecoverableFileQueue(
      chats: chats.values,
      recoverPendingTransfersForChat: _recoverPendingFileTransfersForChat,
      logQueue: _logQueue,
      refreshQueuedFileStatuses: _refreshQueuedFileStatuses,
    );
    if (_chatFileQueueService.hasQueuedItems) {
      _refreshQueuedFileStatuses();
      unawaited(_drainFileQueue());
    }
  }

  int _recoverPendingFileTransfersForChat(Chat chat) {
    return _chatFileQueueService.recoverPendingTransfersForChat(
      chat,
      isRecoverableOutgoingFile: _isRecoverableOutgoingFile,
      rebuildReply: _rebuildReplyMessage,
      schedulePersistLoadedChat: _schedulePersistLoadedChat,
      notifyMessageUpdated: _notifyMessageUpdated,
      refreshQueuedFileStatuses: _refreshQueuedFileStatuses,
      logQueue: _logQueue,
    );
  }

  bool _isRecoverableOutgoingFile(Message message) {
    if (message.incoming ||
        message.kind != MessageKind.file ||
        message.status != MessageStatus.sending) {
      return false;
    }
    final status = message.transferStatus ?? '';
    return status == 'В очереди' ||
        status == 'Подготовка' ||
        status.startsWith('Ожидает отправки');
  }

  bool _isFileQueuedOrActive(String messageId) {
    return _chatFileQueueService.isQueuedOrActive(messageId);
  }

  Message? _rebuildReplyMessage(String peerId, Message message) {
    final replyId = message.replyToMessageId;
    if (replyId == null || replyId.isEmpty) {
      return null;
    }
    final rawKind = message.replyToKind;
    final kind = MessageKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => MessageKind.text,
    );
    final senderPeerId = message.replyToSenderPeerId;
    return Message(
      id: replyId,
      peerId: peerId,
      text: message.replyToTextPreview ?? '',
      senderPeerId: senderPeerId,
      incoming: senderPeerId != null && senderPeerId != facade.peerId,
      timestamp: DateTime.now(),
      kind: kind,
    );
  }

  Future<void> _sendMessageAsync(String peerId, Message message) async {
    await _chatOutboundService.sendDirectMessage(
      peerId,
      message,
      updateMessageStatusById: _updateMessageStatusById,
      setStatus: _setStatus,
    );
  }

  Future<void> _sendGroupMessageAsync(Chat groupChat, Message message) async {
    await _chatOutboundService.sendGroupMessage(
      groupChat,
      message,
      persistChatSummary: _persistChatSummary,
      ensureGroupKey: _ensureGroupKey,
      encryptGroupBytes: _encryptGroupBytes,
      encryptGroupText: _encryptGroupText,
      collectGroupRecipients: _collectGroupRecipients,
      updateMessageStatusById: _updateMessageStatusById,
      setStatus: _setStatus,
    );
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
    await _groupFlowService.broadcastGroupMembersUpdate(
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
    final senderPeerId = sourcePeerId?.trim().isNotEmpty == true
        ? sourcePeerId!.trim()
        : (payload['senderPeerId'] as String? ?? '').trim();
    if (senderPeerId.isEmpty) {
      return;
    }
    final message = ChatMessage(
      id: 'push-group-members:${DateTime.now().microsecondsSinceEpoch}',
      peerId: senderPeerId,
      kind: 'groupMembers',
      text: '${ChatOutboundCodec.groupMembersPrefix}${jsonEncode(payload)}',
    );
    await _handleIncomingGroupMembersUpdate(message);
  }

  Future<void> _sendFileAsync(
    String peerId, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) async {
    await _chatOutboundService.sendDirectFile(
      peerId,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      updateFileProgress: _updateFileProgress,
      logQueue: _logQueue,
      setStatus: _setStatus,
      rememberOutgoingRelayMediaState: _rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      isTransferCancelled: _chatFileQueueService.isTransferCancelled,
      removeCancelledTransfer: _chatFileQueueService.removeCancelledTransfer,
      saveMediaFile:
          ({
            required peerId,
            required messageId,
            required fileName,
            required sourcePath,
          }) => _storage.saveMediaFile(
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
          }) => _storage.saveMediaBytes(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            bytes: bytes,
          ),
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      findChat: (peerId) => chats[peerId],
      unreadMessagesCount: unreadMessagesCount,
      setBadgeCount:
          _onUnreadBadgeCountChanged ??
          NotificationService.instance.setBadgeCount,
      notifyMessageUpdated: _notifyMessageUpdated,
      transferStatusForError: _transferStatusForError,
    );
  }

  Future<void> cancelFileTransfer(String peerId, String messageId) async {
    await _chatFileQueueService.cancelFileTransfer(
      peerId,
      messageId,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      removeMessageWithMediaCleanup: _removeMessageWithMediaCleanup,
      refreshQueuedFileStatuses: _refreshQueuedFileStatuses,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> retryMessage(String peerId, String messageId) async {
    await ensureChatLoaded(peerId);
    final chat = _ensureChat(peerId);
    final index = chat.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) {
      return;
    }
    final message = chat.messages[index];
    if (message.incoming || message.status != MessageStatus.failed) {
      return;
    }

    if (message.kind == MessageKind.file) {
      await _retryFileMessage(chat, message);
      return;
    }

    final retry = ChatMessageCopy.copy(
      message,
      status: MessageStatus.sending,
      transferredBytes: null,
      sendProgress: null,
      transferStatus: null,
    );
    chat.messages[index] = retry;
    await _persistLoadedChat(peerId);
    _messageUpdatesController.add(peerId);
    if (chat.isGroup) {
      unawaited(_sendGroupMessageAsync(chat, retry));
    } else {
      unawaited(_sendMessageAsync(peerId, retry));
    }
  }

  Future<void> _retryFileMessage(Chat chat, Message message) async {
    await _chatOutboundService.retryFileMessage(
      chat,
      message,
      replaceMessage: _replaceMessage,
      rebuildReply: _rebuildReplyMessage,
      isFileQueuedOrActive: _isFileQueuedOrActive,
      enqueueFile: _chatFileQueueService.enqueue,
      refreshQueuedFileStatuses: _refreshQueuedFileStatuses,
      sendGroupFile: _sendGroupFileAsync,
      drainFileQueue: _drainFileQueue,
    );
  }

  Future<void> connect(String peerId) async {
    if (facade.peerId.compareTo(peerId) >= 0) {
      _setStatus(peerId, ChatConnectionStatus.connecting);
      return;
    }
    _setStatus(peerId, ChatConnectionStatus.connecting);
    try {
      await facade.connectToPeer(peerId);
      _setStatus(peerId, ChatConnectionStatus.connected);
    } catch (e) {
      _setStatus(peerId, ChatConnectionStatus.error, error: e.toString());
      rethrow;
    }
  }

  List<Chat> getChatsSorted() {
    final list = chats.values.toList();
    for (final chat in list) {
      chat.name = _chatContactsService.resolveChatName(
        chat.peerId,
        fallback: chat.name,
      );
    }

    list.sort((a, b) {
      final at = a.lastMessage?.timestamp ?? DateTime(0);
      final bt = b.lastMessage?.timestamp ?? DateTime(0);
      return bt.compareTo(at);
    });

    return list;
  }

  Future<void> clearManagedMediaReferencesInMemory() async {
    final peerIds = List<String>.from(chats.keys);
    for (final peerId in peerIds) {
      final chat = chats[peerId];
      if (chat == null) {
        continue;
      }

      if (_storage.isManagedMediaPath(chat.avatarPath)) {
        chat.avatarPath = null;
      }

      if (chat.messagesLoaded) {
        var changed = false;
        final updatedMessages = <Message>[];
        for (final message in chat.messages) {
          if (_storage.isManagedMediaPath(message.localFilePath)) {
            updatedMessages.add(
              ChatMessageCopy.copy(message, localFilePath: null),
            );
            changed = true;
          } else {
            updatedMessages.add(message);
          }
        }
        if (changed) {
          chat.messages = updatedMessages;
          await _persistLoadedChat(peerId);
        } else {
          await _persistChatSummary(chat);
        }
        continue;
      }

      await _persistChatSummary(chat);
    }
    _messageUpdatesController.add('');
  }

  void clearAllChatsFromMemory() {
    chats.clear();
    _messageUpdatesController.add('');
  }

  Chat openChat(String peerId, String name) {
    final chat = _ensureChat(peerId, fallbackName: name);
    _schedulePersistChatSummary(peerId);
    return chat;
  }

  Future<void> addMessage(String peerId, Message message) async {
    await ensureChatLoaded(peerId);
    final chat = _ensureChat(peerId);
    chat.messages.add(message);
    await _persistLoadedChat(peerId);
    _messageUpdatesController.add(peerId);
  }

  Future<void> deleteMessage(String peerId, String messageId) async {
    final messages = chats[peerId]?.messagesLoaded == true
        ? chats[peerId]!.messages
        : await _chatRepository.readStoredMessages(peerId);
    Message? match;
    for (final message in messages) {
      if (message.id == messageId) {
        match = message;
        break;
      }
    }
    await _deleteManagedMediaForMessage(match);
    await _removeMessage(peerId, messageId);
    _syncBadgeCount();
    _messageUpdatesController.add(peerId);
  }

  Future<void> deleteChat(String peerId) async {
    final loadedChat = chats[peerId];
    final isGroupChat =
        loadedChat?.isGroup == true || Chat.isGroupLikePeerId(peerId);
    final canDeleteForEveryone =
        isGroupChat &&
        loadedChat != null &&
        _knownGroupOwnerPeerId(peerId) == facade.peerId;
    if (canDeleteForEveryone) {
      await _broadcastGroupChatDelete(loadedChat);
    } else if (isGroupChat && loadedChat != null) {
      await _sendGroupLeaveBeforeLocalDelete(loadedChat);
    }
    await _deleteChatLocal(
      peerId,
      rememberDeletedGroup: isGroupChat,
      deletedByPeerId: facade.peerId,
    );
  }

  Future<void> _deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup = false,
    String? deletedByPeerId,
  }) async {
    final loadedChat = chats[peerId];
    final isGroupChat = _chatSummaryService.isKnownGroupChat(
      peerId,
      loadedChat: loadedChat,
    );
    final storedMessages = loadedChat?.messagesLoaded == true
        ? List<Message>.from(loadedChat!.messages)
        : await _chatRepository.readStoredMessages(peerId);

    for (final message in storedMessages) {
      await _storage.deleteMediaFile(message.localFilePath);
    }
    await _storage.deletePeerMediaDirectory(peerId);
    await _storage.deleteChatMessages(peerId);
    await _storage.deleteChatSummaryMap(peerId);
    await _groupKeyService.deleteGroupKeys(peerId);
    if (rememberDeletedGroup && isGroupChat) {
      await _rememberDeletedGroup(
        peerId,
        deletedByPeerId: deletedByPeerId ?? facade.peerId,
        chat: loadedChat,
      );
    } else {
      await _chatSummaryService.removeGroupMeta(peerId);
    }

    chats.remove(peerId);
    _chatFileQueueService.removeQueuedItemsForPeer(peerId, storedMessages);

    _syncBadgeCount();
    await _runGroupKeyGc();
    _messageUpdatesController.add(peerId);
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
    await _replaceMessage(peerId, messageId, (current) {
      var progress = current.sendProgress;
      var transferStatus = current.transferStatus;
      if (status == MessageStatus.sent) {
        progress = 1.0;
        transferStatus = 'Отправлено';
      } else if (status == MessageStatus.failed) {
        progress = 0;
        transferStatus = current.transferStatus == 'Отменено'
            ? 'Отменено'
            : _preserveFailedTransferStatus(current.transferStatus);
      }
      return ChatMessageCopy.copy(
        current,
        status: status,
        sendProgress: progress,
        transferStatus: transferStatus,
      );
    });
    _syncBadgeCount();
    _messageUpdatesController.add(peerId);
  }

  String _preserveFailedTransferStatus(String? currentStatus) {
    final normalized = (currentStatus ?? '').trim();
    if (normalized.isEmpty ||
        normalized == 'Подготовка' ||
        normalized == 'Загрузка в relay' ||
        normalized == 'Ожидает отправки' ||
        normalized == 'Отправлено') {
      return 'Ошибка отправки';
    }
    return normalized;
  }

  String _transferStatusForError(Object error, {required String fallback}) {
    if (error is RelayUnavailableException) {
      return error.isNotConfigured
          ? _incomingRelayNotConfiguredStatus
          : _incomingRelayUnavailableStatus;
    }
    return fallback;
  }

  Future<void> _updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    await _chatFileQueueService.updateFileProgress(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
      applyFileProgressUpdate: _applyFileProgressUpdate,
    );
  }

  void _clearProgressUpdate(String peerId, String messageId) {
    _chatFileQueueService.clearProgressUpdate(peerId, messageId);
  }

  String _incomingMediaKey(String peerId, String messageId) =>
      RelayMediaRetryCoordinator.mediaKey(peerId, messageId);

  Future<void> _resumeInterruptedIncomingMediaQueue({
    required String reason,
  }) async {
    var resumed = 0;
    for (final chat in chats.values) {
      resumed += await _resumeInterruptedIncomingMediaForChat(
        chat,
        reason: reason,
      );
    }
    if (resumed > 0) {
      AppFileLogger.log(
        '[chat_media] incoming resume reason=$reason count=$resumed',
      );
    }
  }

  Future<int> _resumeInterruptedIncomingMediaForChat(
    Chat chat, {
    required String reason,
  }) async {
    if (!chat.messagesLoaded) {
      return 0;
    }
    var resumed = 0;
    for (final message in chat.messages.toList(growable: false)) {
      if (!_shouldResumeIncomingMedia(message)) {
        continue;
      }
      final isGroup = (message.transferId ?? '').startsWith('grpblob:');
      AppFileLogger.log(
        '[chat_media] incoming resume reason=$reason peer=${message.peerId} '
        'messageId=${message.id} group=$isGroup',
      );
      _restoreMediaInBackground(message, isGroup: isGroup, force: true);
      resumed += 1;
    }
    return resumed;
  }

  Future<void> _applyFileProgressUpdate(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    final chat = chats[peerId];
    if (chat == null || !chat.messagesLoaded) {
      return;
    }

    for (var i = 0; i < chat.messages.length; i++) {
      final msg = chat.messages[i];
      if (msg.id != messageId) {
        continue;
      }
      final relayTransferId = (msg.transferId ?? '').trim();
      final isIncomingRelayMedia =
          msg.incoming &&
          msg.kind == MessageKind.file &&
          (relayTransferId.startsWith('dirblob:') ||
              relayTransferId.startsWith('grpblob:'));
      if (isIncomingRelayMedia &&
          ((msg.localFilePath?.isNotEmpty ?? false) ||
              msg.transferStatus == _incomingRelayErrorStatus)) {
        return;
      }
      final nextProgress = (totalBytes == null || totalBytes <= 0)
          ? null
          : (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();
      if (isIncomingRelayMedia &&
          _isStaleIncomingRelayProgress(
            currentStatus: msg.transferStatus,
            currentProgress: msg.transferProgress,
            nextStatus: statusText,
            nextProgress: nextProgress,
          )) {
        return;
      }
      final changed =
          msg.transferredBytes != sentBytes ||
          msg.sendProgress != nextProgress ||
          msg.transferStatus != statusText;
      if (!changed) {
        return;
      }
      chat.messages[i] = ChatMessageCopy.copy(
        msg,
        transferredBytes: sentBytes,
        sendProgress: nextProgress,
        transferStatus: statusText,
      );
      _messageUpdatesController.add(peerId);
      return;
    }
  }

  void _refreshQueuedFileStatuses() {
    _chatFileQueueService.refreshQueuedFileStatuses(
      chats: chats,
      schedulePersistLoadedChat: _schedulePersistLoadedChat,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
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
    return _mediaRestoreService.restoreIncomingRelayMediaOnce(
      message,
      isGroup: true,
      restoreGroup: () => _restoreGroupBlobMediaFromRelay(message),
      restoreDirect: () => _restoreDirectBlobMediaFromRelay(message),
    );
  }

  Future<String?> _restoreGroupBlobMediaFromRelay(Message message) async {
    final route = _outboundCodec.parseGroupBlobTransferId(message.transferId);
    if (route == null) {
      return null;
    }

    return _restoreMediaFromRelay(
      peerId: route.groupId,
      messageId: route.messageId,
      blobId: route.blobId,
      fileName: message.fileName,
      downloadBlob: (onProgress) =>
          facade.downloadBlob(route.blobId, onProgress: onProgress),
      transformStatus: _incomingRelayDecryptStatus,
      transformPayload: (blob) {
        return _decodeGroupBlobBytes(
          groupId: route.groupId,
          encryptedBytes: blob.payload,
        );
      },
    );
  }

  Future<String?> restoreDirectBlobMedia(Message message) {
    return _mediaRestoreService.restoreIncomingRelayMediaOnce(
      message,
      isGroup: false,
      restoreGroup: () => _restoreGroupBlobMediaFromRelay(message),
      restoreDirect: () => _restoreDirectBlobMediaFromRelay(message),
    );
  }

  Future<String?> _restoreDirectBlobMediaFromRelay(Message message) async {
    final route = _outboundCodec.parseDirectBlobTransferId(message.transferId);
    if (route == null) {
      return null;
    }

    return _restoreMediaFromRelay(
      peerId: route.peerId,
      messageId: route.messageId,
      blobId: route.blobId,
      fileName: message.fileName,
      downloadBlob: (onProgress) =>
          facade.downloadBlob(route.blobId, onProgress: onProgress),
    );
  }

  void _restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
  }) {
    _mediaRestoreService.restoreMediaInBackground(
      message,
      isGroup: isGroup,
      force: force,
      restoreInBackground:
          (message, {required bool isGroup, bool force = false}) {
            final future = isGroup
                ? restoreGroupBlobMedia(message)
                : restoreDirectBlobMedia(message);
            unawaited(future);
          },
    );
  }

  bool isIncomingRelayMediaRestoreInProgress(Message message) {
    return _mediaRestoreService.isIncomingRelayMediaRestoreInProgress(message);
  }

  bool isIncomingRelayMediaRestoreFailed(Message message) {
    return _mediaRestoreService.isIncomingRelayMediaRestoreFailed(message);
  }

  bool isInitialUnreadAnchor(Message message) {
    if (!message.incoming || message.isRead) {
      return false;
    }
    return !_isFailedIncomingMediaPlaceholder(message);
  }

  bool _isFailedIncomingMediaPlaceholder(Message message) {
    if (!message.incoming || message.kind != MessageKind.file) {
      return false;
    }
    if (message.localFilePath?.trim().isNotEmpty == true) {
      return false;
    }
    return isIncomingRelayMediaRestoreFailed(message);
  }

  Future<String?> _restoreMediaFromRelay({
    required String peerId,
    required String messageId,
    required String blobId,
    required String? fileName,
    required RelayMediaDownloadOperation downloadBlob,
    Future<Uint8List> Function(RelayBlobDownload blob)? transformPayload,
    String? transformStatus,
  }) {
    return _mediaRestoreService.restoreMediaFromRelay(
      peerId: peerId,
      messageId: messageId,
      blobId: blobId,
      fileName: fileName,
      downloadBlob: downloadBlob,
      restoreInBackground:
          (message, {required bool isGroup, bool force = false}) {
            _restoreMediaInBackground(message, isGroup: isGroup, force: true);
          },
      transformPayload: transformPayload,
      transformStatus: transformStatus,
    );
  }

  bool _shouldAutoRestoreIncomingMedia(Message message) {
    return _mediaRestoreService.shouldResumeIncomingMedia(message) ||
        ((message.transferStatus ?? '').trim().isEmpty &&
            _mediaRestoreService.isIncomingRelayMediaPlaceholder(message));
  }

  bool _shouldResumeIncomingMedia(Message message) {
    return _mediaRestoreService.shouldResumeIncomingMedia(message);
  }

  bool _isStaleIncomingRelayProgress({
    required String? currentStatus,
    required double? currentProgress,
    required String nextStatus,
    required double? nextProgress,
  }) {
    return _mediaRestoreService.isStaleIncomingRelayProgress(
      currentStatus: currentStatus,
      currentProgress: currentProgress,
      nextStatus: nextStatus,
      nextProgress: nextProgress,
    );
  }

  bool _hasNetworkConnectivity(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<Uint8List> _decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    return _groupMessageCryptoService.decodeGroupBlobBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
  }

  Future<String?> _restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  }) async {
    try {
      final blob = await facade.downloadBlob(blobId);
      if (blob.isNotFound) {
        return fallback;
      }
      final bytes = await _decodeGroupBlobBytes(
        groupId: groupId,
        encryptedBytes: blob.payload,
      );
      return utf8.decode(bytes);
    } catch (_) {
      return fallback;
    }
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
    await _messageEventRegistration?.cancel();
    await _connectivitySubscription?.cancel();
    await _peerConnectedSub?.cancel();
    await _peerDisconnectedSub?.cancel();
    await _connectionStatusController.close();
    await _messageUpdatesController.close();
    await _newMessageNotificationController.close();
  }

  Stream<List<String>> get discoveredPeersStream =>
      facade.discoveredPeersStream;

  Future<void> startCall(String peerId) => facade.startCall(peerId);
}
