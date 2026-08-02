import 'dart:async';

import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';
import 'chat_file_transfer_coordinator.dart';
import 'chat_group_outbound_coordinator.dart';
import 'chat_outbound_service.dart';

class ChatMessageSendCoordinator {
  const ChatMessageSendCoordinator({
    required String localPeerId,
    required ChatOutboundService outboundService,
    required ChatFileTransferCoordinator fileTransferCoordinator,
    required ChatGroupOutboundCoordinator groupOutboundCoordinator,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat Function(String peerId) ensureChat,
    required String Function() nextLocalMessageId,
    required Future<void> Function(String peerId) persistLoadedChat,
    required String? Function(String chatPeerId, Message? replyTo)
    replySenderLabel,
    required String? Function(Message? replyTo) replyTextPreview,
    required String? Function(Message? replyTo) replyKind,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function() syncBadgeCount,
    required void Function(String peerId) notifyMessageUpdated,
  }) : _localPeerId = localPeerId,
       _outboundService = outboundService,
       _fileTransferCoordinator = fileTransferCoordinator,
       _groupOutboundCoordinator = groupOutboundCoordinator,
       _ensureChatLoaded = ensureChatLoaded,
       _ensureChat = ensureChat,
       _nextLocalMessageId = nextLocalMessageId,
       _persistLoadedChat = persistLoadedChat,
       _replySenderLabel = replySenderLabel,
       _replyTextPreview = replyTextPreview,
       _replyKind = replyKind,
       _replaceMessage = replaceMessage,
       _setStatus = setStatus,
       _syncBadgeCount = syncBadgeCount,
       _notifyMessageUpdated = notifyMessageUpdated;

  final String _localPeerId;
  final ChatOutboundService _outboundService;
  final ChatFileTransferCoordinator _fileTransferCoordinator;
  final ChatGroupOutboundCoordinator _groupOutboundCoordinator;
  final Future<void> Function(String peerId) _ensureChatLoaded;
  final Chat Function(String peerId) _ensureChat;
  final String Function() _nextLocalMessageId;
  final Future<void> Function(String peerId) _persistLoadedChat;
  final String? Function(String chatPeerId, Message? replyTo) _replySenderLabel;
  final String? Function(Message? replyTo) _replyTextPreview;
  final String? Function(Message? replyTo) _replyKind;
  final Future<void> Function(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  )
  _replaceMessage;
  final void Function(
    String peerId,
    ChatConnectionStatus status, {
    String? error,
  })
  _setStatus;
  final void Function() _syncBadgeCount;
  final void Function(String peerId) _notifyMessageUpdated;

  Future<void> sendMessage(
    String peerId,
    String text, {
    Message? replyTo,
  }) async {
    await _ensureChatLoaded(peerId);

    final message = Message(
      id: _nextLocalMessageId(),
      peerId: peerId,
      text: text,
      senderPeerId: _localPeerId,
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
    _notifyMessageUpdated(peerId);
    if (chat.isGroup) {
      unawaited(_groupOutboundCoordinator.sendGroupMessage(chat, message));
    } else {
      unawaited(sendDirectMessage(peerId, message));
    }
  }

  Future<void> sendDirectMessage(String peerId, Message message) {
    return _outboundService.sendDirectMessage(
      peerId,
      message,
      updateMessageStatusById: updateMessageStatusById,
      setStatus: _setStatus,
    );
  }

  Future<void> retryMessage(String peerId, String messageId) async {
    await _ensureChatLoaded(peerId);
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
      await _fileTransferCoordinator.retryFileMessage(chat, message);
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
    _notifyMessageUpdated(peerId);
    if (chat.isGroup) {
      unawaited(_groupOutboundCoordinator.sendGroupMessage(chat, retry));
    } else {
      unawaited(sendDirectMessage(peerId, retry));
    }
  }

  Future<void> updateMessageStatusById(
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
            : preserveFailedTransferStatus(current.transferStatus);
      }
      return ChatMessageCopy.copy(
        current,
        status: status,
        sendProgress: progress,
        transferStatus: transferStatus,
      );
    });
    _syncBadgeCount();
    _notifyMessageUpdated(peerId);
  }

  String preserveFailedTransferStatus(String? currentStatus) {
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
}
