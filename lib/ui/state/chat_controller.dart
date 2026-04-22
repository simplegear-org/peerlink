import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/messaging/chat_service.dart';
import '../../core/messaging/reliable_messaging_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/notification/notification_service.dart';
import '../../core/relay/relay_models.dart';
import '../../core/runtime/contact_name_resolver.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import '../models/contact.dart';
import '../models/message.dart';
import 'avatar_service.dart';
import 'chat_controller_media.dart';
import 'chat_controller_parts.dart';


enum ChatConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

const List<int> _groupMediaCipherMagicV2 = <int>[0x50, 0x4C, 0x47, 0x32]; // PLG2

class _PendingProgressUpdate {
  int sentBytes;
  int? totalBytes;
  String statusText;
  DateTime lastAppliedAt;
  Timer? timer;

  _PendingProgressUpdate({
    required this.sentBytes,
    required this.totalBytes,
    required this.statusText,
    required this.lastAppliedAt,
  });
}

typedef _RelayBlobProgressCallback = void Function({
  required int receivedBytes,
  required int totalBytes,
  required String status,
});

typedef _RelayBlobDownloadOperation = Future<RelayBlobDownload> Function(
  _RelayBlobProgressCallback onProgress,
);

class _FileTransferCancelledException implements Exception {
  const _FileTransferCancelledException();

  @override
  String toString() => 'File transfer cancelled';
}

class _IncomingBlobRefPayload {
  final String targetKind;
  final String chatPeerId;
  final String messageId;
  final String contentKind;
  final String blobId;
  final String? fileName;
  final String? mimeType;
  final int? fileSizeBytes;
  final String? textPreview;
  final String? groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final Map<String, dynamic> raw;

  const _IncomingBlobRefPayload({
    required this.targetKind,
    required this.chatPeerId,
    required this.messageId,
    required this.contentKind,
    required this.blobId,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.textPreview,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.raw,
  });

  bool get isGroup => targetKind == 'group';
  bool get isDirect => targetKind == 'direct';
}

class _IncomingGroupInvitePayload {
  final String groupId;
  final String groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final Map<String, dynamic> raw;

  const _IncomingGroupInvitePayload({
    required this.groupId,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.raw,
  });
}

class _IncomingGroupMessagePayload {
  final String groupId;
  final String groupMessageId;
  final String text;
  final String groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final Map<String, dynamic> raw;

  const _IncomingGroupMessagePayload({
    required this.groupId,
    required this.groupMessageId,
    required this.text,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.raw,
  });
}

class _IncomingGroupDeletePayload {
  final String groupId;
  final String groupMessageId;
  final Map<String, dynamic> raw;

  const _IncomingGroupDeletePayload({
    required this.groupId,
    required this.groupMessageId,
    required this.raw,
  });
}

class _IncomingGroupMembersPayload {
  final String groupId;
  final String groupName;
  final String ownerPeerId;
  final String action;
  final List<String> memberPeerIds;
  final List<String> changedPeerIds;
  final String? avatarBlobId;
  final String? avatarMimeType;
  final int? avatarUpdatedAtMs;
  final Map<String, dynamic> raw;

  const _IncomingGroupMembersPayload({
    required this.groupId,
    required this.groupName,
    required this.ownerPeerId,
    required this.action,
    required this.memberPeerIds,
    required this.changedPeerIds,
    required this.avatarBlobId,
    required this.avatarMimeType,
    required this.avatarUpdatedAtMs,
    required this.raw,
  });
}

class _IncomingGroupKeyPayload {
  final String groupId;
  final String groupKey;
  final int keyVersion;
  final Map<String, dynamic> raw;

  const _IncomingGroupKeyPayload({
    required this.groupId,
    required this.groupKey,
    required this.keyVersion,
    required this.raw,
  });
}

class _IncomingGroupSecurePayload {
  final String groupId;
  final Map<String, dynamic> raw;

  const _IncomingGroupSecurePayload({
    required this.groupId,
    required this.raw,
  });
}

sealed class _IncomingChatDispatch {
  const _IncomingChatDispatch();
}

final class _IncomingDeleteDispatch extends _IncomingChatDispatch {
  const _IncomingDeleteDispatch();
}

final class _IncomingProfileAvatarDispatch extends _IncomingChatDispatch {
  const _IncomingProfileAvatarDispatch();
}

final class _IncomingProfileAvatarRemoveDispatch extends _IncomingChatDispatch {
  const _IncomingProfileAvatarRemoveDispatch();
}

final class _IncomingProfileAvatarQueryDispatch extends _IncomingChatDispatch {
  const _IncomingProfileAvatarQueryDispatch();
}

final class _IncomingGroupInviteDispatch extends _IncomingChatDispatch {
  final _IncomingGroupInvitePayload payload;

  const _IncomingGroupInviteDispatch(this.payload);
}

final class _IncomingGroupKeyDispatch extends _IncomingChatDispatch {
  final _IncomingGroupKeyPayload payload;

  const _IncomingGroupKeyDispatch(this.payload);
}

final class _IncomingGroupDeleteDispatch extends _IncomingChatDispatch {
  final _IncomingGroupDeletePayload payload;

  const _IncomingGroupDeleteDispatch(this.payload);
}

final class _IncomingGroupMembersDispatch extends _IncomingChatDispatch {
  final _IncomingGroupMembersPayload payload;

  const _IncomingGroupMembersDispatch(this.payload);
}

final class _IncomingGroupMessageDispatch extends _IncomingChatDispatch {
  final _IncomingGroupMessagePayload payload;

  const _IncomingGroupMessageDispatch(this.payload);
}

final class _IncomingGroupSecureDispatch extends _IncomingChatDispatch {
  final _IncomingGroupSecurePayload payload;

  const _IncomingGroupSecureDispatch(this.payload);
}

final class _IncomingDirectBlobRefDispatch extends _IncomingChatDispatch {
  final _IncomingBlobRefPayload blobRef;

  const _IncomingDirectBlobRefDispatch(this.blobRef);
}

final class _IncomingDisplayableDispatch extends _IncomingChatDispatch {
  const _IncomingDisplayableDispatch();
}

final class _IncomingIgnoredDispatch extends _IncomingChatDispatch {
  const _IncomingIgnoredDispatch();
}

class ChatController {
  static int _lastGeneratedMessageId = 0;
  static const String _groupInvitePrefix = '__peerlink_group_invite_v1__:';
  static const String _groupMessagePrefix = '__peerlink_group_msg_v1__:';
  static const String _groupDeletePrefix = '__peerlink_group_delete_v1__:';
  static const String _groupMembersPrefix = '__peerlink_group_members_v1__:';
  static const String _groupKeyPrefix = '__peerlink_group_key_v1__:';
  static const String _groupSecurePrefix = '__peerlink_group_secure_v1__:';
  static const String _groupBlobRefPrefix = '__peerlink_group_blob_ref_v1__:';
  static const String _directBlobRefPrefix = '__peerlink_direct_blob_ref_v1__:';
  static const int _incomingMediaRetryMaxAttempts = 3;
  static const Duration _incomingMediaRetryDelay = Duration(seconds: 4);
  static const String _groupMetaStorageKey = 'state.v1';
  static const String _legacyGroupMetaStorageKey = 'peerlink.group_meta.v1';
  final NodeFacade facade;
  final StorageService _storage;
  final SecureStorageBox _contactsBox;
  final SecureStorageBox _settingsBox;
  final SecureStorageBox _groupMetaBox;
  final GroupKeyService _groupKeyService;
  final Cipher _groupCipher = AesGcm.with256bits();
  final AvatarService _avatarService;
  final Map<String, Map<String, dynamic>> _groupMetaByGroupId =
      <String, Map<String, dynamic>>{};

  final Map<String, Chat> chats = {};
  final Map<String, ChatConnectionStatus> _connectionStatus = {};
  final Map<String, String?> _connectionErrors = {};
  final _connectionStatusController = StreamController<String>.broadcast();
  final _messageUpdatesController = StreamController<String>.broadcast();
  final _newMessageNotificationController =
      StreamController<ChatMessage>.broadcast();
  StreamSubscription<String>? _peerConnectedSub;
  StreamSubscription<String>? _peerDisconnectedSub;
  final Queue<QueuedFileTransfer> _fileSendQueue = Queue<QueuedFileTransfer>();
  final Map<String, _PendingProgressUpdate> _pendingProgressUpdates =
      <String, _PendingProgressUpdate>{};
  final Map<String, Timer> _incomingMediaRetryTimers = <String, Timer>{};
  final Map<String, int> _incomingMediaRetryAttempts = <String, int>{};
  bool _fileSendInFlight = false;
  final Set<String> _cancelledFileTransfers = {};
  String? _activeFileTransferId;
  static const Duration _progressThrottleInterval = Duration(milliseconds: 140);

  ChatController(
    this.facade, {
    required StorageService storage,
    required AvatarService avatarService,
  })  : _storage = storage,
        _avatarService = avatarService,
        _contactsBox = storage.getContacts(),
        _settingsBox = storage.getSettings(),
        _groupMetaBox = storage.getGroupMeta(),
        _groupKeyService = GroupKeyService.forSecureStorageBox(
          storage.getGroupKeys(),
        ) {
    unawaited(_loadChats());
    unawaited(_groupKeyService.initialize());
    NotificationService.instance.setBadgeCount(unreadMessagesCount());
    _listenMessages();
    _peerConnectedSub = facade.peerConnectedStream.listen((peerId) {
      _setStatus(peerId, ChatConnectionStatus.connected);
    });
    _peerDisconnectedSub = facade.peerDisconnectedStream.listen((peerId) {
      _setStatus(peerId, ChatConnectionStatus.disconnected);
    });
  }

  Future<void> _loadChats() async {
    _loadGroupMetaFromSettings();
    final summaries = await _storage.loadAllChatSummaries();
    for (final raw in summaries) {
      try {
        final chat = Chat.fromJson(Map<String, dynamic>.from(raw));
        _applyGroupMeta(chat);
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
    _messageUpdatesController.add('');
  }

  void _loadGroupMetaFromSettings() {
    _groupMetaByGroupId.clear();
    final raw = _groupMetaBox.get(_groupMetaStorageKey) ??
        _settingsBox.get(_legacyGroupMetaStorageKey);
    if (raw is! Map) {
      return;
    }
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.trim().isEmpty) {
        continue;
      }
      if (value is Map<String, dynamic>) {
        _groupMetaByGroupId[key] = Map<String, dynamic>.from(value);
      } else if (value is Map) {
        _groupMetaByGroupId[key] = Map<String, dynamic>.from(value);
      }
    }
  }

  Future<void> _persistGroupMetaToSettings() async {
    await _groupMetaBox.put(
      _groupMetaStorageKey,
      Map<String, dynamic>.from(_groupMetaByGroupId),
    );
  }

  void _applyGroupMeta(Chat chat) {
    final meta = _groupMetaByGroupId[chat.peerId];
    if (meta == null) {
      return;
    }
    final rawMembers = meta['memberPeerIds'];
    if (rawMembers is List) {
      final members = rawMembers
          .whereType<String>()
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(growable: false);
      if (members.isNotEmpty) {
        chat.memberPeerIds = members;
      }
    }
    final owner = (meta['ownerPeerId'] as String?)?.trim();
    if (owner != null && owner.isNotEmpty) {
      chat.ownerPeerId = owner;
    }
    final isGroup = meta['isGroup'] as bool?;
    if (isGroup == true) {
      chat.isGroup = true;
    }
    final groupName = (meta['name'] as String?)?.trim();
    if (groupName != null && groupName.isNotEmpty) {
      chat.name = groupName;
    }
    final avatarPath = (meta['avatarPath'] as String?)?.trim();
    if (avatarPath != null && avatarPath.isNotEmpty) {
      chat.avatarPath = avatarPath;
    }
  }

  Future<void> _runGroupKeyGc() async {
    final activeGroupIds = chats.values
        .where((chat) => chat.isGroup || Chat.isGroupLikePeerId(chat.peerId))
        .map((chat) => chat.peerId)
        .toSet();
    await _groupKeyService.runGc(activeGroupIds: activeGroupIds);
  }

  String _contactNameFor(String peerId, {String? fallback}) {
    return ContactNameResolver.resolveFromEntry(
      _contactsBox.get(peerId),
      peerId: peerId,
      fallback: fallback,
    );
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
      return replyTo.fileName?.trim().isNotEmpty == true ? replyTo.fileName!.trim() : 'Файл';
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
    final stored = await _readInitialMessages(peerId, _initialLoadLimit);
    await _processLoadedMessages(peerId, stored);

    chat.messages = stored;
    chat.messagesLoaded = true;
    chat.hasMoreMessages = await _checkHasMoreMessages(peerId, stored.length);
    _refreshSummaryFromMessages(chat, stored);
    developer.log(
      '[chat] ensureChatLoaded peer=$peerId initialLoaded=${stored.length} '
      'hasMore=${chat.hasMoreMessages}',
      name: 'chat',
    );

    _messageUpdatesController.add(peerId);
  }

  Future<List<Message>> _readInitialMessages(String peerId, int limit) async {
    final stored = await _readStoredMessages(peerId);
    if (stored.length <= limit) {
      return stored;
    }

    final firstUnreadIndex = stored.indexWhere(
      (message) => message.incoming && !message.isRead,
    );
    if (firstUnreadIndex != -1) {
      final leadingContextCount = limit ~/ 2;
      final startIndex = (firstUnreadIndex - leadingContextCount).clamp(
        0,
        stored.length,
      );
      return List<Message>.from(
        stored.sublist(startIndex),
        growable: true,
      );
    }

    final startIndex = stored.length - limit;
    if (startIndex <= 0) {
      return stored;
    }

    return List<Message>.from(stored.sublist(startIndex), growable: true);
  }

  /// Загружает все сообщения (для совместимости)
  Future<List<Message>> _readStoredMessages(String peerId) async {
    final raw = await _storage.readChatMessages(peerId);
    return raw.map(Message.fromJson).toList(growable: true);
  }

