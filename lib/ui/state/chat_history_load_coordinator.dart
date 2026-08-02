import 'dart:async';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/node/node_facade.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_media.dart';
import 'chat_file_transfer_coordinator.dart';
import 'chat_repository.dart';
import 'chat_summary_service.dart';

class ChatHistoryLoadCoordinator {
  const ChatHistoryLoadCoordinator({
    required StorageService storage,
    required NodeFacade facade,
    required GroupKeyService groupKeyService,
    required ChatRepository chatRepository,
    required ChatSummaryService chatSummaryService,
    required ChatFileTransferCoordinator fileTransferCoordinator,
    required Map<String, Chat> chats,
    required String Function(String peerId, {String? fallback}) contactNameFor,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(Message? message)
    deleteManagedMediaForMessage,
    required void Function() syncBadgeCount,
    required void Function(String peerId) notifyMessageUpdated,
    required Future<void> Function(Chat chat, {required String reason})
    resumeInterruptedIncomingMediaForChat,
    required Future<void> Function({required String reason})
    resumePendingOutgoingRelayMedia,
  }) : _storage = storage,
       _facade = facade,
       _groupKeyService = groupKeyService,
       _chatRepository = chatRepository,
       _chatSummaryService = chatSummaryService,
       _fileTransferCoordinator = fileTransferCoordinator,
       _chats = chats,
       _contactNameFor = contactNameFor,
       _persistChatSummary = persistChatSummary,
       _deleteManagedMediaForMessage = deleteManagedMediaForMessage,
       _syncBadgeCount = syncBadgeCount,
       _notifyMessageUpdated = notifyMessageUpdated,
       _resumeInterruptedIncomingMediaForChat =
           resumeInterruptedIncomingMediaForChat,
       _resumePendingOutgoingRelayMedia = resumePendingOutgoingRelayMedia;

  static const int initialLoadLimit = 50;
  static const int paginationLimit = 50;

  final StorageService _storage;
  final NodeFacade _facade;
  final GroupKeyService _groupKeyService;
  final ChatRepository _chatRepository;
  final ChatSummaryService _chatSummaryService;
  final ChatFileTransferCoordinator _fileTransferCoordinator;
  final Map<String, Chat> _chats;
  final String Function(String peerId, {String? fallback}) _contactNameFor;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final Future<void> Function(Message? message) _deleteManagedMediaForMessage;
  final void Function() _syncBadgeCount;
  final void Function(String peerId) _notifyMessageUpdated;
  final Future<void> Function(Chat chat, {required String reason})
  _resumeInterruptedIncomingMediaForChat;
  final Future<void> Function({required String reason})
  _resumePendingOutgoingRelayMedia;

  Future<void> loadChats() async {
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
        _chats[chat.peerId] = chat;
      } catch (_) {
        // Ignore invalid persisted chat entries.
      }
    }
    await runGroupKeyGc();
    _syncBadgeCount();
    _notifyMessageUpdated('');
    unawaited(_facade.pollRelay());
    unawaited(_resumePendingOutgoingRelayMedia(reason: 'startup'));
  }

  Future<void> ensureChatLoaded(
    String peerId, {
    required Chat Function(String peerId) ensureChat,
  }) async {
    final chat = ensureChat(peerId);
    if (chat.messagesLoaded) {
      return;
    }

    final stored = await _chatRepository.loadInitialMessages(
      peerId,
      initialLoadLimit,
    );
    await processLoadedMessages(peerId, stored);

    chat.messages = stored;
    chat.messagesLoaded = true;
    chat.hasMoreMessages = await _chatRepository.hasMoreMessages(
      peerId,
      stored.length,
    );
    _chatRepository.refreshSummaryFromMessages(chat, stored);
    _fileTransferCoordinator.recoverPendingTransfersForChat(chat);
    developer.log(
      '[chat] ensureChatLoaded peer=$peerId initialLoaded=${stored.length} '
      'hasMore=${chat.hasMoreMessages}',
      name: 'chat',
    );

    _notifyMessageUpdated(peerId);
    unawaited(
      _resumeInterruptedIncomingMediaForChat(chat, reason: 'chat-load'),
    );
  }

  Future<void> processLoadedMessages(String peerId, List<Message> stored) {
    return ChatControllerMedia.processLoadedMessages(
      storage: _storage,
      peerId: peerId,
      stored: stored,
      writeStoredMessages: _chatRepository.writeStoredMessages,
      upsertStoredMessages: _chatRepository.upsertStoredMessages,
      deleteStoredMessagesByIds: _chatRepository.deleteStoredMessagesByIds,
      persistChatSummary: (id) async {
        final chat = _chats[id];
        if (chat != null) {
          await _persistChatSummary(chat);
        }
      },
      deleteManagedMediaForMessage: _deleteManagedMediaForMessage,
    );
  }

  Future<bool> loadMoreMessages(String peerId) async {
    final chat = _chats[peerId];
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
      'pageSize=$paginationLimit',
      name: 'chat',
    );
    final olderMessages = await _chatRepository.readOlderMessages(
      peerId,
      currentCount,
      paginationLimit,
    );

    if (olderMessages.isEmpty) {
      chat.hasMoreMessages = false;
      developer.log(
        '[chat] loadMore empty peer=$peerId currentCount=$currentCount',
        name: 'chat',
      );
      return false;
    }

    await processLoadedMessages(peerId, olderMessages);
    chat.messages.insertAll(0, olderMessages);
    chat.hasMoreMessages = olderMessages.length == paginationLimit;
    developer.log(
      '[chat] loadMore success peer=$peerId fetched=${olderMessages.length} '
      'loadedNow=${chat.messages.length} hasMoreNow=${chat.hasMoreMessages}',
      name: 'chat',
    );

    _notifyMessageUpdated(peerId);
    unawaited(
      _resumeInterruptedIncomingMediaForChat(chat, reason: 'load-more'),
    );
    return true;
  }

  Future<void> persistLoadedChat(String peerId) async {
    final chat = _chats[peerId];
    if (chat == null) {
      return;
    }
    await _chatRepository.persistLoadedChat(chat);
  }

  void schedulePersistLoadedChat(String peerId) {
    unawaited(persistLoadedChat(peerId));
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _chatRepository.messageOffsetFromNewest(peerId, messageId);
  }

  Future<void> runGroupKeyGc() async {
    final activeGroupIds = _chats.values
        .where((chat) => chat.isGroup || Chat.isGroupLikePeerId(chat.peerId))
        .map((chat) => chat.peerId)
        .toSet();
    activeGroupIds.addAll(_chatSummaryService.knownGroupIds());
    await _groupKeyService.runGc(activeGroupIds: activeGroupIds);
  }
}
