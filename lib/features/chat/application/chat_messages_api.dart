// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_message_mutation_service.dart';
import 'package:peerlink/features/chat/application/chat_message_send_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_read_state_service.dart';
import 'package:peerlink/features/chat/application/chat_receipt_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';

abstract interface class ChatMessagesApi {
  Future<void> sendMessage(String peerId, String text, {Message? replyTo});

  Future<void> retryMessage(String peerId, String messageId);

  Future<void> markChatAsRead(String peerId);

  Future<void> updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  );

  Future<void> applyIncomingReceipt(IncomingMessageReceiptPayload payload);

  Future<void> sendDeliveredForMessage(Message message, Chat chat);

  int unreadMessagesCount();

  void syncBadgeCount();

  Future<Message?> findMessage(String peerId, String messageId);

  Future<void> appendMessage(String peerId, Message message);

  Future<void> replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  );

  Future<bool> removeMessage(String peerId, String messageId);

  Future<bool> removeMessageWithMediaCleanup(String peerId, String messageId);

  Future<bool> removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  );

  Future<void> deleteManagedMediaForMessage(Message? message);
}

class ChatControllerMessagesApi implements ChatMessagesApi {
  const ChatControllerMessagesApi({
    required ChatMessageSendCoordinator messageSendCoordinator,
    required ChatMessageMutationService messageMutationService,
    required ChatReadStateService readStateService,
    required ChatReceiptService receiptService,
    required ChatRepository chatRepository,
    required Map<String, Chat> chats,
    required Future<void> Function(String peerId) persistLoadedChat,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(int unreadCount)? onUnreadBadgeCountChanged,
  }) : _messageSendCoordinator = messageSendCoordinator,
       _messageMutationService = messageMutationService,
       _readStateService = readStateService,
       _receiptService = receiptService,
       _chatRepository = chatRepository,
       _chats = chats,
       _persistLoadedChat = persistLoadedChat,
       _persistChatSummary = persistChatSummary,
       _notifyMessageUpdated = notifyMessageUpdated,
       _onUnreadBadgeCountChanged = onUnreadBadgeCountChanged;

  final ChatMessageSendCoordinator _messageSendCoordinator;
  final ChatMessageMutationService _messageMutationService;
  final ChatReadStateService _readStateService;
  final ChatReceiptService _receiptService;
  final ChatRepository _chatRepository;
  final Map<String, Chat> _chats;
  final Future<void> Function(String peerId) _persistLoadedChat;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final void Function(String peerId) _notifyMessageUpdated;
  final void Function(int unreadCount)? _onUnreadBadgeCountChanged;

  @override
  Future<void> sendMessage(String peerId, String text, {Message? replyTo}) {
    return _messageSendCoordinator.sendMessage(peerId, text, replyTo: replyTo);
  }

  @override
  Future<void> retryMessage(String peerId, String messageId) {
    return _messageSendCoordinator.retryMessage(peerId, messageId);
  }

  @override
  Future<void> updateMessageStatusById(
    String peerId,
    String messageId,
    MessageStatus status,
  ) {
    return _messageSendCoordinator.updateMessageStatusById(
      peerId,
      messageId,
      status,
    );
  }

  @override
  int unreadMessagesCount() {
    return _readStateService.unreadMessagesCount(_chats);
  }

  @override
  void syncBadgeCount() {
    final setBadgeCount = _onUnreadBadgeCountChanged;
    if (setBadgeCount == null) {
      return;
    }
    _readStateService.syncBadgeCount(_chats, setBadgeCount: setBadgeCount);
  }

  @override
  Future<void> markChatAsRead(String peerId) async {
    try {
      final marked = await _readStateService.markChatAsRead(
        peerId,
        chats: _chats,
        chatRepository: _chatRepository,
        persistLoadedChat: _persistLoadedChat,
        persistChatSummary: _persistChatSummary,
        notifyMessageUpdated: _notifyMessageUpdated,
      );
      if (marked.isNotEmpty) {
        final chat = _chats[peerId];
        if (chat != null) {
          await _receiptService.sendReadForMessages(marked, chat);
        }
      }
      syncBadgeCount();
    } catch (e, stack) {
      developer.log(
        '[chat] markChatAsRead failed peer=$peerId error=$e\n$stack',
        name: 'chat',
      );
    }
  }

  @override
  Future<void> applyIncomingReceipt(IncomingMessageReceiptPayload payload) {
    return _receiptService.applyIncomingReceipt(
      payload,
      chats: _chats,
      chatRepository: _chatRepository,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  @override
  Future<void> sendDeliveredForMessage(Message message, Chat chat) {
    return _receiptService.sendDeliveredForMessage(message, chat);
  }

  @override
  Future<void> appendMessage(String peerId, Message message) async {
    await _messageMutationService.appendMessage(peerId, message);
    final chat = _chats[peerId];
    if (chat != null && message.incoming) {
      await _receiptService.sendDeliveredForMessage(message, chat);
    }
  }

  @override
  Future<bool> removeMessage(String peerId, String messageId) {
    return _messageMutationService.removeMessage(peerId, messageId);
  }

  @override
  Future<Message?> findMessage(String peerId, String messageId) {
    return _messageMutationService.findMessage(peerId, messageId);
  }

  @override
  Future<void> deleteManagedMediaForMessage(Message? message) {
    return _messageMutationService.deleteManagedMediaForMessage(message);
  }

  @override
  Future<bool> removeMessageWithMediaCleanup(String peerId, String messageId) {
    return _messageMutationService.removeMessageWithMediaCleanup(
      peerId,
      messageId,
    );
  }

  @override
  Future<bool> removeMessageByAuthorWithMediaCleanup(
    String peerId,
    String messageId,
    String authorPeerId,
  ) {
    return _messageMutationService.removeMessageByAuthorWithMediaCleanup(
      peerId,
      messageId,
      authorPeerId,
    );
  }

  @override
  Future<void> replaceMessage(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  ) {
    return _messageMutationService.replaceMessage(peerId, messageId, transform);
  }
}