  /// Сохраняет все сообщения (для совместимости)
  Future<void> _writeStoredMessages(
    String peerId,
    List<Message> messages,
  ) async {
    await _storage.writeChatMessages(
      peerId,
      messages.map((message) => message.toPersistentJson()).toList(growable: false),
    );
  }

  Future<void> _upsertStoredMessages(
    String peerId,
    List<Message> messages,
  ) async {
    await _storage.upsertChatMessages(
      peerId,
      messages.map((message) => message.toPersistentJson()).toList(growable: false),
    );
  }

  Future<void> _deleteStoredMessagesByIds(
    String peerId,
    List<String> messageIds,
  ) async {
    await _storage.deleteChatMessagesByIds(peerId, messageIds);
  }

  /// Проверяет, есть ли ещё сообщения для загрузки
  Future<bool> _checkHasMoreMessages(String peerId, int loadedCount) async {
    final index = await _storage.loadMessagesIndex(peerId);
    final totalMessages = index['totalMessages'] as int? ?? 0;
    developer.log(
      '[chat] hasMore peer=$peerId total=$totalMessages loaded=$loadedCount '
      'result=${totalMessages > loadedCount}',
      name: 'chat',
    );
    return totalMessages > loadedCount;
  }

  /// Обрабатывает загруженные сообщения (восстанавливает медиа файлы)
  Future<void> _processLoadedMessages(String peerId, List<Message> stored) {
    return ChatControllerMedia.processLoadedMessages(
      storage: _storage,
      peerId: peerId,
      stored: stored,
      writeStoredMessages: _writeStoredMessages,
      upsertStoredMessages: _upsertStoredMessages,
      deleteStoredMessagesByIds: _deleteStoredMessagesByIds,
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
    final olderMessages = await _readOlderMessages(peerId, currentCount, _paginationLimit);

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
    return true;
  }

  Future<int?> messageOffsetFromNewest(String peerId, String messageId) {
    return _storage.getMessageOffsetFromNewest(peerId, messageId);
  }

  /// Загружает более старые сообщения
  Future<List<Message>> _readOlderMessages(String peerId, int endIndex, int limit) async {
    final raw = await _storage.loadMessagesPage(peerId, endIndex, limit);
    developer.log(
      '[chat] readOlder peer=$peerId offset=$endIndex limit=$limit fetched=${raw.length}',
      name: 'chat',
    );
    return raw.map(Message.fromJson).toList(growable: true);
  }

  Future<void> _persistChatSummary(Chat chat) async {
    final summaryJson = Map<String, dynamic>.from(chat.toJson())
      ..['messagesLoaded'] = false;
    await _storage.saveChatSummaryMap(chat.peerId, summaryJson);
    var shouldPersistGroupMeta = false;
    if (chat.isGroup || Chat.isGroupLikePeerId(chat.peerId)) {
      final nextMeta = <String, dynamic>{
        'isGroup': true,
        'name': chat.name,
        'ownerPeerId': chat.ownerPeerId,
        'memberPeerIds': chat.memberPeerIds,
        'avatarPath': chat.avatarPath,
      };
      final currentMeta = _groupMetaByGroupId[chat.peerId];
      if (!_isSameGroupMeta(currentMeta, nextMeta)) {
        _groupMetaByGroupId[chat.peerId] = nextMeta;
        shouldPersistGroupMeta = true;
      }
    } else if (_groupMetaByGroupId.remove(chat.peerId) != null) {
      shouldPersistGroupMeta = true;
    }
    if (shouldPersistGroupMeta) {
      await _persistGroupMetaToSettings();
    }
  }

  bool _isSameGroupMeta(
    Map<String, dynamic>? current,
    Map<String, dynamic> next,
  ) {
    if (current == null) {
      return false;
    }
    final currentIsGroup = current['isGroup'] == true;
    final nextIsGroup = next['isGroup'] == true;
    if (currentIsGroup != nextIsGroup) {
      return false;
    }
    final currentName = (current['name'] as String?) ?? '';
    final nextName = (next['name'] as String?) ?? '';
    if (currentName != nextName) {
      return false;
    }
    final currentOwner = (current['ownerPeerId'] as String?) ?? '';
    final nextOwner = (next['ownerPeerId'] as String?) ?? '';
    if (currentOwner != nextOwner) {
      return false;
    }
    final currentMembers = ((current['memberPeerIds'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    final nextMembers = ((next['memberPeerIds'] as List?) ?? const [])
        .whereType<String>()
        .toList(growable: false);
    if (currentMembers.length != nextMembers.length) {
      return false;
    }
    for (var i = 0; i < currentMembers.length; i++) {
      if (currentMembers[i] != nextMembers[i]) {
        return false;
      }
    }
    final currentAvatarPath = (current['avatarPath'] as String?) ?? '';
    final nextAvatarPath = (next['avatarPath'] as String?) ?? '';
    if (currentAvatarPath != nextAvatarPath) {
      return false;
    }
    return true;
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
    _refreshLoadedSummary(chat);
    await _persistChatSummary(chat);
    await _writeStoredMessages(peerId, chat.messages);
  }

  void _schedulePersistLoadedChat(String peerId) {
    unawaited(_persistLoadedChat(peerId));
  }

  void _refreshLoadedSummary(Chat chat) {
    _refreshSummaryFromMessages(chat, chat.messages);
  }

  void _refreshSummaryFromMessages(Chat chat, List<Message> messages) {
    chat.previewMessage = messages.isEmpty ? null : messages.last;
    chat.unreadCount = messages
        .where((message) => message.incoming && !message.isRead)
        .length;
  }

  Future<void> _appendMessage(String peerId, Message message) async {
    final chat = _ensureChat(peerId);
    if (chat.messagesLoaded) {
      chat.messages.add(message);
      await _persistLoadedChat(peerId);
      return;
    }

    final stored = await _readStoredMessages(peerId);
    stored.add(message);
    await _writeStoredMessages(peerId, stored);
    chat.previewMessage = message;
    if (message.incoming && !message.isRead) {
      chat.unreadCount += 1;
    }
    await _persistChatSummary(chat);
  }

  Future<bool> _removeMessage(String peerId, String messageId) async {
    final chat = chats[peerId];
    if (chat == null) {
      return false;
    }

    if (chat.messagesLoaded) {
      final before = chat.messages.length;
      chat.messages.removeWhere((message) => message.id == messageId);
      if (chat.messages.length == before) {
        return false;
      }
      await _persistLoadedChat(peerId);
      return true;
    }

    final stored = await _readStoredMessages(peerId);
    final before = stored.length;
    stored.removeWhere((message) => message.id == messageId);
    if (stored.length == before) {
      return false;
    }
    _refreshSummaryFromMessages(chat, stored);
    await _writeStoredMessages(peerId, stored);
    await _persistChatSummary(chat);
    return true;
  }

  Future<Message?> _findMessage(String peerId, String messageId) async {
    final loaded = chats[peerId];
    if (loaded?.messagesLoaded == true) {
      for (final message in loaded!.messages) {
        if (message.id == messageId) {
          return message;
        }
      }
      return null;
    }

    final stored = await _readStoredMessages(peerId);
    for (final message in stored) {
      if (message.id == messageId) {
        return message;
      }
    }
    return null;
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

  Future<void> _replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) async {
    final chat = _ensureChat(peerId);

    if (chat.messagesLoaded) {
      for (var i = 0; i < chat.messages.length; i++) {
        final current = chat.messages[i];
        if (current.id != messageId) {
          continue;
        }
        chat.messages[i] = transform(current);
        await _persistLoadedChat(peerId);
        return;
      }
      return;
    }

    final stored = await _readStoredMessages(peerId);
    for (var i = 0; i < stored.length; i++) {
      final current = stored[i];
      if (current.id != messageId) {
        continue;
      }
      stored[i] = transform(current);
      _refreshSummaryFromMessages(chat, stored);
      await _writeStoredMessages(peerId, stored);
      await _persistChatSummary(chat);
      return;
    }
  }

  void _listenMessages() {
    facade.messageEvents.listen((event) async {
      final msg = event.payload;
      final dispatch = _classifyIncomingMessage(msg);
      await _handleIncomingMessage(msg, dispatch);
    });
  }

  _IncomingChatDispatch _classifyIncomingMessage(ChatMessage msg) {
    if (msg.kind == 'delete') {
      return const _IncomingDeleteDispatch();
    }
    if (msg.kind == 'profileAvatar') {
      return const _IncomingProfileAvatarDispatch();
    }
    if (msg.kind == 'profileAvatarRemove') {
      return const _IncomingProfileAvatarRemoveDispatch();
    }
    if (msg.kind == 'profileAvatarQuery') {
      return const _IncomingProfileAvatarQueryDispatch();
    }
    final groupInvite = _normalizeGroupInvitePayload(msg.text);
    if (groupInvite != null) {
      return _IncomingGroupInviteDispatch(groupInvite);
    }
    final groupKey = _normalizeGroupKeyPayload(msg.text);
    if (groupKey != null) {
      return _IncomingGroupKeyDispatch(groupKey);
    }
    final groupDelete = _normalizeGroupDeletePayload(msg.text);
    if (groupDelete != null) {
      return _IncomingGroupDeleteDispatch(groupDelete);
    }
    final groupMembers = _normalizeGroupMembersPayload(msg.text);
    if (groupMembers != null) {
      return _IncomingGroupMembersDispatch(groupMembers);
    }
    final groupMessage = _normalizeGroupMessagePayload(msg.text);
    if (groupMessage != null) {
      return _IncomingGroupMessageDispatch(groupMessage);
    }
    final groupSecure = _normalizeGroupSecurePayload(msg.text);
    if (groupSecure != null) {
      return _IncomingGroupSecureDispatch(groupSecure);
    }
    final blobRef = _decodeIncomingBlobRefPayload(msg.text);
    if (blobRef != null && blobRef.isDirect) {
      return _IncomingDirectBlobRefDispatch(blobRef);
    }
    final isDisplayableKind = msg.kind == 'text' || msg.kind == 'file';
    if (isDisplayableKind) {
      return const _IncomingDisplayableDispatch();
    }
    return const _IncomingIgnoredDispatch();
  }

  Future<void> _handleIncomingMessage(
    ChatMessage msg,
    _IncomingChatDispatch dispatch,
  ) async {
    switch (dispatch) {
      case _IncomingDeleteDispatch():
        if (msg.text.isNotEmpty) {
          if (_isGroupDeletePayload(msg.text)) {
            await _handleIncomingGroupDelete(msg);
            return;
          }
          final removed = await _removeMessageWithMediaCleanup(msg.peerId, msg.text);
          if (!removed) {
            developer.log(
              '[chat] delete out-of-sync peer=${msg.peerId} messageId=${msg.text}',
              name: 'chat',
            );
          }
          _messageUpdatesController.add(msg.peerId);
        }
        return;
      case _IncomingProfileAvatarDispatch():
        await _avatarService.handleIncomingAvatarAnnouncement(
          msg.peerId,
          msg.text,
        );
        return;
      case _IncomingProfileAvatarRemoveDispatch():
        await _avatarService.handleIncomingAvatarRemoval(
          msg.peerId,
          msg.text,
        );
        return;
      case _IncomingProfileAvatarQueryDispatch():
        await _avatarService.handleIncomingAvatarQuery(
          msg.peerId,
          msg.text,
        );
        return;
      case _IncomingGroupInviteDispatch(payload: final payload):
        await _handleIncomingGroupInvite(msg, payload: payload);
        return;
      case _IncomingGroupKeyDispatch(payload: final payload):
        await _handleIncomingGroupKey(msg, payload: payload);
        return;
      case _IncomingGroupDeleteDispatch(payload: final payload):
        await _handleIncomingGroupDelete(msg, payload: payload);
        return;
      case _IncomingGroupMembersDispatch(payload: final payload):
        await _handleIncomingGroupMembersUpdate(msg, payload: payload);
        return;
      case _IncomingGroupMessageDispatch(payload: final payload):
        await _handleIncomingGroupMessage(msg, payload: payload);
        return;
      case _IncomingGroupSecureDispatch(payload: final payload):
        await _handleIncomingGroupSecureMessage(msg, payload: payload);
        return;
      case _IncomingDirectBlobRefDispatch(blobRef: final blobRef):
        await _handleIncomingDirectBlobRef(msg, blobRef);
        return;
      case _IncomingDisplayableDispatch():
        _setStatus(msg.peerId, ChatConnectionStatus.connected);

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

        await _appendMessage(msg.peerId, message);
        _messageUpdatesController.add(msg.peerId);
        _newMessageNotificationController.add(msg);

        NotificationService.instance
            .showMessageNotification(
              fromPeerId: msg.peerId,
              message: msg.text,
              badgeCount: unreadMessagesCount(),
            )
            .catchError((error) {
          developer.log('notification error: $error', name: 'chat');
        });
        return;
      case _IncomingIgnoredDispatch():
        developer.log(
          '[chat] ignored non-display message kind=${msg.kind} from=${msg.peerId} id=${msg.id}',
          name: 'chat',
        );
        return;
    }
  }

  bool _isGroupInvitePayload(String text) {
    return text.startsWith(_groupInvitePrefix);
  }

  bool _isGroupMessagePayload(String text) {
    return text.startsWith(_groupMessagePrefix);
  }

  bool _isGroupDeletePayload(String text) {
    return text.startsWith(_groupDeletePrefix);
  }

  bool _isGroupMembersPayload(String text) {
    return text.startsWith(_groupMembersPrefix);
  }

  bool _isGroupKeyPayload(String text) {
    return text.startsWith(_groupKeyPrefix);
  }

  bool _isGroupSecurePayload(String text) {
    return text.startsWith(_groupSecurePrefix);
  }

  Future<String> _ensureGroupKey(Chat groupChat) async {
    return _groupKeyService.ensureGroupKey(groupChat.peerId);
  }

  String _encodeGroupKeyPayload({
    required Chat groupChat,
    required String groupKeyBase64,
    required int keyVersion,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_key',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupName': groupChat.name,
      'ownerPeerId': groupChat.ownerPeerId ?? facade.peerId,
      'groupKey': groupKeyBase64,
      'keyVersion': keyVersion,
      'senderPeerId': facade.peerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$_groupKeyPrefix${jsonEncode(payload)}';
  }

  Future<void> _sendGroupKeyToRecipients(
    Chat groupChat,
    List<String> recipients, {
    String? groupKeyBase64,
    int? keyVersion,
  }) async {
    final groupKey = groupKeyBase64 ?? await _ensureGroupKey(groupChat);
    final versionCandidate =
        keyVersion ?? _groupKeyService.keyVersionForGroup(groupChat.peerId);
    final resolvedVersion = versionCandidate <= 0 ? 1 : versionCandidate;
    final payload = _encodeGroupKeyPayload(
      groupChat: groupChat,
      groupKeyBase64: groupKey,
      keyVersion: resolvedVersion,
    );
    final targets = recipients
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != facade.peerId)
        .toSet()
        .toList(growable: false);
    for (var i = 0; i < targets.length; i++) {
      try {
        await facade.sendControlMessage(
          targets[i],
          kind: 'groupKey',
          text: payload,
        );
      } catch (_) {
        // best effort, peer may be offline; message relay retry/poll will reconcile.
      }
    }
  }

  Future<void> _rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) async {
    final rotation = await _groupKeyService.rotateGroupKey(groupChat.peerId);
    await _sendGroupKeyToRecipients(
      groupChat,
      recipients,
      groupKeyBase64: rotation.keyBase64,
      keyVersion: rotation.version,
    );
  }

  Future<void> _syncGroupMembershipWithRelay(Chat groupChat) async {
    final ownerPeerId = (groupChat.ownerPeerId ?? '').trim();
    if (ownerPeerId.isEmpty || ownerPeerId != facade.peerId) {
      return;
    }
    final members = <String>{
      ...groupChat.memberPeerIds.map((item) => item.trim()).where((item) => item.isNotEmpty),
      facade.peerId,
    }.toList(growable: false)
      ..sort();
    try {
      await facade.updateRelayGroupMembers(
        groupId: groupChat.peerId,
        ownerPeerId: ownerPeerId,
        memberPeerIds: members,
      );
    } catch (error) {
      developer.log(
        'group membership sync failed group=${groupChat.peerId} error=$error',
        name: 'chat',
      );
    }
  }

  Map<String, dynamic>? _decodeGroupInvitePayload(String text) {
    if (!_isGroupInvitePayload(text)) {
      return null;
    }
    try {
      final raw = text.substring(_groupInvitePrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _encodeGroupInvitePayload({
    required String groupId,
    required String groupName,
    required List<String> memberPeerIds,
    required String ownerPeerId,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_invite',
      'v': 1,
      'groupId': groupId,
      'groupName': groupName,
      'memberPeerIds': memberPeerIds,
      'inviterPeerId': facade.peerId,
      'ownerPeerId': ownerPeerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$_groupInvitePrefix${jsonEncode(payload)}';
  }

  Map<String, dynamic>? _decodeGroupMessagePayload(String text) {
    if (!_isGroupMessagePayload(text)) {
      return null;
    }
    try {
      final raw = text.substring(_groupMessagePrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic>? _decodeGroupDeletePayload(String text) {
    if (!_isGroupDeletePayload(text)) {
      return null;
    }
    try {
      final raw = text.substring(_groupDeletePrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic>? _decodeGroupMembersPayload(String text) {
    if (!_isGroupMembersPayload(text)) {
      return null;
    }
    try {
      final raw = text.substring(_groupMembersPrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic>? _decodeGroupKeyPayload(String text) {
    if (!_isGroupKeyPayload(text)) {
      return null;
    }
    try {
      final raw = text.substring(_groupKeyPrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic>? _decodeGroupSecurePayloadRaw(String text) {
    if (!_isGroupSecurePayload(text)) {
      return null;
    }
    try {
      final raw = text.substring(_groupSecurePrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<String?> _encryptGroupText({
    required String groupId,
    required String plainText,
  }) async {
    final keyBase64 = _groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      return null;
    }
    final secretKey = SecretKey(keyBytes);
    final nonce = _groupCipher.newNonce();
    final clear = Uint8List.fromList(utf8.encode(plainText));
    final secretBox = await _groupCipher.encrypt(
      clear,
      secretKey: secretKey,
      nonce: nonce,
    );
    final payload = <String, dynamic>{
      'v': 1,
      'groupId': groupId,
      'nonce': base64Encode(secretBox.nonce),
      'cipher': base64Encode(secretBox.cipherText),
      'mac': base64Encode(secretBox.mac.bytes),
    };
    return '$_groupSecurePrefix${jsonEncode(payload)}';
  }

  Future<Uint8List?> _encryptGroupBytes({
    required String groupId,
    required Uint8List plainBytes,
  }) async {
    final keyBase64 = _groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    if (plainBytes.length >= 256 * 1024) {
      return Isolate.run(
        () => _encryptGroupBytesIsolate(
          groupId: groupId,
          keyBase64: keyBase64,
          plainBytes: plainBytes,
        ),
      );
    }
    return _encryptGroupBytesIsolate(
      groupId: groupId,
      keyBase64: keyBase64,
      plainBytes: plainBytes,
    );
  }

  Future<String?> _decryptGroupText(String text) async {
    final payload = _decodeGroupSecurePayloadRaw(text);
    if (payload == null) {
      return null;
    }
    final groupId = (payload['groupId'] as String? ?? '').trim();
    if (groupId.isEmpty) {
      return null;
    }
    final keyBase64 = _groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    final nonceRaw = payload['nonce'] as String?;
    final cipherRaw = payload['cipher'] as String?;
    final macRaw = payload['mac'] as String?;
    if (nonceRaw == null || cipherRaw == null || macRaw == null) {
      return null;
    }
    final keyBytes = base64Decode(keyBase64);
    if (keyBytes.length != 32) {
      return null;
    }
    final secretBox = SecretBox(
      base64Decode(cipherRaw),
      nonce: base64Decode(nonceRaw),
      mac: Mac(base64Decode(macRaw)),
    );
    final clear = await _groupCipher.decrypt(
      secretBox,
      secretKey: SecretKey(keyBytes),
    );
    return utf8.decode(clear);
  }

  Future<Uint8List?> _decryptGroupBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    final keyBase64 = _groupKeyService.keyForGroup(groupId);
    if (keyBase64 == null || keyBase64.isEmpty) {
      return null;
    }
    if (encryptedBytes.length >= 256 * 1024) {
      return Isolate.run(
        () => _decryptGroupBytesIsolate(
          groupId: groupId,
          keyBase64: keyBase64,
          encryptedBytes: encryptedBytes,
        ),
      );
    }
    return _decryptGroupBytesIsolate(
      groupId: groupId,
      keyBase64: keyBase64,
      encryptedBytes: encryptedBytes,
    );
  }

  String _encodeGroupMessagePayload({
    required Chat groupChat,
    required String messageId,
    required String text,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_message',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupMessageId': messageId,
      'groupName': groupChat.name,
      'text': text,
      'memberPeerIds': groupChat.memberPeerIds,
      'senderPeerId': facade.peerId,
      'ownerPeerId': groupChat.ownerPeerId ?? facade.peerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$_groupMessagePrefix${jsonEncode(payload)}';
  }

  String _encodeGroupDeletePayload({
    required String groupId,
    required String messageId,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_delete',
      'v': 1,
      'groupId': groupId,
      'groupMessageId': messageId,
      'senderPeerId': facade.peerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$_groupDeletePrefix${jsonEncode(payload)}';
  }

  String _groupFileTransferId({
    required String groupId,
    required String messageId,
  }) {
    return 'grpfile:$groupId|$messageId';
  }

  String _groupBlobTransferId({
    required String groupId,
    required String messageId,
    required String blobId,
  }) {
    return 'grpblob:$groupId|$messageId|$blobId';
  }

  String _directBlobTransferId({
    required String peerId,
    required String messageId,
    required String blobId,
  }) {
    return 'dirblob:$peerId|$messageId|$blobId';
  }

  ({String groupId, String messageId, String blobId})? _parseGroupBlobTransferId(
    String? transferId,
  ) {
    final raw = transferId?.trim() ?? '';
    if (!raw.startsWith('grpblob:')) {
      return null;
    }
    final body = raw.substring('grpblob:'.length);
    final first = body.indexOf('|');
    final second = body.indexOf('|', first + 1);
    if (first <= 0 || second <= first + 1 || second >= body.length - 1) {
      return null;
    }
    final groupId = body.substring(0, first).trim();
    final messageId = body.substring(first + 1, second).trim();
    final blobId = body.substring(second + 1).trim();
    if (groupId.isEmpty || messageId.isEmpty || blobId.isEmpty) {
      return null;
    }
    return (groupId: groupId, messageId: messageId, blobId: blobId);
  }

  ({String peerId, String messageId, String blobId})? _parseDirectBlobTransferId(
    String? transferId,
  ) {
    final raw = transferId?.trim() ?? '';
    if (!raw.startsWith('dirblob:')) {
      return null;
    }
    final body = raw.substring('dirblob:'.length);
    final first = body.indexOf('|');
    final second = body.indexOf('|', first + 1);
    if (first <= 0 || second <= first + 1 || second >= body.length - 1) {
      return null;
    }
    final peerId = body.substring(0, first).trim();
    final messageId = body.substring(first + 1, second).trim();
    final blobId = body.substring(second + 1).trim();
    if (peerId.isEmpty || messageId.isEmpty || blobId.isEmpty) {
      return null;
    }
    return (peerId: peerId, messageId: messageId, blobId: blobId);
  }

  String _encodeGroupBlobRefPayload({
    required Chat groupChat,
    required String messageId,
    required String contentKind,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    String? textPreview,
    required String blobId,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_blob_ref',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupMessageId': messageId,
      'groupName': groupChat.name,
      'contentKind': contentKind,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSizeBytes': fileSizeBytes,
      'textPreview': textPreview,
      'blobId': blobId,
      'memberPeerIds': groupChat.memberPeerIds,
      'senderPeerId': facade.peerId,
      'ownerPeerId': groupChat.ownerPeerId ?? facade.peerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$_groupBlobRefPrefix${jsonEncode(payload)}';
  }

  Map<String, dynamic>? _decodeGroupBlobRefPayload(String text) {
    if (!text.startsWith(_groupBlobRefPrefix)) {
      return null;
    }
    try {
      final raw = text.substring(_groupBlobRefPrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  _IncomingBlobRefPayload? _decodeIncomingBlobRefPayload(String text) {
    final direct = _decodeDirectBlobRefPayload(text);
    if (direct != null) {
      return _normalizeBlobRefPayload(
        direct,
        targetKind: 'direct',
        chatPeerId: (direct['peerId'] as String? ?? '').trim(),
        messageId: (direct['messageId'] as String? ?? '').trim(),
      );
    }

    final group = _decodeGroupBlobRefPayload(text);
    if (group != null) {
      return _normalizeBlobRefPayload(
        group,
        targetKind: 'group',
        chatPeerId: (group['groupId'] as String? ?? '').trim(),
        messageId: (group['groupMessageId'] as String? ?? '').trim(),
      );
    }

    return null;
  }

  _IncomingGroupInvitePayload? _normalizeGroupInvitePayload(String text) {
    final raw = _decodeGroupInvitePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupName = (raw['groupName'] as String? ?? '').trim();
    if (groupId.isEmpty || groupName.isEmpty) {
      return null;
    }
    final memberPeerIds = <String>[];
    final rawMembers = raw['memberPeerIds'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is String && item.trim().isNotEmpty) {
          memberPeerIds.add(item.trim());
        }
      }
    }
    return _IncomingGroupInvitePayload(
      groupId: groupId,
      groupName: groupName,
      memberPeerIds: memberPeerIds,
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  _IncomingGroupMessagePayload? _normalizeGroupMessagePayload(String text) {
    final raw = _decodeGroupMessagePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupMessageId = (raw['groupMessageId'] as String? ?? '').trim();
    final messageText = (raw['text'] as String? ?? '').trim();
    if (groupId.isEmpty || groupMessageId.isEmpty || messageText.isEmpty) {
      return null;
    }
    final memberPeerIds = <String>[];
    final rawMembers = raw['memberPeerIds'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is String && item.trim().isNotEmpty) {
          memberPeerIds.add(item.trim());
        }
      }
    }
    return _IncomingGroupMessagePayload(
      groupId: groupId,
      groupMessageId: groupMessageId,
      text: messageText,
      groupName: (raw['groupName'] as String? ?? '').trim(),
      memberPeerIds: memberPeerIds,
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  _IncomingGroupDeletePayload? _normalizeGroupDeletePayload(String text) {
    final raw = _decodeGroupDeletePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupMessageId = (raw['groupMessageId'] as String? ?? '').trim();
    if (groupId.isEmpty || groupMessageId.isEmpty) {
      return null;
    }
    return _IncomingGroupDeletePayload(
      groupId: groupId,
      groupMessageId: groupMessageId,
      raw: raw,
    );
  }

  _IncomingGroupMembersPayload? _normalizeGroupMembersPayload(String text) {
    final raw = _decodeGroupMembersPayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final rawMembers = raw['memberPeerIds'];
    if (groupId.isEmpty || rawMembers is! List) {
      return null;
    }
    final memberPeerIds = <String>[];
    for (final item in rawMembers) {
      if (item is String && item.trim().isNotEmpty) {
        memberPeerIds.add(item.trim());
      }
    }
    final changedPeerIds = <String>[];
    final changedRaw = raw['changedPeerIds'];
    if (changedRaw is List) {
      for (final item in changedRaw) {
        if (item is String && item.trim().isNotEmpty) {
          changedPeerIds.add(item.trim());
        }
      }
    }
    final rawUpdatedAtMs = raw['avatarUpdatedAtMs'];
    final updatedAtMs = rawUpdatedAtMs is int
        ? rawUpdatedAtMs
        : int.tryParse('${rawUpdatedAtMs ?? ''}');
    return _IncomingGroupMembersPayload(
      groupId: groupId,
      groupName: (raw['groupName'] as String? ?? '').trim(),
      ownerPeerId: (raw['ownerPeerId'] as String? ?? '').trim(),
      action: (raw['action'] as String? ?? '').trim(),
      memberPeerIds: memberPeerIds,
      changedPeerIds: changedPeerIds,
      avatarBlobId: (raw['avatarBlobId'] as String?)?.trim(),
      avatarMimeType: (raw['avatarMimeType'] as String?)?.trim(),
      avatarUpdatedAtMs: updatedAtMs,
      raw: raw,
    );
  }

  _IncomingGroupKeyPayload? _normalizeGroupKeyPayload(String text) {
    final raw = _decodeGroupKeyPayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupKey = (raw['groupKey'] as String? ?? '').trim();
    if (groupId.isEmpty || groupKey.isEmpty) {
      return null;
    }
    final keyVersion = raw['keyVersion'] is int
        ? raw['keyVersion'] as int
        : int.tryParse('${raw['keyVersion']}') ?? 1;
    return _IncomingGroupKeyPayload(
      groupId: groupId,
      groupKey: groupKey,
      keyVersion: keyVersion,
      raw: raw,
    );
  }

  _IncomingGroupSecurePayload? _normalizeGroupSecurePayload(String text) {
    final raw = _decodeGroupSecurePayloadRaw(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    if (groupId.isEmpty) {
      return null;
    }
    return _IncomingGroupSecurePayload(
      groupId: groupId,
      raw: raw,
    );
  }

  _IncomingBlobRefPayload? _normalizeBlobRefPayload(
    Map<String, dynamic> raw, {
    required String targetKind,
    required String chatPeerId,
    required String messageId,
  }) {
    final blobId = (raw['blobId'] as String? ?? '').trim();
    if (chatPeerId.isEmpty || messageId.isEmpty || blobId.isEmpty) {
      return null;
    }
    final memberPeerIds = <String>[];
    final rawMembers = raw['memberPeerIds'];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is String && item.trim().isNotEmpty) {
          memberPeerIds.add(item.trim());
        }
      }
    }
    return _IncomingBlobRefPayload(
      targetKind: targetKind,
      chatPeerId: chatPeerId,
      messageId: messageId,
      contentKind: (raw['contentKind'] as String? ?? '').trim(),
      blobId: blobId,
      fileName: (raw['fileName'] as String?)?.trim(),
      mimeType: (raw['mimeType'] as String?)?.trim(),
      fileSizeBytes: raw['fileSizeBytes'] as int?,
      textPreview: (raw['textPreview'] as String?)?.trim(),
      groupName: (raw['groupName'] as String?)?.trim(),
      memberPeerIds: memberPeerIds,
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  String _encodeGroupMembersPayload({
    required Chat groupChat,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_members',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupName': groupChat.name,
      'ownerPeerId': groupChat.ownerPeerId ?? facade.peerId,
      'memberPeerIds': groupChat.memberPeerIds,
      'changedPeerIds': changedPeerIds,
      'action': action,
      'senderPeerId': facade.peerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (avatarBlobId != null && avatarBlobId.trim().isNotEmpty) {
      payload['avatarBlobId'] = avatarBlobId.trim();
    }
    if (avatarMimeType != null && avatarMimeType.trim().isNotEmpty) {
      payload['avatarMimeType'] = avatarMimeType.trim();
    }
    if (avatarFileSizeBytes != null && avatarFileSizeBytes > 0) {
      payload['avatarFileSizeBytes'] = avatarFileSizeBytes;
    }
    if (avatarUpdatedAtMs != null && avatarUpdatedAtMs > 0) {
      payload['avatarUpdatedAtMs'] = avatarUpdatedAtMs;
    }
    return '$_groupMembersPrefix${jsonEncode(payload)}';
  }

  List<String> _collectGroupRecipients(Chat groupChat) {
    final recipients = <String>{};
    for (final item in groupChat.memberPeerIds) {
      final peerId = item.trim();
      if (peerId.isNotEmpty && peerId != facade.peerId) {
        recipients.add(peerId);
      }
    }
    final list = recipients.toList(growable: false);
    list.sort();
    return list;
  }

  Future<void> _handleIncomingGroupInvite(
    ChatMessage msg, {
    _IncomingGroupInvitePayload? payload,
  }) async {
    final resolvedPayload = payload ?? _normalizeGroupInvitePayload(msg.text);
    if (resolvedPayload == null) {
      developer.log(
        'group invite drop: invalid payload from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final groupId = resolvedPayload.groupId;
    final groupName = resolvedPayload.groupName;
    if (groupId.isEmpty || groupName.isEmpty) {
      developer.log(
        'group invite drop: missing group fields from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final memberPeerIds = <String>{...resolvedPayload.memberPeerIds};
    memberPeerIds.add(msg.peerId);
    memberPeerIds.add(facade.peerId);
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final resolvedOwner = (ownerPeerId != null && ownerPeerId.isNotEmpty)
        ? ownerPeerId
        : msg.peerId;

    final chat = chats[groupId] ??
        Chat(
          peerId: groupId,
          name: groupName,
          isGroup: true,
          memberPeerIds: memberPeerIds.toList(growable: false),
          ownerPeerId: resolvedOwner,
          messagesLoaded: true,
          hasMoreMessages: false,
        );

    chat.name = groupName;
    chat.isGroup = true;
    chat.memberPeerIds = memberPeerIds.toList(growable: false);
    chat.ownerPeerId = resolvedOwner;
    chats[groupId] = chat;
    developer.log(
      'group invite applied group=$groupId from=${msg.peerId} members=${chat.memberPeerIds.length}',
      name: 'chat',
    );

    final invitationMessage = Message(
      id: msg.id,
      peerId: groupId,
      text: 'Вас пригласили в чат "$groupName"',
      senderPeerId: msg.peerId,
      incoming: true,
      timestamp: DateTime.now(),
      status: MessageStatus.sent,
      isRead: false,
    );
    await _appendMessage(groupId, invitationMessage);
    _messageUpdatesController.add(groupId);
  }

  Future<void> _handleIncomingGroupKey(
    ChatMessage msg, {
    _IncomingGroupKeyPayload? payload,
  }) async {
    final resolvedPayload = payload ?? _normalizeGroupKeyPayload(msg.text);
    if (resolvedPayload == null) {
      return;
    }
    final groupId = resolvedPayload.groupId;
    final groupKey = resolvedPayload.groupKey;
    if (groupId.isEmpty || groupKey.isEmpty) {
      return;
    }
    await _groupKeyService.applyIncomingGroupKey(
      groupId: groupId,
      groupKeyBase64: groupKey,
      keyVersion: resolvedPayload.keyVersion,
    );
  }

  Future<void> _handleIncomingGroupSecureMessage(
    ChatMessage msg, {
    _IncomingGroupSecurePayload? payload,
  }) async {
    final resolvedPayload = payload ?? _normalizeGroupSecurePayload(msg.text);
    if (resolvedPayload == null) {
      return;
    }
    final groupId = resolvedPayload.groupId;
    if (groupId.isEmpty) {
      return;
    }
    final clearText = await _decryptGroupText(msg.text);
    if (clearText == null || clearText.isEmpty) {
      developer.log(
        'group secure message drop: decrypt failed group=$groupId from=${msg.peerId}',
        name: 'chat',
      );
      return;
    }

    final existingChat = chats[groupId];
    final chat = existingChat ??
        Chat(
          peerId: groupId,
          name: groupId,
          isGroup: true,
          memberPeerIds: <String>[facade.peerId, msg.peerId],
          ownerPeerId: msg.peerId,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    chats[groupId] = chat;

    if (existingChat != null) {
      if (!chat.memberPeerIds.contains(facade.peerId)) {
        developer.log(
          'group secure message drop: self is not a member group=$groupId',
          name: 'chat',
        );
        return;
      }
      if (!chat.memberPeerIds.contains(msg.peerId)) {
        developer.log(
          'group secure message drop: sender is not a member group=$groupId sender=${msg.peerId}',
          name: 'chat',
        );
        return;
      }
    }
    final groupName = chat.name;

    final blobRef = _decodeIncomingBlobRefPayload(clearText);
    if (blobRef != null && blobRef.isGroup) {
      await _handleIncomingGroupBlobRef(
        msg,
        groupId: groupId,
        groupChat: chat,
        existingGroupChat: existingChat,
        blobRef: blobRef,
        notificationSenderLabel: groupName,
      );
      return;
    }

    final incoming = Message(
      id: msg.id,
      peerId: groupId,
      text: clearText,
      senderPeerId: msg.peerId,
      incoming: true,
      timestamp: DateTime.now(),
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await _appendMessage(groupId, incoming);
    _messageUpdatesController.add(groupId);
    _newMessageNotificationController.add(
      ChatMessage(
        id: msg.id,
        peerId: groupId,
        text: clearText,
      ),
    );
    NotificationService.instance
        .showMessageNotification(
          fromPeerId: groupName,
          message: clearText,
          badgeCount: unreadMessagesCount(),
        )
        .catchError((error) {
      developer.log('notification error: $error', name: 'chat');
        });
  }

  Future<void> _handleIncomingGroupMessage(
    ChatMessage msg, {
    _IncomingGroupMessagePayload? payload,
  }) async {
    final resolvedPayload = payload ?? _normalizeGroupMessagePayload(msg.text);
    if (resolvedPayload == null) {
      developer.log(
        'group message drop: invalid payload from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final groupId = resolvedPayload.groupId;
    final groupMessageId = resolvedPayload.groupMessageId;
    final text = resolvedPayload.text;
    final groupName = resolvedPayload.groupName;
    if (groupId.isEmpty || groupMessageId.isEmpty || text.isEmpty) {
      developer.log(
        'group message drop: missing fields from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final members = <String>{...resolvedPayload.memberPeerIds};
    members.add(msg.peerId);
    members.add(facade.peerId);
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final resolvedOwner = (ownerPeerId != null && ownerPeerId.isNotEmpty)
        ? ownerPeerId
        : msg.peerId;

    final existing = chats[groupId];
    final chat = existing ??
        Chat(
          peerId: groupId,
          name: groupName.isNotEmpty ? groupName : groupId,
          isGroup: true,
          memberPeerIds: members.toList(growable: false),
          ownerPeerId: resolvedOwner,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    if (groupName.isNotEmpty) {
      chat.name = groupName;
    }
    if (existing == null) {
      chat.memberPeerIds = members.toList(growable: false);
      chat.ownerPeerId = resolvedOwner;
    } else if ((chat.ownerPeerId == null || chat.ownerPeerId!.isEmpty) &&
        resolvedOwner.isNotEmpty) {
      chat.ownerPeerId = resolvedOwner;
    }
    chats[groupId] = chat;

    if (!chat.memberPeerIds.contains(facade.peerId)) {
      developer.log(
        'group message drop: self is not a member group=$groupId',
        name: 'chat',
      );
      return;
    }
    if (!chat.memberPeerIds.contains(msg.peerId)) {
      developer.log(
        'group message drop: sender is not a member group=$groupId sender=${msg.peerId}',
        name: 'chat',
      );
      return;
    }

    final blobRef = _decodeIncomingBlobRefPayload(text);
    if (blobRef != null && blobRef.isGroup) {
      await _handleIncomingGroupBlobRef(
        msg,
        groupId: groupId,
        groupChat: chat,
        existingGroupChat: existing,
        blobRef: blobRef,
        notificationSenderLabel: groupName.isNotEmpty ? groupName : chat.name,
      );
      return;
    }

    final incoming = Message(
      id: groupMessageId,
      peerId: groupId,
      text: text,
      senderPeerId: msg.peerId,
      incoming: true,
      timestamp: DateTime.now(),
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await _appendMessage(groupId, incoming);
    _messageUpdatesController.add(groupId);

    _newMessageNotificationController.add(
      ChatMessage(
        id: msg.id,
        peerId: groupId,
        text: text,
      ),
    );
    NotificationService.instance
        .showMessageNotification(
          fromPeerId: groupName.isNotEmpty ? groupName : groupId,
          message: text,
          badgeCount: unreadMessagesCount(),
        )
        .catchError((error) {
      developer.log('notification error: $error', name: 'chat');
        });
  }

  Future<void> _handleIncomingGroupDelete(
    ChatMessage msg, {
    _IncomingGroupDeletePayload? payload,
  }) async {
    final resolvedPayload = payload ?? _normalizeGroupDeletePayload(msg.text);
    if (resolvedPayload == null) {
      developer.log(
        'group delete drop: invalid payload from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final groupId = resolvedPayload.groupId;
    final groupMessageId = resolvedPayload.groupMessageId;
    if (groupId.isEmpty || groupMessageId.isEmpty) {
      developer.log(
        'group delete drop: missing fields from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final removed = await _removeMessageWithMediaCleanup(groupId, groupMessageId);
    if (!removed) {
      developer.log(
        '[chat] group delete out-of-sync group=$groupId messageId=$groupMessageId',
        name: 'chat',
      );
    }
    _messageUpdatesController.add(groupId);
  }

  Future<void> _handleIncomingGroupMembersUpdate(
    ChatMessage msg, {
    _IncomingGroupMembersPayload? payload,
  }) async {
    final resolvedPayload = payload ?? _normalizeGroupMembersPayload(msg.text);
    if (resolvedPayload == null) {
      developer.log(
        'group members drop: invalid payload from=${msg.peerId} id=${msg.id}',
        name: 'chat',
      );
      return;
    }

    final groupId = resolvedPayload.groupId;
    final groupName = resolvedPayload.groupName;
    final ownerPeerId = resolvedPayload.ownerPeerId;
    final action = resolvedPayload.action;
    if (groupId.isEmpty) {
      return;
    }

    final members = <String>{...resolvedPayload.memberPeerIds};
    if (msg.peerId.trim().isNotEmpty) {
      members.add(msg.peerId.trim());
    }
    final changedPeerIds = <String>{...resolvedPayload.changedPeerIds};
    final selfRemoved = action == 'remove' && changedPeerIds.contains(facade.peerId);
    if (!selfRemoved) {
      members.add(facade.peerId);
    }
    final chat = chats[groupId] ??
        Chat(
          peerId: groupId,
          name: groupName.isNotEmpty ? groupName : groupId,
          isGroup: true,
          memberPeerIds: members.toList(growable: false),
          ownerPeerId: ownerPeerId.isNotEmpty ? ownerPeerId : msg.peerId,
          messagesLoaded: true,
          hasMoreMessages: false,
        );
    chat.isGroup = true;
    if (groupName.isNotEmpty) {
      chat.name = groupName;
    }
    chat.memberPeerIds = members.toList(growable: false);
    if (ownerPeerId.isNotEmpty) {
      chat.ownerPeerId = ownerPeerId;
    }
    chats[groupId] = chat;
    await _persistChatSummary(chat);

    if (action == 'avatar') {
      final avatarBlobId = (resolvedPayload.avatarBlobId ?? '').trim();
      if (avatarBlobId.isNotEmpty) {
        final knownOwner = (chat.ownerPeerId ?? '').trim();
        if (knownOwner.isNotEmpty && msg.peerId != knownOwner) {
          developer.log(
            'group avatar drop: sender is not owner group=$groupId sender=${msg.peerId}',
            name: 'chat',
          );
          _messageUpdatesController.add(groupId);
          return;
        }
        try {
          final blob = await facade.downloadBlob(avatarBlobId);
          final decrypted = await _decryptGroupBytes(
            groupId: groupId,
            encryptedBytes: blob.payload,
          );
          final avatarBytes = decrypted ?? blob.payload;
          final avatarMime = resolvedPayload.avatarMimeType?.trim();
          final updatedAtMs = resolvedPayload.avatarUpdatedAtMs ??
              DateTime.now().millisecondsSinceEpoch;
          await _saveGroupAvatarBytes(
            groupChat: chat,
            bytes: avatarBytes,
            mimeType: avatarMime?.isNotEmpty == true ? avatarMime! : 'image/png',
            updatedAtMs: updatedAtMs,
          );
        } catch (_) {
          // Ignore avatar sync failures.
        }
      }
    }
    _messageUpdatesController.add(groupId);
  }

  Future<void> _handleIncomingGroupBlobRef(
    ChatMessage msg, {
    required String groupId,
    required Chat groupChat,
    required Chat? existingGroupChat,
    required _IncomingBlobRefPayload blobRef,
    required String notificationSenderLabel,
  }) async {
    if (blobRef.chatPeerId != groupId || blobRef.blobId.isEmpty) {
      return;
    }

    if (existingGroupChat == null && blobRef.memberPeerIds.isNotEmpty) {
      final members = <String>{
        ...blobRef.memberPeerIds,
        msg.peerId,
        facade.peerId,
      };
      groupChat.memberPeerIds = members.toList(growable: false);
    }
    final ownerPeerId = blobRef.ownerPeerId;
    if (ownerPeerId != null && ownerPeerId.isNotEmpty) {
      groupChat.ownerPeerId = ownerPeerId;
    }

    if (blobRef.contentKind == 'text') {
      final text = await _restoreGroupBlobText(
        groupId: groupId,
        blobId: blobRef.blobId,
        fallback: blobRef.textPreview,
      );
      if (text == null || text.isEmpty) {
        return;
      }
      final incoming = Message(
        id: blobRef.messageId,
        peerId: groupId,
        text: text,
        senderPeerId: msg.peerId,
        incoming: true,
        timestamp: DateTime.now(),
        replyToMessageId: msg.replyToMessageId,
        replyToSenderPeerId: msg.replyToSenderPeerId,
        replyToSenderLabel: msg.replyToSenderLabel,
        replyToTextPreview: msg.replyToTextPreview,
        replyToKind: msg.replyToKind,
        status: MessageStatus.sent,
        isRead: false,
      );
      await _appendMessage(groupId, incoming);
      _messageUpdatesController.add(groupId);
      _newMessageNotificationController.add(
        ChatMessage(
          id: blobRef.messageId,
          peerId: groupId,
          text: text,
        ),
      );
      NotificationService.instance
          .showMessageNotification(
            fromPeerId: notificationSenderLabel,
            message: text,
            badgeCount: unreadMessagesCount(),
          )
          .catchError((error) {
        developer.log('notification error: $error', name: 'chat');
      });
      return;
    }

    if (blobRef.contentKind == 'avatar') {
      try {
        final blob = await facade.downloadBlob(blobRef.blobId);
        final avatarBytes = await _decodeGroupBlobBytes(
          groupId: groupId,
          encryptedBytes: blob.payload,
        );
        final avatarMime = blobRef.mimeType;
        await _saveGroupAvatarBytes(
          groupChat: groupChat,
          bytes: avatarBytes,
          mimeType: avatarMime?.isNotEmpty == true ? avatarMime! : 'image/png',
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        _messageUpdatesController.add(groupId);
      } catch (_) {
        // Ignore avatar sync failures.
      }
      return;
    }

    if (blobRef.contentKind != 'media') {
      return;
    }

    final fileName = (blobRef.fileName ?? '').trim();
    if (fileName.isEmpty) {
      return;
    }

    final incoming = Message(
      id: blobRef.messageId,
      peerId: groupId,
      text: fileName,
      senderPeerId: msg.peerId,
      incoming: true,
      timestamp: DateTime.now(),
      kind: MessageKind.file,
      fileName: fileName,
      mimeType: blobRef.mimeType,
      transferId: _groupBlobTransferId(
        groupId: groupId,
        messageId: blobRef.messageId,
        blobId: blobRef.blobId,
      ),
      fileSizeBytes: blobRef.fileSizeBytes,
      replyToMessageId: msg.replyToMessageId,
      replyToSenderPeerId: msg.replyToSenderPeerId,
      replyToSenderLabel: msg.replyToSenderLabel,
      replyToTextPreview: msg.replyToTextPreview,
      replyToKind: msg.replyToKind,
      status: MessageStatus.sent,
      isRead: false,
    );
    await _appendMessage(groupId, incoming);
    _messageUpdatesController.add(groupId);
    unawaited(restoreGroupBlobMedia(incoming));
    _newMessageNotificationController.add(
      ChatMessage(
        id: blobRef.messageId,
        peerId: groupId,
        text: fileName,
        kind: 'file',
        fileName: fileName,
        mimeType: blobRef.mimeType,
      ),
    );
    NotificationService.instance
        .showMessageNotification(
          fromPeerId: notificationSenderLabel,
          message: fileName,
          badgeCount: unreadMessagesCount(),
        )
        .catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
  }

  Future<void> _handleIncomingDirectBlobRef(
    ChatMessage msg,
    _IncomingBlobRefPayload blobRef,
  ) async {
    final peerId = msg.peerId;
    final payloadPeerId = blobRef.raw['peerId'] as String? ?? '';
    final messageId = blobRef.messageId.trim().isNotEmpty
        ? blobRef.messageId
        : msg.id;
    final fileName = (blobRef.fileName ?? '').trim();
    final blobId = blobRef.blobId.trim();
    final contentKind = blobRef.contentKind.trim();

    if (payloadPeerId.isNotEmpty && payloadPeerId != peerId) {
      developer.log(
        '[chat] direct blob ref ignored peer-mismatch payloadPeer=$payloadPeerId actualPeer=$peerId',
        name: 'chat',
      );
      return;
    }
    if (contentKind != 'media' || messageId.isEmpty || fileName.isEmpty || blobId.isEmpty) {
      return;
    }

    await ensureChatLoaded(peerId);
    final chat = _ensureChat(peerId);
    final existingIndex = chat.messages.indexWhere((message) => message.id == messageId);
    if (existingIndex == -1) {
      chat.messages.add(
        Message(
          id: messageId,
          peerId: peerId,
          text: fileName,
          senderPeerId: peerId,
          incoming: true,
          timestamp: DateTime.now(),
          kind: MessageKind.file,
          fileName: fileName,
          mimeType: blobRef.mimeType,
          transferId: _directBlobTransferId(
            peerId: peerId,
            messageId: messageId,
            blobId: blobId,
          ),
          fileSizeBytes: blobRef.fileSizeBytes,
          replyToMessageId: msg.replyToMessageId,
          replyToSenderPeerId: msg.replyToSenderPeerId,
          replyToSenderLabel: msg.replyToSenderLabel,
          replyToTextPreview: msg.replyToTextPreview,
          replyToKind: msg.replyToKind,
          transferredBytes: 0,
          transferStatus: 'Получение из relay',
          status: MessageStatus.sent,
          isRead: false,
        ),
      );
      await _persistLoadedChat(peerId);
      _messageUpdatesController.add(peerId);
      unawaited(restoreDirectBlobMedia(chat.messages.last));
    } else {
      _messageUpdatesController.add(peerId);
      unawaited(restoreDirectBlobMedia(chat.messages[existingIndex]));
    }

    _newMessageNotificationController.add(
      ChatMessage(
        id: messageId,
        peerId: peerId,
        text: fileName,
        kind: 'file',
        fileName: fileName,
        mimeType: blobRef.mimeType,
      ),
    );
    NotificationService.instance
        .showMessageNotification(
          fromPeerId: chat.name,
          message: fileName,
          badgeCount: unreadMessagesCount(),
        )
        .catchError((error) {
      developer.log('notification error: $error', name: 'chat');
    });
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
    return chats.values.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
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
    final raw = _contactsBox.get(peerId);
    if (raw is Map) {
      final name = raw['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return null;
  }

  List<Contact> getContacts() {
    final contacts = <Contact>[];
    final keys = _contactsBox.keys.map((key) => key.toString()).toList(
          growable: false,
        );
    for (final key in keys) {
      final value = _contactsBox.get(key);
      if (value is Map<String, dynamic>) {
        try {
          contacts.add(Contact.fromJson(value));
        } catch (_) {
          // Ignore malformed contact.
        }
        continue;
      }
      if (value is Map) {
        try {
          contacts.add(Contact.fromJson(Map<String, dynamic>.from(value)));
        } catch (_) {
          // Ignore malformed contact.
        }
      }
    }
    contacts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return contacts;
  }

  Future<void> addOrUpdateContact({
    required String peerId,
    required String name,
  }) async {
    final normalizedPeerId = peerId.trim();
    final normalizedName = name.trim();
    if (normalizedPeerId.isEmpty || normalizedName.isEmpty) {
      throw ArgumentError('peerId and name are required');
    }
    await _contactsBox.put(
      normalizedPeerId,
      Contact(peerId: normalizedPeerId, name: normalizedName).toJson(),
    );

    final chatList = List<Chat>.from(chats.values);
    for (final chat in chatList) {
      final updatedName = _contactNameFor(chat.peerId, fallback: chat.name);
      if (updatedName != chat.name) {
        chat.name = updatedName;
        _schedulePersistChatSummary(chat.peerId);
      }
    }
    _messageUpdatesController.add('');
  }

  Future<void> setGroupAvatar({
    required String groupId,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw StateError('Group chat not found');
    }
    final owner = (chat.ownerPeerId ?? '').trim();
    if (owner.isNotEmpty && owner != facade.peerId) {
      throw StateError('Only group owner can change avatar');
    }
    if (bytes.isEmpty) {
      throw StateError('Avatar is empty');
    }

    final stamp = DateTime.now().millisecondsSinceEpoch;
    await _saveGroupAvatarBytes(
      groupChat: chat,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: stamp,
    );
    await _broadcastGroupAvatarUpdate(
      groupChat: chat,
      bytes: bytes,
      mimeType: mimeType,
      updatedAtMs: stamp,
    );
    _messageUpdatesController.add(groupId);
  }

  String _avatarExtensionForMime(String mimeType) {
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('png')) {
      return 'png';
    }
    if (normalized.contains('webp')) {
      return 'webp';
    }
    return 'jpg';
  }

  Future<void> _saveGroupAvatarBytes({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) async {
    final ext = _avatarExtensionForMime(mimeType);
    final path = await _storage.saveMediaBytes(
      peerId: '_group_avatars',
      messageId: '${groupChat.peerId}_$updatedAtMs',
      fileName: 'group_avatar.$ext',
      bytes: bytes,
    );
    if (path.isEmpty) {
      throw StateError('Failed to save avatar');
    }

    final previous = groupChat.avatarPath;
    groupChat.avatarPath = path;
    if (previous != null && previous.isNotEmpty && previous != path) {
      await _storage.deleteMediaFile(previous);
    }
    await _persistChatSummary(groupChat);
  }

  Future<void> _broadcastGroupAvatarUpdate({
    required Chat groupChat,
    required Uint8List bytes,
    required String mimeType,
    required int updatedAtMs,
  }) async {
    final recipients = _collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      return;
    }

    final messageId = 'avatar:$updatedAtMs';
    await _ensureGroupKey(groupChat);
    final encryptedBytes = await _encryptGroupBytes(
      groupId: groupChat.peerId,
      plainBytes: bytes,
    );
    final payloadBytes = encryptedBytes ?? bytes;
    final blobId = await facade.uploadBlob(
      scopeKind: RelayBlobScopeKind.group,
      targetId: groupChat.peerId,
      fileName: 'group_avatar.${_avatarExtensionForMime(mimeType)}',
      mimeType: mimeType,
      bytes: payloadBytes,
      blobId: 'blob:${groupChat.peerId}:$messageId',
    );
    await _broadcastGroupMembersUpdate(
      groupChat: groupChat,
      recipients: recipients,
      action: 'avatar',
      changedPeerIds: const <String>[],
      avatarBlobId: blobId,
      avatarMimeType: mimeType,
      avatarFileSizeBytes: bytes.length,
      avatarUpdatedAtMs: updatedAtMs,
    );
  }

  Future<Chat> createGroupChat({
    required String name,
    required List<String> memberPeerIds,
    bool sendInvites = true,
  }) async {
    final trimmedName = name.trim();
    final invitees = memberPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final allMembers = <String>{...invitees, facade.peerId}.toList(growable: false);
    if (trimmedName.isEmpty) {
      throw ArgumentError('Group name is required');
    }
    if (invitees.isEmpty) {
      throw ArgumentError('At least one member is required');
    }

    final groupId = 'group:${DateTime.now().microsecondsSinceEpoch}';
    final chat = Chat(
      peerId: groupId,
      name: trimmedName,
      isGroup: true,
      memberPeerIds: allMembers,
      ownerPeerId: facade.peerId,
      messagesLoaded: true,
      hasMoreMessages: false,
    );
    chats[groupId] = chat;
    await _persistChatSummary(chat);
    await _ensureGroupKey(chat);
    await _syncGroupMembershipWithRelay(chat);
    if (sendInvites) {
      await _sendGroupInvites(
        chat,
        recipients: invitees,
      );
      await _rotateGroupKey(
        chat,
        recipients: allMembers,
      );
    }
    _messageUpdatesController.add(groupId);
    return chat;
  }

  Future<Chat> createDirectChat({
    required String peerId,
    String? name,
  }) async {
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

  Future<void> _sendGroupInvites(
    Chat groupChat, {
    List<String>? recipients,
  }) async {
    final targetRecipients = (recipients ?? groupChat.memberPeerIds)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != facade.peerId)
        .toSet()
        .toList(growable: false);
    if (targetRecipients.isEmpty) {
      return;
    }

    final allMembers = <String>{
      ...groupChat.memberPeerIds.map((item) => item.trim()).where((item) => item.isNotEmpty),
      facade.peerId,
    }.toList(growable: false);
    final payload = _encodeGroupInvitePayload(
      groupId: groupChat.peerId,
      groupName: groupChat.name,
      memberPeerIds: allMembers,
      ownerPeerId: groupChat.ownerPeerId ?? facade.peerId,
    );

    for (var i = 0; i < targetRecipients.length; i++) {
      final recipient = targetRecipients[i];
      final messageId = 'invite:${groupChat.peerId}:${_nextLocalMessageId()}:$i';
      try {
        developer.log(
          'group invite send start group=${groupChat.peerId} recipient=$recipient messageId=$messageId',
          name: 'chat',
        );
        await facade.sendControlMessage(
          recipient,
          kind: 'groupInvite',
          text: payload,
        );
        developer.log(
          'group invite send queued group=${groupChat.peerId} recipient=$recipient messageId=$messageId',
          name: 'chat',
        );
      } catch (error) {
        developer.log(
          'group invite send failed group=${groupChat.peerId} recipient=$recipient error=$error',
          name: 'chat',
        );
      }
    }
  }

  Future<void> addGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw ArgumentError('Group chat not found');
    }
    final additions = participantPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where((item) => !chat.memberPeerIds.contains(item))
        .toSet()
        .toList(growable: false);
    if (additions.isEmpty) {
      return;
    }
    chat.memberPeerIds = <String>{
      ...chat.memberPeerIds,
      ...additions,
    }.toList(growable: false);
    await _persistChatSummary(chat);
    await _syncGroupMembershipWithRelay(chat);
    await _rotateGroupKey(
      chat,
      recipients: chat.memberPeerIds,
    );
    await _sendGroupInvites(
      chat,
      recipients: additions,
    );
    await _broadcastGroupMembersUpdate(
      groupChat: chat,
      recipients: <String>{...chat.memberPeerIds}.toList(growable: false),
      action: 'add',
      changedPeerIds: additions,
    );
    _messageUpdatesController.add(groupId);
  }

  Future<void> removeGroupParticipants({
    required String groupId,
    required List<String> participantPeerIds,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw ArgumentError('Group chat not found');
    }
    final removals = participantPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .where((item) => item != facade.peerId)
        .where((item) => item != chat.ownerPeerId)
        .where((item) => chat.memberPeerIds.contains(item))
        .toSet()
        .toList(growable: false);
    if (removals.isEmpty) {
      return;
    }

    final previousMembers = chat.memberPeerIds.toList(growable: false);
    chat.memberPeerIds = chat.memberPeerIds
        .where((peerId) => !removals.contains(peerId))
        .toList(growable: false);
    await _persistChatSummary(chat);
    await _syncGroupMembershipWithRelay(chat);
    await _rotateGroupKey(
      chat,
      recipients: chat.memberPeerIds,
    );
    await _broadcastGroupMembersUpdate(
      groupChat: chat,
      recipients: <String>{...previousMembers}.toList(growable: false),
      action: 'remove',
      changedPeerIds: removals,
    );
    _messageUpdatesController.add(groupId);
  }

  Future<void> renameGroupChat({
    required String groupId,
    required String newName,
  }) async {
    final chat = chats[groupId];
    if (chat == null || !chat.isGroup) {
      throw ArgumentError('Group chat not found');
    }
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Group name is required');
    }
    if (!chat.memberPeerIds.contains(facade.peerId)) {
      throw StateError('Only group members can rename group chat');
    }
    chat.name = trimmed;
    await _persistChatSummary(chat);
    await _broadcastGroupMembersUpdate(
      groupChat: chat,
      recipients: <String>{...chat.memberPeerIds}.toList(growable: false),
      action: 'rename',
      changedPeerIds: const <String>[],
    );
    _messageUpdatesController.add(groupId);
  }

  Future<void> sendMessage(
    String peerId,
    String text,
    {Message? replyTo}
  ) async {
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
    developer.log(
      'queue:add peer=$peerId messageId=$messageId file=$fileName size=$resolvedSize',
      name: 'chat',
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

    _fileSendQueue.add(
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
    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        facade.peerId,
      }.toList(growable: false);
      await _persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      await _replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Вы больше не участник чата',
        ),
      );
      _setStatus(groupChat.peerId, ChatConnectionStatus.error);
      return;
    }

    final recipients = _collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      await _replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Нет участников для отправки',
        ),
      );
      return;
    }

    _setStatus(groupChat.peerId, ChatConnectionStatus.connecting);
    await _updateFileProgress(
      groupChat.peerId,
      messageId,
      sentBytes: 0,
      totalBytes: fileSizeBytes,
      statusText: 'Подготовка',
    );

    Uint8List? resolvedBytes = fileBytes;
    if (resolvedBytes == null && filePath != null && filePath.isNotEmpty) {
      resolvedBytes = Uint8List.fromList(
        await File(filePath).readAsBytes(),
      );
    }
    if (resolvedBytes == null) {
      await _replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Не удалось прочитать файл',
        ),
      );
      _setStatus(groupChat.peerId, ChatConnectionStatus.error);
      return;
    }

    var hasFailure = false;
    String? blobId;
    try {
      await _ensureGroupKey(groupChat);
      final encryptedBytes = await _encryptGroupBytes(
        groupId: groupChat.peerId,
        plainBytes: resolvedBytes,
      );
      final payloadBytes = encryptedBytes ?? resolvedBytes;
      await _updateFileProgress(
        groupChat.peerId,
        messageId,
        sentBytes: 0,
        totalBytes: fileSizeBytes,
        statusText: 'Загрузка в relay',
      );
      blobId = await facade.uploadBlob(
        scopeKind: RelayBlobScopeKind.group,
        targetId: groupChat.peerId,
        fileName: fileName,
        mimeType: mimeType,
        bytes: payloadBytes,
        blobId: 'blob:$messageId',
        onProgress: ({
          required int sentBytes,
          required int totalBytes,
          required String status,
        }) {
          unawaited(
            _updateFileProgress(
              groupChat.peerId,
              messageId,
              sentBytes: sentBytes,
              totalBytes: totalBytes,
              statusText: status,
            ),
          );
        },
      );
      final blobRefPayload = _encodeGroupBlobRefPayload(
        groupChat: groupChat,
        messageId: messageId,
        contentKind: 'media',
        fileName: fileName,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
        blobId: blobId,
      );
      final securePayload = await _encryptGroupText(
        groupId: groupChat.peerId,
        plainText: blobRefPayload,
      );
      final payload = securePayload ??
          _encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: messageId,
            text: blobRefPayload,
          );
      await facade.sendPayload(
        groupChat.peerId,
        targetKind: ChatPayloadTargetKind.group,
        recipients: recipients,
        text: payload,
        messageId: messageId,
        kind: 'text',
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: _replySenderLabel(groupChat.peerId, replyTo),
        replyToTextPreview: _replyTextPreview(replyTo),
        replyToKind: _replyKind(replyTo),
      );
      await _updateFileProgress(
        groupChat.peerId,
        messageId,
        sentBytes: fileSizeBytes,
        totalBytes: fileSizeBytes,
        statusText: 'Отправлено',
      );
    } catch (_) {
      hasFailure = true;
    }

    String? localPath;
    if (filePath != null && filePath.isNotEmpty) {
      localPath = await _storage.saveMediaFile(
        peerId: groupChat.peerId,
        messageId: messageId,
        fileName: fileName,
        sourcePath: filePath,
      );
    } else if (fileBytes != null) {
      localPath = await _storage.saveMediaBytes(
        peerId: groupChat.peerId,
        messageId: messageId,
        fileName: fileName,
        bytes: fileBytes,
      );
    }

    await _replaceMessage(
      groupChat.peerId,
      messageId,
      (current) => ChatMessageCopy.copy(
        current,
        transferId: blobId != null
            ? _groupBlobTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
                blobId: blobId,
              )
            : _groupFileTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
              ),
        localFilePath: (localPath != null && localPath.isNotEmpty)
            ? localPath
            : current.localFilePath,
        fileDataBase64: null,
        transferredBytes: hasFailure ? current.transferredBytes : null,
        sendProgress: hasFailure ? current.sendProgress : null,
        transferStatus: hasFailure ? 'Ошибка отправки' : null,
        status: hasFailure ? MessageStatus.failed : MessageStatus.sent,
      ),
    );
    _clearProgressUpdate(groupChat.peerId, messageId);

    _setStatus(
      groupChat.peerId,
      hasFailure ? ChatConnectionStatus.error : ChatConnectionStatus.connected,
      error: hasFailure ? 'Failed to send group media' : null,
    );
    _messageUpdatesController.add(groupChat.peerId);
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
        final payload = _encodeGroupDeletePayload(
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

  Future<void> _drainFileQueue() async {
    if (_fileSendInFlight) {
      developer.log('queue:skip drain already in flight', name: 'chat');
      return;
    }

    _fileSendInFlight = true;
    try {
      while (_fileSendQueue.isNotEmpty) {
        final item = _fileSendQueue.removeFirst();
        developer.log(
          'queue:start peer=${item.peerId} messageId=${item.messageId} remaining=${_fileSendQueue.length}',
          name: 'chat',
        );
        if (_cancelledFileTransfers.remove(item.messageId)) {
          // Item was cancelled before it started processing, remove it completely
          await _removeMessageWithMediaCleanup(item.peerId, item.messageId);
          _refreshQueuedFileStatuses();
          continue;
        }
        _activeFileTransferId = item.messageId;
        _refreshQueuedFileStatuses();
        await _sendFileAsync(
          item.peerId,
          messageId: item.messageId,
          fileName: item.fileName,
          fileBytes: item.fileBytes,
          filePath: item.filePath,
          fileSizeBytes: item.fileSizeBytes,
          mimeType: item.mimeType,
        );
        _activeFileTransferId = null;
        developer.log(
          'queue:done peer=${item.peerId} messageId=${item.messageId}',
          name: 'chat',
        );
        _refreshQueuedFileStatuses();
      }
    } finally {
      _activeFileTransferId = null;
      _fileSendInFlight = false;
      developer.log('queue:idle', name: 'chat');
      _refreshQueuedFileStatuses();
    }
  }

  Future<void> _sendMessageAsync(String peerId, Message message) async {
    _setStatus(peerId, ChatConnectionStatus.connecting);
    try {
      await facade.sendPayload(
        peerId,
        text: message.text,
        messageId: message.id,
        replyToMessageId: message.replyToMessageId,
        replyToSenderPeerId: message.replyToSenderPeerId,
        replyToSenderLabel: message.replyToSenderLabel,
        replyToTextPreview: message.replyToTextPreview,
        replyToKind: message.replyToKind,
      );
      await _updateMessageStatusById(peerId, message.id, MessageStatus.sent);
      _setStatus(peerId, ChatConnectionStatus.connected);
    } catch (e) {
      await _updateMessageStatusById(peerId, message.id, MessageStatus.failed);
      _setStatus(peerId, ChatConnectionStatus.error, error: e.toString());
    }
  }

  Future<void> _sendGroupMessageAsync(Chat groupChat, Message message) async {
    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        facade.peerId,
      }.toList(growable: false);
      await _persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(facade.peerId)) {
      await _updateMessageStatusById(groupChat.peerId, message.id, MessageStatus.failed);
      _setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Вы больше не участник этого чата',
      );
      return;
    }

    final recipients = _collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      await _updateMessageStatusById(groupChat.peerId, message.id, MessageStatus.failed);
      _setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Group has no members',
      );
      return;
    }

    _setStatus(groupChat.peerId, ChatConnectionStatus.connecting);
    var hasFailure = false;
    try {
      await _ensureGroupKey(groupChat);
      final plainBytes = Uint8List.fromList(utf8.encode(message.text));
      final encryptedBytes = await _encryptGroupBytes(
        groupId: groupChat.peerId,
        plainBytes: plainBytes,
      );
      final payloadBytes = encryptedBytes ?? plainBytes;
      final blobId = await facade.uploadBlob(
        scopeKind: RelayBlobScopeKind.group,
        targetId: groupChat.peerId,
        fileName: 'text.txt',
        mimeType: 'text/plain',
        bytes: payloadBytes,
        blobId: 'blob:${message.id}',
      );
      final blobRefPayload = _encodeGroupBlobRefPayload(
        groupChat: groupChat,
        messageId: message.id,
        contentKind: 'text',
        textPreview: message.text,
        blobId: blobId,
      );
      final securePayload = await _encryptGroupText(
        groupId: groupChat.peerId,
        plainText: blobRefPayload,
      );
      final payload = securePayload ??
          _encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: message.id,
            text: blobRefPayload,
          );
      await facade.sendPayload(
        groupChat.peerId,
        targetKind: ChatPayloadTargetKind.group,
        recipients: recipients,
        text: payload,
        messageId: message.id,
        kind: 'text',
        replyToMessageId: message.replyToMessageId,
        replyToSenderPeerId: message.replyToSenderPeerId,
        replyToSenderLabel: message.replyToSenderLabel,
        replyToTextPreview: message.replyToTextPreview,
        replyToKind: message.replyToKind,
      );
    } catch (_) {
      const fanoutConcurrency = 6;
      final payload = _encodeGroupMessagePayload(
        groupChat: groupChat,
        messageId: message.id,
        text: message.text,
      );
      for (var batchStart = 0;
          batchStart < recipients.length;
          batchStart += fanoutConcurrency) {
        final batchEnd = (batchStart + fanoutConcurrency > recipients.length)
            ? recipients.length
            : batchStart + fanoutConcurrency;
        final batch = recipients.sublist(batchStart, batchEnd);
        final results = await Future.wait(
          batch.asMap().entries.map((entry) async {
            final recipient = entry.value;
            final recipientIndex = batchStart + entry.key;
            final perRecipientMessageId = '${message.id}:$recipientIndex';
            try {
              await facade.sendPayload(
                recipient,
                text: payload,
                messageId: perRecipientMessageId,
                replyToMessageId: message.replyToMessageId,
                replyToSenderPeerId: message.replyToSenderPeerId,
                replyToSenderLabel: message.replyToSenderLabel,
                replyToTextPreview: message.replyToTextPreview,
                replyToKind: message.replyToKind,
              );
              return true;
            } catch (_) {
              return false;
            }
          }),
        );
        if (results.any((ok) => !ok)) {
          hasFailure = true;
        }
      }
    }

    if (hasFailure) {
      await _updateMessageStatusById(groupChat.peerId, message.id, MessageStatus.failed);
      _setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Failed to send to some group members',
      );
      return;
    }

    await _updateMessageStatusById(groupChat.peerId, message.id, MessageStatus.sent);
    _setStatus(groupChat.peerId, ChatConnectionStatus.connected);
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
    final payload = _encodeGroupMembersPayload(
      groupChat: groupChat,
      action: action,
      changedPeerIds: changedPeerIds,
      avatarBlobId: avatarBlobId,
      avatarMimeType: avatarMimeType,
      avatarFileSizeBytes: avatarFileSizeBytes,
      avatarUpdatedAtMs: avatarUpdatedAtMs,
    );
    final targets = recipients
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != facade.peerId)
        .toSet()
        .toList(growable: false);
    for (final peerId in targets) {
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'groupMembers',
          text: payload,
        );
      } catch (_) {
        // best effort
      }
    }
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
    await _updateFileProgress(
      peerId,
      messageId,
      sentBytes: 0,
      totalBytes: fileSizeBytes,
      statusText: 'Подготовка',
    );
    _setStatus(peerId, ChatConnectionStatus.connecting);
    try {
      Uint8List? resolvedBytes = fileBytes;
      if (resolvedBytes == null && filePath != null && filePath.isNotEmpty) {
        resolvedBytes = Uint8List.fromList(await File(filePath).readAsBytes());
      }
      if (resolvedBytes == null) {
        throw StateError('Не удалось прочитать файл');
      }
      if (_cancelledFileTransfers.contains(messageId)) {
        throw _FileTransferCancelledException();
      }

      final blobId = await facade.uploadBlob(
        scopeKind: RelayBlobScopeKind.direct,
        targetId: peerId,
        fileName: fileName,
        mimeType: mimeType,
        bytes: resolvedBytes,
        blobId: 'blob:$messageId',
        onProgress: ({
          required int sentBytes,
          required int totalBytes,
          required String status,
        }) {
          unawaited(
            _updateFileProgress(
              peerId,
              messageId,
              sentBytes: sentBytes,
              totalBytes: totalBytes,
              statusText: status,
            ),
          );
        },
      );
      if (_cancelledFileTransfers.contains(messageId)) {
        throw _FileTransferCancelledException();
      }

      final blobRefPayload = _encodeDirectBlobRefPayload(
        peerId: peerId,
        messageId: messageId,
        contentKind: 'media',
        fileName: fileName,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
        blobId: blobId,
      );
      await facade.sendPayload(
        peerId,
        text: blobRefPayload,
        messageId: messageId,
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: _replySenderLabel(peerId, replyTo),
        replyToTextPreview: _replyTextPreview(replyTo),
        replyToKind: _replyKind(replyTo),
      );

      String? localPath;

      if (filePath != null && filePath.isNotEmpty) {
        localPath = await _storage.saveMediaFile(
          peerId: peerId,
          messageId: messageId,
          fileName: fileName,
          sourcePath: filePath,
        );
      } else if (fileBytes != null) {
        localPath = await _storage.saveMediaBytes(
          peerId: peerId,
          messageId: messageId,
          fileName: fileName,
          bytes: fileBytes,
        );
      }

      await _replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferId: _directBlobTransferId(
            peerId: peerId,
            messageId: messageId,
            blobId: blobId,
          ),
          transferredBytes: null,
          sendProgress: null,
          transferStatus: null,
          localFilePath: (localPath != null && localPath.isNotEmpty)
              ? localPath
              : current.localFilePath,
          fileDataBase64: null,
          status: MessageStatus.sent,
        ),
      );
      _clearProgressUpdate(peerId, messageId);

      // Double-check if was cancelled and no bytes transferred, remove it
      if (_cancelledFileTransfers.remove(messageId)) {
        final chat = chats[peerId];
        if (chat != null && chat.messagesLoaded) {
          Message? message;
          for (final m in chat.messages) {
            if (m.id == messageId) {
              message = m;
              break;
            }
          }
          if (message != null && (message.transferredBytes ?? 0) == 0) {
            await _removeMessageWithMediaCleanup(peerId, messageId);
            _setStatus(peerId, ChatConnectionStatus.connected);
            NotificationService.instance.setBadgeCount(unreadMessagesCount());
            _messageUpdatesController.add(peerId);
            return;
          }
        }
      }

      _setStatus(peerId, ChatConnectionStatus.connected);
      NotificationService.instance.setBadgeCount(unreadMessagesCount());
      _messageUpdatesController.add(peerId);
    } catch (e) {
      final wasCancelled = _cancelledFileTransfers.remove(messageId);

      // If transfer was cancelled, message was already removed from chat
      // No need to update it
      if (wasCancelled) {
        _setStatus(peerId, ChatConnectionStatus.connected);
        _messageUpdatesController.add(peerId);
        return;
      }

      // For other errors, mark message as failed
      await _replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferredBytes: 0,
          sendProgress: 0.0,
          transferStatus: 'Ошибка отправки',
          status: MessageStatus.failed,
        ),
      );
      _clearProgressUpdate(peerId, messageId);
      _setStatus(peerId, ChatConnectionStatus.error, error: e.toString());
      _messageUpdatesController.add(peerId);
    }
  }

  Future<void> cancelFileTransfer(String peerId, String messageId) async {
    final queuedBefore = _fileSendQueue.length;
    _fileSendQueue.removeWhere((item) => item.messageId == messageId);
    final removedFromQueue = _fileSendQueue.length != queuedBefore;

    // Mark for cancellation immediately
    _cancelledFileTransfers.add(messageId);

    // Remove message from chat immediately
    await _removeMessageWithMediaCleanup(peerId, messageId);
    if (removedFromQueue) {
      _refreshQueuedFileStatuses();
    }
    _messageUpdatesController.add(peerId);
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
      chat.name = _contactNameFor(chat.peerId, fallback: chat.name);
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
              ChatMessageCopy.copy(
                message,
                localFilePath: null,
              ),
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
        : await _readStoredMessages(peerId);
    Message? match;
    for (final message in messages) {
      if (message.id == messageId) {
        match = message;
        break;
      }
    }
    await _deleteManagedMediaForMessage(match);
    await _removeMessage(peerId, messageId);
    NotificationService.instance.setBadgeCount(unreadMessagesCount());
    _messageUpdatesController.add(peerId);
  }

  Future<void> deleteChat(String peerId) async {
    final loadedChat = chats[peerId];
    final storedMessages = loadedChat?.messagesLoaded == true
        ? List<Message>.from(loadedChat!.messages)
        : await _readStoredMessages(peerId);

    for (final message in storedMessages) {
      await _storage.deleteMediaFile(message.localFilePath);
    }
    await _storage.deletePeerMediaDirectory(peerId);
    await _storage.deleteChatMessages(peerId);
    await _storage.deleteChatSummaryMap(peerId);
    await _groupKeyService.deleteGroupKeys(peerId);
    if (_groupMetaByGroupId.remove(peerId) != null) {
      await _persistGroupMetaToSettings();
    }

    chats.remove(peerId);
    _fileSendQueue.removeWhere((item) => item.peerId == peerId);
    _cancelledFileTransfers.removeWhere((messageId) {
      return storedMessages.any((message) => message.id == messageId);
    });
    if (_activeFileTransferId != null &&
        storedMessages.any((message) => message.id == _activeFileTransferId)) {
      _cancelledFileTransfers.add(_activeFileTransferId!);
    }

    NotificationService.instance.setBadgeCount(unreadMessagesCount());
    await _runGroupKeyGc();
    _messageUpdatesController.add(peerId);
  }

  Future<void> markChatAsRead(String peerId) async {
    try {
      final chat = chats[peerId];
      if (chat == null) {
        NotificationService.instance.setBadgeCount(unreadMessagesCount());
        return;
      }

      if (chat.messagesLoaded) {
        var changed = false;
        for (var i = 0; i < chat.messages.length; i++) {
          final message = chat.messages[i];
          if (message.incoming && !message.isRead) {
            chat.messages[i] = ChatMessageCopy.copy(message, isRead: true);
            changed = true;
          }
        }
        if (changed) {
          await _persistLoadedChat(peerId);
          _messageUpdatesController.add(peerId);
        }
      } else {
        final stored = await _readStoredMessages(peerId);
        var changed = false;
        for (var i = 0; i < stored.length; i++) {
          final message = stored[i];
          if (message.incoming && !message.isRead) {
            stored[i] = ChatMessageCopy.copy(message, isRead: true);
            changed = true;
          }
        }
        if (changed) {
          _refreshSummaryFromMessages(chat, stored);
          await _writeStoredMessages(peerId, stored);
          await _persistChatSummary(chat);
          _messageUpdatesController.add(peerId);
        }
      }

      NotificationService.instance.setBadgeCount(unreadMessagesCount());
    } catch (e, stack) {
      developer.log('[chat] markChatAsRead failed peer=$peerId error=$e\n$stack', name: 'chat');
    }
  }

  Future<void> _updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  ) async {
    await _replaceMessage(
      peerId,
      messageId,
      (current) {
        var progress = current.sendProgress;
        var transferStatus = current.transferStatus;
        if (status == MessageStatus.sent) {
          progress = 1.0;
          transferStatus = 'Отправлено';
        } else if (status == MessageStatus.failed) {
          progress = 0;
          transferStatus = current.transferStatus == 'Отменено'
              ? 'Отменено'
              : 'Ошибка отправки';
        }
        return ChatMessageCopy.copy(
          current,
          status: status,
          sendProgress: progress,
          transferStatus: transferStatus,
        );
      },
    );
    NotificationService.instance.setBadgeCount(unreadMessagesCount());
    _messageUpdatesController.add(peerId);
  }

  Future<void> _updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    final key = '$peerId::$messageId';
    final now = DateTime.now();
    final pending = _pendingProgressUpdates[key];
    if (pending != null) {
      pending
        ..sentBytes = sentBytes
        ..totalBytes = totalBytes
        ..statusText = statusText;
      final elapsed = now.difference(pending.lastAppliedAt);
      if (elapsed >= _progressThrottleInterval) {
        pending.timer?.cancel();
        pending.timer = null;
        await _applyFileProgressUpdate(
          peerId,
          messageId,
          sentBytes: pending.sentBytes,
          totalBytes: pending.totalBytes,
          statusText: pending.statusText,
        );
        pending.lastAppliedAt = DateTime.now();
        _pendingProgressUpdates[key] = pending;
        return;
      }
      pending.timer ??= Timer(
        _progressThrottleInterval - elapsed,
        () {
          final currentPending = _pendingProgressUpdates[key];
          if (currentPending == null) {
            return;
          }
          currentPending.timer = null;
          unawaited(
            _applyFileProgressUpdate(
              peerId,
              messageId,
              sentBytes: currentPending.sentBytes,
              totalBytes: currentPending.totalBytes,
              statusText: currentPending.statusText,
            ),
          );
          currentPending.lastAppliedAt = DateTime.now();
          _pendingProgressUpdates[key] = currentPending;
        },
      );
      _pendingProgressUpdates[key] = pending;
      return;
    }

    _pendingProgressUpdates[key] = _PendingProgressUpdate(
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
      lastAppliedAt: now,
    );
    await _applyFileProgressUpdate(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
    );
  }

  void _clearProgressUpdate(String peerId, String messageId) {
    final key = '$peerId::$messageId';
    final pending = _pendingProgressUpdates.remove(key);
    pending?.timer?.cancel();
  }

  void _clearIncomingMediaRetry(String peerId, String messageId) {
    final key = '$peerId::$messageId';
    _incomingMediaRetryAttempts.remove(key);
    final timer = _incomingMediaRetryTimers.remove(key);
    timer?.cancel();
  }

  void _scheduleIncomingMediaRetry(String peerId, String messageId) {
    final key = '$peerId::$messageId';
    if (_incomingMediaRetryTimers.containsKey(key)) {
      return;
    }
    final attempts = (_incomingMediaRetryAttempts[key] ?? 0) + 1;
    if (attempts > _incomingMediaRetryMaxAttempts) {
      return;
    }
    _incomingMediaRetryAttempts[key] = attempts;
    _incomingMediaRetryTimers[key] = Timer(_incomingMediaRetryDelay, () async {
      _incomingMediaRetryTimers.remove(key);
      final message = await _findMessage(peerId, messageId);
      if (message == null ||
          !message.incoming ||
          message.kind != MessageKind.file ||
          (message.localFilePath?.isNotEmpty ?? false)) {
        _clearIncomingMediaRetry(peerId, messageId);
        return;
      }
      try {
        await _replaceMessage(
          peerId,
          messageId,
          (current) => ChatMessageCopy.copy(
            current,
            transferredBytes: 0,
            sendProgress: null,
            transferStatus: 'Повторная загрузка',
          ),
        );
        if ((message.transferId ?? '').startsWith('dirblob:')) {
          await restoreDirectBlobMedia(message);
        } else if ((message.transferId ?? '').startsWith('grpblob:')) {
          await restoreGroupBlobMedia(message);
        }
      } catch (_) {
        // Best effort: a later retry or manual tap can continue recovery.
      }
    });
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
      final nextProgress = (totalBytes == null || totalBytes <= 0)
          ? null
          : (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();
      final changed = msg.transferredBytes != sentBytes ||
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
    if (_fileSendQueue.isEmpty) {
      return;
    }

    final queueSnapshot = _fileSendQueue.toList(growable: false);
    final total = queueSnapshot.length;
    final changedPeers = <String>{};
    for (var index = 0; index < queueSnapshot.length; index++) {
      final item = queueSnapshot[index];
      final chat = chats[item.peerId];
      if (chat == null || !chat.messagesLoaded) {
        continue;
      }
      for (var i = 0; i < chat.messages.length; i++) {
        final msg = chat.messages[i];
        if (msg.id != item.messageId) {
          continue;
        }
        if (msg.status != MessageStatus.sending) {
          break;
        }
        final nextStatus = 'Ожидает отправки (${index + 1} из $total)';
        if (msg.transferStatus != nextStatus || msg.sendProgress != 0.02) {
          chat.messages[i] = ChatMessageCopy.copy(
            msg,
            transferStatus: nextStatus,
            sendProgress: 0.02,
          );
          changedPeers.add(item.peerId);
        }
        break;
      }
    }

    if (changedPeers.isEmpty) {
      return;
    }

    for (final peerId in changedPeers) {
      _schedulePersistLoadedChat(peerId);
      _messageUpdatesController.add(peerId);
    }
  }

  Future<String?> restoreMediaFromEmbedded(String peerId, Message message) {
    return ChatControllerMedia.restoreMediaFromEmbedded(
      storage: _storage,
      peerId: peerId,
      message: message,
      replaceMessage: _replaceMessage,
    );
  }

  Future<String?> restoreGroupBlobMedia(Message message) async {
    final route = _parseGroupBlobTransferId(message.transferId);
    if (route == null) {
      return null;
    }

    return _restoreMediaFromRelay(
      peerId: route.groupId,
      messageId: route.messageId,
      blobId: route.blobId,
      fileName: message.fileName,
      downloadBlob: (onProgress) => _downloadBlobWithRetry(
        attempts: 2,
        retryDelay: const Duration(milliseconds: 500),
        operation: () => facade.downloadBlob(
          route.blobId,
          onProgress: onProgress,
        ),
      ),
      transformPayload: (blob) async {
        await _replaceMessage(
          route.groupId,
          route.messageId,
          (current) => ChatMessageCopy.copy(
            current,
            transferredBytes: blob.sizeBytes,
            sendProgress: 0.85,
            transferStatus: 'Расшифровка',
          ),
        );
        return _decodeGroupBlobBytes(
          groupId: route.groupId,
          encryptedBytes: blob.payload,
        );
      },
    );
  }

  String _encodeDirectBlobRefPayload({
    required String peerId,
    required String messageId,
    required String contentKind,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    required String blobId,
  }) {
    final payload = <String, dynamic>{
      'type': 'direct_blob_ref',
      'v': 1,
      'peerId': facade.peerId,
      'counterpartyPeerId': peerId,
      'messageId': messageId,
      'contentKind': contentKind,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSizeBytes': fileSizeBytes,
      'blobId': blobId,
      'senderPeerId': facade.peerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$_directBlobRefPrefix${jsonEncode(payload)}';
  }

  Map<String, dynamic>? _decodeDirectBlobRefPayload(String text) {
    if (!text.startsWith(_directBlobRefPrefix)) {
      return null;
    }
    try {
      final raw = text.substring(_directBlobRefPrefix.length);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<String?> restoreDirectBlobMedia(Message message) async {
    final route = _parseDirectBlobTransferId(message.transferId);
    if (route == null) {
      return null;
    }

    return _restoreMediaFromRelay(
      peerId: route.peerId,
      messageId: route.messageId,
      blobId: route.blobId,
      fileName: message.fileName,
      downloadBlob: (onProgress) => _downloadBlobWithRetry(
        attempts: 2,
        retryDelay: const Duration(milliseconds: 500),
        operation: () => facade
            .downloadBlob(
              route.blobId,
              onProgress: onProgress,
            )
            .timeout(const Duration(seconds: 20)),
      ),
    );
  }

  Future<String?> _restoreMediaFromRelay({
    required String peerId,
    required String messageId,
    required String blobId,
    required String? fileName,
    required _RelayBlobDownloadOperation downloadBlob,
    Future<Uint8List> Function(RelayBlobDownload blob)? transformPayload,
  }) async {
    try {
      await _replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferredBytes: 0,
          sendProgress: null,
          transferStatus: 'Получение из relay',
        ),
      );
      final blob = await downloadBlob(({
          required int receivedBytes,
          required int totalBytes,
          required String status,
        }) {
          unawaited(
            _updateFileProgress(
              peerId,
              messageId,
              sentBytes: receivedBytes,
              totalBytes: totalBytes <= 0 ? null : totalBytes,
              statusText: status,
            ),
          );
        });
      final bytes = transformPayload != null
          ? await transformPayload(blob)
          : blob.payload;
      await _replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferredBytes: bytes.length,
          sendProgress: 0.95,
          transferStatus: 'Сохранение',
        ),
      );
      final path = await _storage.saveMediaBytes(
        peerId: peerId,
        messageId: messageId,
        fileName: fileName ?? blob.fileName,
        bytes: bytes,
      );
      if (path.isEmpty) {
        return null;
      }
      _clearProgressUpdate(peerId, messageId);
      await _replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          localFilePath: path,
          fileDataBase64: null,
          transferredBytes: null,
          sendProgress: null,
          transferStatus: null,
        ),
      );
      _clearIncomingMediaRetry(peerId, messageId);
      _messageUpdatesController.add(peerId);
      return path;
    } catch (_) {
      _clearProgressUpdate(peerId, messageId);
      await _replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          sendProgress: 0.0,
          transferStatus: 'Ошибка загрузки',
        ),
      );
      final failedMessage = await _findMessage(peerId, messageId);
      if (failedMessage != null &&
          failedMessage.incoming &&
          failedMessage.kind == MessageKind.file &&
          (failedMessage.localFilePath?.isNotEmpty != true)) {
        _scheduleIncomingMediaRetry(peerId, messageId);
      } else {
        _clearIncomingMediaRetry(peerId, messageId);
      }
      _messageUpdatesController.add(peerId);
      return null;
    }
  }

  Future<RelayBlobDownload> _downloadBlobWithRetry({
    required int attempts,
    required Duration retryDelay,
    required Future<RelayBlobDownload> Function() operation,
  }) async {
    assert(attempts > 0);
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        if (attempt + 1 < attempts) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    throw lastError ?? Exception('blob-fetch failed for $attempts attempts');
  }

  Future<Uint8List> _decodeGroupBlobBytes({
    required String groupId,
    required Uint8List encryptedBytes,
  }) async {
    final decrypted = await _decryptGroupBytes(
      groupId: groupId,
      encryptedBytes: encryptedBytes,
    );
    return decrypted ?? encryptedBytes;
  }

  Future<String?> _restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  }) async {
    try {
      final blob = await facade.downloadBlob(blobId);
      final bytes = await _decodeGroupBlobBytes(
        groupId: groupId,
        encryptedBytes: blob.payload,
      );
      return utf8.decode(bytes);
    } catch (_) {
      return fallback;
    }
  }

  void _setStatus(
    String peerId,
    ChatConnectionStatus status, {
    String? error,
  }) {
    _connectionStatus[peerId] = status;
    _connectionErrors[peerId] = error;
    _connectionStatusController.add(peerId);
  }

  Future<void> dispose() async {
    final pendingUpdates =
        List<_PendingProgressUpdate>.from(_pendingProgressUpdates.values);
    for (final pending in pendingUpdates) {
      pending.timer?.cancel();
    }
    _pendingProgressUpdates.clear();
    final retryTimers = List<Timer>.from(_incomingMediaRetryTimers.values);
    for (final timer in retryTimers) {
      timer.cancel();
    }
    _incomingMediaRetryTimers.clear();
    _incomingMediaRetryAttempts.clear();
    await _peerConnectedSub?.cancel();
    await _peerDisconnectedSub?.cancel();
    await _connectionStatusController.close();
    await _messageUpdatesController.close();
    await _newMessageNotificationController.close();
  }

  Stream<List<String>> get discoveredPeersStream => facade.discoveredPeersStream;

  Future<void> startCall(String peerId) => facade.startCall(peerId);
}

Future<Uint8List?> _encryptGroupBytesIsolate({
  required String groupId,
  required String keyBase64,
  required Uint8List plainBytes,
}) async {
  final keyBytes = base64Decode(keyBase64);
  if (keyBytes.length != 32) {
    return null;
  }
  final cipher = AesGcm.with256bits();
  final secretKey = SecretKey(keyBytes);
  final nonce = cipher.newNonce();
  final secretBox = await cipher.encrypt(
    plainBytes,
    secretKey: secretKey,
    nonce: nonce,
  );
  final groupIdBytes = Uint8List.fromList(utf8.encode(groupId));
  final nonceBytes = Uint8List.fromList(secretBox.nonce);
  final macBytes = Uint8List.fromList(secretBox.mac.bytes);
  final cipherBytes = Uint8List.fromList(secretBox.cipherText);
  if (groupIdBytes.length > 0xFFFF ||
      nonceBytes.length > 0xFF ||
      macBytes.length > 0xFF) {
    return null;
  }

  final totalLength = _groupMediaCipherMagicV2.length +
      1 +
      1 +
      2 +
      groupIdBytes.length +
      nonceBytes.length +
      macBytes.length +
      cipherBytes.length;
  final packed = Uint8List(totalLength);
  final data = ByteData.sublistView(packed);
  var offset = 0;
  for (final byte in _groupMediaCipherMagicV2) {
    packed[offset++] = byte;
  }
  packed[offset++] = nonceBytes.length;
  packed[offset++] = macBytes.length;
  data.setUint16(offset, groupIdBytes.length, Endian.big);
  offset += 2;
  packed.setRange(offset, offset + groupIdBytes.length, groupIdBytes);
  offset += groupIdBytes.length;
  packed.setRange(offset, offset + nonceBytes.length, nonceBytes);
  offset += nonceBytes.length;
  packed.setRange(offset, offset + macBytes.length, macBytes);
  offset += macBytes.length;
  packed.setRange(offset, offset + cipherBytes.length, cipherBytes);
  return packed;
}

Future<Uint8List?> _decryptGroupBytesIsolate({
  required String groupId,
  required String keyBase64,
  required Uint8List encryptedBytes,
}) async {
  final keyBytes = base64Decode(keyBase64);
  if (keyBytes.length != 32) {
    return null;
  }
  final cipher = AesGcm.with256bits();
  final secretKey = SecretKey(keyBytes);

  if (encryptedBytes.length >= _groupMediaCipherMagicV2.length + 1 + 1 + 2 + 1) {
    var magicMatch = true;
    for (var i = 0; i < _groupMediaCipherMagicV2.length; i++) {
      if (encryptedBytes[i] != _groupMediaCipherMagicV2[i]) {
        magicMatch = false;
        break;
      }
    }
    if (magicMatch) {
      var offset = _groupMediaCipherMagicV2.length;
      final nonceLen = encryptedBytes[offset++];
      final macLen = encryptedBytes[offset++];
      final data = ByteData.sublistView(encryptedBytes);
      final groupIdLen = data.getUint16(offset, Endian.big);
      offset += 2;
      final minLength = _groupMediaCipherMagicV2.length +
          1 +
          1 +
          2 +
          groupIdLen +
          nonceLen +
          macLen;
      if (encryptedBytes.length > minLength) {
        final groupIdEnd = offset + groupIdLen;
        if (groupIdEnd <= encryptedBytes.length) {
          final payloadGroupId = utf8.decode(
            encryptedBytes.sublist(offset, groupIdEnd),
            allowMalformed: true,
          );
          if (payloadGroupId == groupId) {
            offset = groupIdEnd;
            final nonceEnd = offset + nonceLen;
            final macEnd = nonceEnd + macLen;
            if (macEnd <= encryptedBytes.length) {
              final nonce = encryptedBytes.sublist(offset, nonceEnd);
              final macBytes = encryptedBytes.sublist(nonceEnd, macEnd);
              final payloadCipher = encryptedBytes.sublist(macEnd);
              if (payloadCipher.isNotEmpty) {
                final secretBox = SecretBox(
                  payloadCipher,
                  nonce: nonce,
                  mac: Mac(macBytes),
                );
                final clear = await cipher.decrypt(
                  secretBox,
                  secretKey: secretKey,
                );
                return Uint8List.fromList(clear);
              }
            }
          }
        }
      }
    }
  }

  Map<String, dynamic> payload;
  try {
    final decoded = jsonDecode(utf8.decode(encryptedBytes));
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    } else if (decoded is Map) {
      payload = Map<String, dynamic>.from(decoded);
    } else {
      return null;
    }
  } catch (_) {
    return null;
  }

  final payloadGroupId = (payload['groupId'] as String? ?? '').trim();
  if (payloadGroupId != groupId) {
    return null;
  }
  final nonceRaw = payload['nonce'] as String?;
  final cipherRaw = payload['cipher'] as String?;
  final macRaw = payload['mac'] as String?;
  if (nonceRaw == null || cipherRaw == null || macRaw == null) {
    return null;
  }

  final secretBox = SecretBox(
    base64Decode(cipherRaw),
    nonce: base64Decode(nonceRaw),
    mac: Mac(base64Decode(macRaw)),
  );
  final clear = await cipher.decrypt(
    secretBox,
    secretKey: secretKey,
  );
  return Uint8List.fromList(clear);
}
