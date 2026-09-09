// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:collection';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/security/group_key_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_parts.dart';
import 'package:peerlink/features/chat/application/chat_controller_media.dart';
import 'package:peerlink/features/chat/application/chat_file_transfer_coordinator.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';
import 'package:peerlink/features/chat/application/chat_summary_service.dart';

class ChatHistoryLoadCoordinator {
  ChatHistoryLoadCoordinator({
    required StorageService storage,
    required ChatRuntimeApi facade,
    required GroupKeyService groupKeyService,
    required ChatRepository chatRepository,
    required ChatSummaryStore chatSummaryStore,
    required ChatSummaryService chatSummaryService,
    required ChatFileTransferCoordinator fileTransferCoordinator,
    required Map<String, Chat> chats,
    required Chat Function(String peerId) ensureChat,
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
    required Future<String?> Function(Message message) ensureThumbnail,
  }) : _storage = storage,
       _facade = facade,
       _groupKeyService = groupKeyService,
       _chatRepository = chatRepository,
       _chatSummaryStore = chatSummaryStore,
       _chatSummaryService = chatSummaryService,
       _fileTransferCoordinator = fileTransferCoordinator,
       _chats = chats,
       _ensureChat = ensureChat,
       _contactNameFor = contactNameFor,
       _persistChatSummary = persistChatSummary,
       _deleteManagedMediaForMessage = deleteManagedMediaForMessage,
       _syncBadgeCount = syncBadgeCount,
       _notifyMessageUpdated = notifyMessageUpdated,
       _resumeInterruptedIncomingMediaForChat =
           resumeInterruptedIncomingMediaForChat,
       _resumePendingOutgoingRelayMedia = resumePendingOutgoingRelayMedia,
       _ensureThumbnail = ensureThumbnail;

  static const int initialLoadLimit = 50;
  static const int paginationLimit = 50;
  static const int _maxThumbnailBackfillQueue = 120;
  static const int _maxConcurrentThumbnailBackfills = 1;

  final StorageService _storage;
  final ChatRuntimeApi _facade;
  final GroupKeyService _groupKeyService;
  final ChatRepository _chatRepository;
  final ChatSummaryStore _chatSummaryStore;
  final ChatSummaryService _chatSummaryService;
  final ChatFileTransferCoordinator _fileTransferCoordinator;
  final Map<String, Chat> _chats;
  final Chat Function(String peerId) _ensureChat;
  final String Function(String peerId, {String? fallback}) _contactNameFor;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final Future<void> Function(Message? message) _deleteManagedMediaForMessage;
  final void Function() _syncBadgeCount;
  final void Function(String peerId) _notifyMessageUpdated;
  final Future<void> Function(Chat chat, {required String reason})
  _resumeInterruptedIncomingMediaForChat;
  final Future<void> Function({required String reason})
  _resumePendingOutgoingRelayMedia;
  final Future<String?> Function(Message message) _ensureThumbnail;
  final Queue<_ThumbnailBackfillItem> _thumbnailBackfillQueue =
      Queue<_ThumbnailBackfillItem>();
  final Set<String> _queuedThumbnailBackfills = <String>{};
  int _activeThumbnailBackfills = 0;

  Future<void> initializeGroupKeys() => _groupKeyService.initialize();

