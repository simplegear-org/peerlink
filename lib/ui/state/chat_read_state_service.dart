// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../models/chat.dart';
import '../models/message.dart';
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

  Future<List<Message>> markChatAsRead(
    String peerId, {
    required Map<String, Chat> chats,
    required ChatRepository chatRepository,
    required Future<void> Function(String peerId) persistLoadedChat,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chat = chats[peerId];
    if (chat == null) {
      return <Message>[];
    }

    if (chat.messagesLoaded) {
      var changed = false;
      final marked = <Message>[];
      for (var i = 0; i < chat.messages.length; i++) {
        final message = chat.messages[i];
        if (message.incoming && !message.isRead) {
          chat.messages[i] = ChatMessageCopy.copy(message, isRead: true);
          marked.add(chat.messages[i]);
          changed = true;
        }
      }
      if (changed) {
        await persistLoadedChat(peerId);
        notifyMessageUpdated(peerId);
      }
      return marked;
    }

    final stored = await chatRepository.readStoredMessages(peerId);
    var changed = false;
    final marked = <Message>[];
    for (var i = 0; i < stored.length; i++) {
      final message = stored[i];
      if (message.incoming && !message.isRead) {
        stored[i] = ChatMessageCopy.copy(message, isRead: true);
        marked.add(stored[i]);
        changed = true;
      }
    }
    if (!changed) {
      return <Message>[];
    }

    chatRepository.refreshSummaryFromMessages(chat, stored);
    await chatRepository.writeStoredMessages(peerId, stored);
    await persistChatSummary(chat);
    notifyMessageUpdated(peerId);
    return marked;
  }
}
