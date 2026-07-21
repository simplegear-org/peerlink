import '../models/chat.dart';
import 'chat_controller_parts.dart';
import 'chat_repository.dart';

class ChatReadStateService {
  const ChatReadStateService();

  int unreadMessagesCount(Map<String, Chat> chats) {
    return chats.values.fold<int>(0, (sum, chat) => sum + chat.unreadCount);
  }

  void syncBadgeCount(
    Map<String, Chat> chats, {
    required void Function(int count) setBadgeCount,
  }) {
    setBadgeCount(unreadMessagesCount(chats));
  }

  Future<bool> markChatAsRead(
    String peerId, {
    required Map<String, Chat> chats,
    required ChatRepository chatRepository,
    required Future<void> Function(String peerId) persistLoadedChat,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chat = chats[peerId];
    if (chat == null) {
      return false;
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
        await persistLoadedChat(peerId);
        notifyMessageUpdated(peerId);
      }
      return changed;
    }

    final stored = await chatRepository.readStoredMessages(peerId);
    var changed = false;
    for (var i = 0; i < stored.length; i++) {
      final message = stored[i];
      if (message.incoming && !message.isRead) {
        stored[i] = ChatMessageCopy.copy(message, isRead: true);
        changed = true;
      }
    }
    if (!changed) {
      return false;
    }

    chatRepository.refreshSummaryFromMessages(chat, stored);
    await chatRepository.writeStoredMessages(peerId, stored);
    await persistChatSummary(chat);
    notifyMessageUpdated(peerId);
    return true;
  }
}