  Future<void> loadChats() async {
    _chatSummaryService.loadGroupMetaFromSettings();
    final summaries = await _chatSummaryStore.loadAll();
    for (final raw in summaries) {
      try {
        final chat = Chat.fromJson(Map<String, dynamic>.from(raw));
        if (_chatSummaryService.isGroupDeleted(chat.peerId)) {
          await _storage.deletePeerMediaDirectory(chat.peerId);
          await _chatSummaryStore.delete(chat.peerId);
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

  Future<void> ensureChatLoaded(String peerId) async {
    final chat = _ensureChat(peerId);
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
    _scheduleMissingThumbnailBackfill(chat, stored);
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
    _scheduleMissingThumbnailBackfill(chat, olderMessages);
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

  Future<void> unloadChatMessages(String peerId) async {
    final chat = _chats[peerId];
    if (chat == null || !chat.messagesLoaded) {
      developer.log(
        '[chat] unload skipped peer=$peerId reason=not-loaded',
        name: 'chat',
      );
      return;
    }
    final loadedCount = chat.messages.length;
    await _chatRepository.persistLoadedChat(chat);
    chat.messages = <Message>[];
    chat.messagesLoaded = false;
    chat.hasMoreMessages = true;
    developer.log(
      '[chat] unload success peer=$peerId released=$loadedCount '
      'preview=${chat.previewMessage?.id}',
      name: 'chat',
    );
  }

  void schedulePersistLoadedChat(String peerId) {
    unawaited(persistLoadedChat(peerId));
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _chatRepository.messageOffsetFromNewest(peerId, messageId);
  }

  Future<String?> firstInitialUnreadMessageId(String peerId) {
    return _chatRepository.firstInitialUnreadMessageId(peerId);
  }

  Future<void> runGroupKeyGc() async {
    final activeGroupIds = _chats.values
        .where((chat) => chat.isGroup || Chat.isGroupLikePeerId(chat.peerId))
        .map((chat) => chat.peerId)
        .toSet();
    activeGroupIds.addAll(_chatSummaryService.knownGroupIds());
    await _groupKeyService.runGc(activeGroupIds: activeGroupIds);
  }

  void _scheduleMissingThumbnailBackfill(Chat chat, List<Message> messages) {
    var candidates = 0;
    var videos = 0;
    var images = 0;
    var missingLocal = 0;
    var alreadyQueued = 0;
    var droppedCount = 0;
    for (final message in messages) {
      if (message.kind == MessageKind.file && _isThumbnailCandidate(message)) {
        candidates += 1;
        if (message.isVideo ||
            (message.mimeType?.trim().toLowerCase().startsWith('video/') ??
                false)) {
          videos += 1;
        } else if (message.isImage ||
            (message.mimeType?.trim().toLowerCase().startsWith('image/') ??
                false)) {
          images += 1;
        }
        final localPath = message.localFilePath?.trim();
        if (localPath == null || localPath.isEmpty) {
          missingLocal += 1;
        }
      }
      if (!_needsThumbnailBackfill(message)) {
        continue;
      }
      final key = '${chat.peerId}|${message.id}';
      if (!_queuedThumbnailBackfills.add(key)) {
        alreadyQueued += 1;
        continue;
      }
      _thumbnailBackfillQueue.add(
        _ThumbnailBackfillItem(peerId: chat.peerId, message: message),
      );
      while (_thumbnailBackfillQueue.length > _maxThumbnailBackfillQueue) {
        final dropped = _thumbnailBackfillQueue.removeFirst();
        droppedCount += 1;
        _queuedThumbnailBackfills.remove(
          '${dropped.peerId}|${dropped.message.id}',
        );
      }
    }
    developer.log(
      '[chat_media] thumbnail backfill schedule peer=${chat.peerId} '
      'batch=${messages.length} candidates=$candidates videos=$videos '
      'images=$images missingLocal=$missingLocal alreadyQueued=$alreadyQueued '
      'dropped=$droppedCount queue=${_thumbnailBackfillQueue.length} '
      'active=$_activeThumbnailBackfills',
      name: 'chat',
      level: 900,
    );
    _pumpThumbnailBackfillQueue();
  }

  bool _needsThumbnailBackfill(Message message) {
    if (message.kind != MessageKind.file || !_isThumbnailCandidate(message)) {
      return false;
    }
    final localPath = message.localFilePath?.trim();
    if (localPath == null || localPath.isEmpty) {
      return false;
    }
    return true;
  }

  bool _isThumbnailCandidate(Message message) {
    final mime = message.mimeType?.trim().toLowerCase();
    if (mime != null && mime.startsWith('image/')) {
      return true;
    }
    return message.isImage;
  }

  void _pumpThumbnailBackfillQueue() {
    while (_activeThumbnailBackfills < _maxConcurrentThumbnailBackfills &&
        _thumbnailBackfillQueue.isNotEmpty) {
      final item = _thumbnailBackfillQueue.removeFirst();
      _activeThumbnailBackfills += 1;
      unawaited(_runThumbnailBackfill(item));
    }
  }

  Future<void> _runThumbnailBackfill(_ThumbnailBackfillItem item) async {
    final key = '${item.peerId}|${item.message.id}';
    final stopwatch = Stopwatch()..start();
    try {
      developer.log(
        '[chat_media] thumbnail backfill start peer=${item.peerId} '
        'messageId=${item.message.id} file=${item.message.fileName ?? ""} '
        'mime=${item.message.mimeType ?? ""} '
        'local=${item.message.localFilePath ?? ""} '
        'thumb=${item.message.thumbnailPath ?? ""} '
        'queue=${_thumbnailBackfillQueue.length} active=$_activeThumbnailBackfills',
        name: 'chat',
        level: 900,
      );
      final thumbnailPath = await _ensureThumbnail(item.message);
      if (thumbnailPath == null || thumbnailPath.isEmpty) {
        developer.log(
          '[chat_media] thumbnail backfill no-result peer=${item.peerId} '
          'messageId=${item.message.id} '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
          name: 'chat',
          level: 900,
        );
        return;
      }
      if (thumbnailPath == item.message.thumbnailPath) {
        developer.log(
          '[chat_media] thumbnail backfill same-path peer=${item.peerId} '
          'messageId=${item.message.id} path=$thumbnailPath '
          'elapsedMs=${stopwatch.elapsedMilliseconds}',
          name: 'chat',
          level: 900,
        );
        return;
      }
      await _chatRepository.replaceMessage(
        item.peerId,
        item.message.id,
        (current) =>
            ChatMessageCopy.copy(current, thumbnailPath: thumbnailPath),
      );
      _notifyMessageUpdated(item.peerId);
      developer.log(
        '[chat_media] thumbnail backfill updated peer=${item.peerId} '
        'messageId=${item.message.id} path=$thumbnailPath '
        'elapsedMs=${stopwatch.elapsedMilliseconds}',
        name: 'chat',
        level: 900,
      );
    } catch (error) {
      developer.log(
        '[chat_media] thumbnail backfill failed peer=${item.peerId} '
        'messageId=${item.message.id} error=$error',
        name: 'chat',
      );
    } finally {
      _queuedThumbnailBackfills.remove(key);
      _activeThumbnailBackfills -= 1;
      _pumpThumbnailBackfillQueue();
    }
  }
}

class _ThumbnailBackfillItem {
  final String peerId;
  final Message message;

  const _ThumbnailBackfillItem({required this.peerId, required this.message});
}
