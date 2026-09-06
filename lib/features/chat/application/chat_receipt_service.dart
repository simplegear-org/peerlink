// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_controller_parts.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';

class ChatReceiptService {
  const ChatReceiptService({
    required ChatRuntimeApi facade,
    required ChatOutboundCodec outboundCodec,
  }) : _facade = facade,
       _outboundCodec = outboundCodec;

  final ChatRuntimeApi _facade;
  final ChatOutboundCodec _outboundCodec;

  Future<void> sendDeliveredForMessage(Message message, Chat chat) async {
    if (!message.incoming) {
      return;
    }
    final targetPeerId = _receiptTargetPeerId(message, chat);
    if (targetPeerId == null || targetPeerId == _facade.peerId) {
      return;
    }
    await _sendReceipt(
      targetPeerId: targetPeerId,
      chatId: chat.peerId,
      isGroup: chat.isGroup,
      messageIds: <String>[message.id],
      status: MessageReceiptStatus.delivered,
    );
  }

  Future<void> sendReadForMessages(List<Message> messages, Chat chat) async {
    final byTarget = <String, List<String>>{};
    for (final message in messages) {
      if (!message.incoming) {
        continue;
      }
      final targetPeerId = _receiptTargetPeerId(message, chat);
      if (targetPeerId == null || targetPeerId == _facade.peerId) {
        continue;
      }
      byTarget.putIfAbsent(targetPeerId, () => <String>[]).add(message.id);
    }
    for (final entry in byTarget.entries) {
      await _sendReceipt(
        targetPeerId: entry.key,
        chatId: chat.peerId,
        isGroup: chat.isGroup,
        messageIds: entry.value,
        status: MessageReceiptStatus.read,
      );
    }
  }

  Future<void> applyIncomingReceipt(
    IncomingMessageReceiptPayload receipt, {
    required Map<String, Chat> chats,
    required ChatRepository chatRepository,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final chatId = receipt.isGroup ? receipt.chatId : receipt.senderPeerId;
    final chat = chats[chatId];
    final peerId = chat?.peerId ?? chatId;
    var changed = false;
    for (final messageId in receipt.messageIds) {
      await chatRepository.replaceMessage(peerId, messageId, (current) {
        if (current.incoming) {
          return current;
        }
        final updated = _applyReceipt(current, receipt);
        if (identical(updated, current)) {
          return current;
        }
        changed = true;
        return updated;
      });
    }
    if (changed) {
      notifyMessageUpdated(peerId);
    }
  }

  Future<void> markSent(
    String peerId,
    String messageId, {
    required ChatRepository chatRepository,
  }) {
    return chatRepository.replaceMessage(
      peerId,
      messageId,
      (current) => ChatMessageCopy.copy(
        current,
        receiptStatus: current.receiptStatus == MessageReceiptStatus.pending
            ? MessageReceiptStatus.sent
            : current.receiptStatus,
      ),
    );
  }

  Message _applyReceipt(
    Message current,
    IncomingMessageReceiptPayload receipt,
  ) {
    final sender = receipt.senderPeerId.trim();
    if (sender.isEmpty) {
      return current;
    }
    final delivered = Map<String, int>.from(current.deliveredAtByPeer);
    final read = Map<String, int>.from(current.readAtByPeer);
    if (receipt.status == MessageReceiptStatus.read.name) {
      read[sender] = receipt.atMs;
      delivered.putIfAbsent(sender, () => receipt.atMs);
    } else if (receipt.status == MessageReceiptStatus.delivered.name) {
      delivered[sender] = receipt.atMs;
    } else {
      return current;
    }
    final nextStatus = read.isNotEmpty
        ? MessageReceiptStatus.read
        : delivered.isNotEmpty
        ? MessageReceiptStatus.delivered
        : current.receiptStatus;
    if (nextStatus == current.receiptStatus &&
        _sameMap(delivered, current.deliveredAtByPeer) &&
        _sameMap(read, current.readAtByPeer)) {
      return current;
    }
    return ChatMessageCopy.copy(
      current,
      receiptStatus: _maxReceiptStatus(current.receiptStatus, nextStatus),
      deliveredAtByPeer: delivered,
      readAtByPeer: read,
    );
  }

  String? _receiptTargetPeerId(Message message, Chat chat) {
    if (chat.isGroup) {
      final sender = message.senderPeerId?.trim() ?? '';
      return sender.isEmpty ? null : sender;
    }
    return chat.peerId;
  }

  Future<void> _sendReceipt({
    required String targetPeerId,
    required String chatId,
    required bool isGroup,
    required List<String> messageIds,
    required MessageReceiptStatus status,
  }) async {
    final normalizedIds = messageIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (normalizedIds.isEmpty) {
      return;
    }
    final atMs = DateTime.now().millisecondsSinceEpoch;
    final payload = _outboundCodec.encodeMessageReceiptPayload(
      chatId: chatId,
      isGroup: isGroup,
      messageIds: normalizedIds,
      status: status.name,
      atMs: atMs,
    );
    unawaited(
      _facade
          .sendPayload(
            targetPeerId,
            text: payload,
            kind: 'receipt',
            messageId: 'receipt:$chatId:${status.name}:$atMs',
          )
          .catchError((error) {
            developer.log(
              '[chat] receipt send failed target=$targetPeerId chat=$chatId '
              'status=${status.name} error=$error',
              name: 'chat',
            );
            return ChatSendReceipt.empty;
          }),
    );
  }

  MessageReceiptStatus _maxReceiptStatus(
    MessageReceiptStatus a,
    MessageReceiptStatus b,
  ) {
    return a.index >= b.index ? a : b;
  }

  bool _sameMap(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
