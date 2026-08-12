import '../../core/node/node_facade.dart';
import '../../core/runtime/storage_service.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_file_queue_service.dart';
import 'chat_group_outbound_coordinator.dart';
import 'chat_repository.dart';
import 'chat_summary_service.dart';
import 'chat_controller_parts.dart';

class ChatCleanupCoordinator {
  const ChatCleanupCoordinator({
    required NodeFacade facade,
    required StorageService storage,
    required GroupKeyService groupKeyService,
    required ChatRepository chatRepository,
    required ChatSummaryService chatSummaryService,
    required ChatFileQueueService chatFileQueueService,
    required ChatGroupOutboundCoordinator groupOutboundCoordinator,
    required Map<String, Chat> chats,
    required Future<void> Function(Message? message)
    deleteManagedMediaForMessage,
    required Future<bool> Function(String peerId, String messageId)
    removeMessage,
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<void> Function(
      String groupId, {
      required String deletedByPeerId,
      Chat? chat,
    })
    rememberDeletedGroup,
    required Future<void> Function() runGroupKeyGc,
    required void Function() syncBadgeCount,
    required void Function(String peerId) notifyMessageUpdated,
  }) : _facade = facade,
       _storage = storage,
       _groupKeyService = groupKeyService,
       _chatRepository = chatRepository,
       _chatSummaryService = chatSummaryService,
       _chatFileQueueService = chatFileQueueService,
       _groupOutboundCoordinator = groupOutboundCoordinator,
       _chats = chats,
       _deleteManagedMediaForMessage = deleteManagedMediaForMessage,
       _removeMessage = removeMessage,
       _persistChatSummary = persistChatSummary,
       _rememberDeletedGroup = rememberDeletedGroup,
       _runGroupKeyGc = runGroupKeyGc,
       _syncBadgeCount = syncBadgeCount,
       _notifyMessageUpdated = notifyMessageUpdated;

  final NodeFacade _facade;
  final StorageService _storage;
  final GroupKeyService _groupKeyService;
  final ChatRepository _chatRepository;
  final ChatSummaryService _chatSummaryService;
  final ChatFileQueueService _chatFileQueueService;
  final ChatGroupOutboundCoordinator _groupOutboundCoordinator;
  final Map<String, Chat> _chats;
  final Future<void> Function(Message? message) _deleteManagedMediaForMessage;
  final Future<bool> Function(String peerId, String messageId) _removeMessage;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final Future<void> Function(
    String groupId, {
    required String deletedByPeerId,
    Chat? chat,
  })
  _rememberDeletedGroup;
  final Future<void> Function() _runGroupKeyGc;
  final void Function() _syncBadgeCount;
  final void Function(String peerId) _notifyMessageUpdated;

  Future<void> clearManagedMediaReferencesInMemory() async {
    final peerIds = List<String>.from(_chats.keys);
    for (final peerId in peerIds) {
      final chat = _chats[peerId];
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
          await _chatRepository.persistLoadedChat(chat);
        } else {
          await _persistChatSummary(chat);
        }
        continue;
      }

      await _persistChatSummary(chat);
    }
    _notifyMessageUpdated('');
  }

  void clearAllChatsFromMemory() {
    _chats.clear();
    _notifyMessageUpdated('');
  }

  Future<void> deleteMessage(String peerId, String messageId) async {
    final messages = _chats[peerId]?.messagesLoaded == true
        ? _chats[peerId]!.messages
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
    _notifyMessageUpdated(peerId);
  }

  Future<void> deleteChat(String peerId) async {
    final loadedChat = _chats[peerId];
    final isGroupChat =
        loadedChat?.isGroup == true || Chat.isGroupLikePeerId(peerId);
    final canDeleteForEveryone =
        isGroupChat &&
        loadedChat != null &&
        _chatSummaryService.knownGroupOwnerPeerId(peerId) == _facade.peerId;
    if (canDeleteForEveryone) {
      await _groupOutboundCoordinator.broadcastGroupChatDelete(loadedChat);
    } else if (isGroupChat && loadedChat != null) {
      await _groupOutboundCoordinator.sendGroupLeaveBeforeLocalDelete(
        loadedChat,
      );
    }
    await deleteChatLocal(
      peerId,
      rememberDeletedGroup: isGroupChat,
      deletedByPeerId: _facade.peerId,
    );
  }

  Future<void> deleteChatLocal(
    String peerId, {
    bool rememberDeletedGroup = false,
    String? deletedByPeerId,
  }) async {
    final loadedChat = _chats[peerId];
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
    if (!isGroupChat) {
      await _groupKeyService.deleteGroupKeys(peerId);
    }
    if (rememberDeletedGroup && isGroupChat) {
      await _rememberDeletedGroup(
        peerId,
        deletedByPeerId: deletedByPeerId ?? _facade.peerId,
        chat: loadedChat,
      );
    } else {
      await _chatSummaryService.removeGroupMeta(peerId);
    }

    _chats.remove(peerId);
    _chatFileQueueService.removeQueuedItemsForPeer(peerId, storedMessages);

    _syncBadgeCount();
    await _runGroupKeyGc();
    _notifyMessageUpdated(peerId);
  }
}
