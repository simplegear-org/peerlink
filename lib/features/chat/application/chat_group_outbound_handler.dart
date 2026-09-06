// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_controller_parts.dart';
import 'package:peerlink/features/chat/application/chat_media_outbound_service.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_outbound_notification_type.dart';

class ChatGroupOutboundHandler {
  const ChatGroupOutboundHandler({
    required ChatRuntimeApi facade,
    required ChatOutboundCodec outboundCodec,
    required ChatMediaOutboundService mediaOutboundService,
  }) : _facade = facade,
       _outboundCodec = outboundCodec,
       _mediaOutboundService = mediaOutboundService;

  final ChatRuntimeApi _facade;
  final ChatOutboundCodec _outboundCodec;
  final ChatMediaOutboundService _mediaOutboundService;

  Future<void> sendMessage(
    Chat groupChat,
    Message message, {
    required Future<void> Function(Chat chat) persistChatSummary,
    required Future<String> Function(Chat chat) ensureGroupKey,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List plainBytes,
    })
    encryptGroupBytes,
    required Future<String?> Function({
      required String groupId,
      required String plainText,
    })
    encryptGroupText,
    required List<String> Function(Chat chat) collectGroupRecipients,
    required Future<void> Function(
      String peerId,
      String messageId,
      MessageStatus status,
    )
    updateMessageStatusById,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
  }) async {
    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        _facade.peerId,
      }.toList(growable: false);
      await persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
      await updateMessageStatusById(
        groupChat.peerId,
        message.id,
        MessageStatus.failed,
      );
      setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Вы больше не участник этого чата',
      );
      return;
    }

    final recipients = collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      await updateMessageStatusById(
        groupChat.peerId,
        message.id,
        MessageStatus.failed,
      );
      setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Group has no members',
      );
      return;
    }

    setStatus(groupChat.peerId, ChatConnectionStatus.connecting);
    var hasFailure = false;
    var relayGroupStored = false;
    var receipt = ChatSendReceipt.empty;
    final fallbackDirectPushes = <_FallbackDirectPush>[];
    try {
      await ensureGroupKey(groupChat);
      await _syncOwnerRelayMembershipIfNeeded(groupChat);
      final plainBytes = Uint8List.fromList(utf8.encode(message.text));
      final encryptedBytes = await encryptGroupBytes(
        groupId: groupChat.peerId,
        plainBytes: plainBytes,
      );
      final payloadBytes = encryptedBytes ?? plainBytes;
      final blobId = await _facade.uploadBlob(
        scopeKind: RelayBlobScopeKind.group,
        targetId: groupChat.peerId,
        fileName: 'text.txt',
        mimeType: 'text/plain',
        bytes: payloadBytes,
        blobId: 'blob:${message.id}',
      );
      final blobRefPayload = _outboundCodec.encodeGroupBlobRefPayload(
        groupChat: groupChat,
        messageId: message.id,
        contentKind: 'text',
        textPreview: message.text,
        blobId: blobId,
      );
      final securePayload = await encryptGroupText(
        groupId: groupChat.peerId,
        plainText: blobRefPayload,
      );
      final payload =
          securePayload ??
          _outboundCodec.encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: message.id,
            text: blobRefPayload,
          );
      receipt = await _facade.sendPayload(
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
      if (!receipt.sent) {
        throw StateError('group relay payload was not stored');
      }
      relayGroupStored = true;
    } catch (_) {
      const fanoutConcurrency = 6;
      final payload = _outboundCodec.encodeGroupMessagePayload(
        groupChat: groupChat,
        messageId: message.id,
        text: message.text,
      );
      for (
        var batchStart = 0;
        batchStart < recipients.length;
        batchStart += fanoutConcurrency
      ) {
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
              final fanoutReceipt = await _facade.sendPayload(
                recipient,
                text: payload,
                messageId: perRecipientMessageId,
                replyToMessageId: message.replyToMessageId,
                replyToSenderPeerId: message.replyToSenderPeerId,
                replyToSenderLabel: message.replyToSenderLabel,
                replyToTextPreview: message.replyToTextPreview,
                replyToKind: message.replyToKind,
              );
              if (fanoutReceipt.sent) {
                fallbackDirectPushes.add(
                  _FallbackDirectPush(
                    recipient: recipient,
                    messageId: perRecipientMessageId,
                    relayServers: fanoutReceipt.relayServers,
                  ),
                );
              }
              return fanoutReceipt.sent;
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
      await updateMessageStatusById(
        groupChat.peerId,
        message.id,
        MessageStatus.failed,
      );
      setStatus(
        groupChat.peerId,
        ChatConnectionStatus.error,
        error: 'Failed to send to some group members',
      );
      return;
    }

    await updateMessageStatusById(
      groupChat.peerId,
      message.id,
      MessageStatus.sent,
    );
    if (!relayGroupStored) {
      developer.log(
        'group push skipped group=${groupChat.peerId} '
        'messageId=${message.id} reason=relay-not-stored '
        'fallbackDirectPushes=${fallbackDirectPushes.length}',
        name: 'chat',
      );
      await _sendFallbackDirectPushes(
        groupId: groupChat.peerId,
        notificationType: 'text',
        pushes: fallbackDirectPushes,
      );
      setStatus(groupChat.peerId, ChatConnectionStatus.connected);
      return;
    }
    try {
      await _facade.sendGroupPushEvent(
        groupId: groupChat.peerId,
        messageId: message.id,
        recipientUserIds: recipients,
        relayServers: receipt.relayServers,
        notificationType: 'text',
        relayScopeKind: 'group',
        relayMessageId: message.id,
      );
    } catch (error) {
      developer.log(
        'push event send failed group=${groupChat.peerId} messageId=${message.id} error=$error',
        name: 'chat',
      );
    }
    setStatus(groupChat.peerId, ChatConnectionStatus.connected);
  }

  Future<void> sendFile(
    Chat groupChat, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
    required Future<void> Function(Chat chat) persistChatSummary,
    required List<String> Function(Chat chat) collectGroupRecipients,
    required Future<String> Function(Chat chat) ensureGroupKey,
    required Future<Uint8List?> Function({
      required String groupId,
      required Uint8List plainBytes,
    })
    encryptGroupBytes,
    required Future<String?> Function({
      required String groupId,
      required String plainText,
    })
    encryptGroupText,
    required String? Function(String chatPeerId, Message? replyTo)
    replySenderLabel,
    required String? Function(Message? replyTo) replyTextPreview,
    required String? Function(Message? replyTo) replyKind,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    updateFileProgress,
    required Future<void> Function(OutgoingRelayMediaState state)
    rememberOutgoingRelayMediaState,
    required Future<void> Function(String peerId, String messageId)
    forgetOutgoingRelayMediaState,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required void Function(String peerId, String messageId) clearProgressUpdate,
    required Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required String sourcePath,
    })
    saveMediaFile,
    required Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required Uint8List bytes,
    })
    saveMediaBytes,
    required Future<String?> Function(Message message) ensureThumbnail,
    required String Function(Object error, {required String fallback})
    transferStatusForError,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
      groupChat.memberPeerIds = <String>{
        ...groupChat.memberPeerIds,
        _facade.peerId,
      }.toList(growable: false);
      await persistChatSummary(groupChat);
    }

    if (!groupChat.memberPeerIds.contains(_facade.peerId)) {
      await replaceMessage(
        groupChat.peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          status: MessageStatus.failed,
          transferStatus: 'Вы больше не участник чата',
        ),
      );
      setStatus(groupChat.peerId, ChatConnectionStatus.error);
      return;
    }

    final recipients = collectGroupRecipients(groupChat);
    if (recipients.isEmpty) {
      await replaceMessage(
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

    setStatus(groupChat.peerId, ChatConnectionStatus.connecting);

    var hasFailure = false;
    Object? failureError;
    String? blobId;
    String? fallbackPayload;
    String? fallbackNotificationType;
    var relayGroupStored = false;
    var sendReceipt = ChatSendReceipt.empty;
    final fallbackDirectPushes = <_FallbackDirectPush>[];
    try {
      await ensureGroupKey(groupChat);
      await _syncOwnerRelayMembershipIfNeeded(groupChat);
      final upload = await _mediaOutboundService.prepareAndUpload(
        chatPeerId: groupChat.peerId,
        messageId: messageId,
        fileName: fileName,
        fileBytes: fileBytes,
        filePath: filePath,
        fileSizeBytes: fileSizeBytes,
        mimeType: mimeType,
        scopeKind: RelayBlobScopeKind.group,
        targetId: groupChat.peerId,
        updateFileProgress: updateFileProgress,
        logQueue: (message) => developer.log(message, name: 'chat'),
        isCancelled: () => false,
        transformPayload: (plainBytes) async {
          final encryptedBytes = await encryptGroupBytes(
            groupId: groupChat.peerId,
            plainBytes: plainBytes,
          );
          return encryptedBytes ?? plainBytes;
        },
      );
      final uploadedBlobId = upload.blobId;
      blobId = upload.blobId;
      final blobRefPayload = _outboundCodec.encodeGroupBlobRefPayload(
        groupChat: groupChat,
        messageId: messageId,
        contentKind: 'media',
        fileName: fileName,
        mimeType: mimeType,
        fileSizeBytes: fileSizeBytes,
        blobId: uploadedBlobId,
      );
      final securePayload = await encryptGroupText(
        groupId: groupChat.peerId,
        plainText: blobRefPayload,
      );
      final payload =
          securePayload ??
          _outboundCodec.encodeGroupMessagePayload(
            groupChat: groupChat,
            messageId: messageId,
            text: blobRefPayload,
          );
      fallbackPayload = payload;
      fallbackNotificationType = chatNotificationTypeForFile(
        fileName: fileName,
        mimeType: mimeType,
      );
      await rememberOutgoingRelayMediaState(
        OutgoingRelayMediaState(
          peerId: groupChat.peerId,
          messageId: messageId,
          targetKind: OutgoingRelayMediaTargetKind.group,
          blobId: uploadedBlobId,
          payloadText: payload,
          recipients: recipients,
          localFilePath: filePath,
          replyToMessageId: replyTo?.id,
          replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
          replyToSenderLabel: replySenderLabel(groupChat.peerId, replyTo),
          replyToTextPreview: replyTextPreview(replyTo),
          replyToKind: replyKind(replyTo),
        ),
      );
      sendReceipt = await _facade.sendPayload(
        groupChat.peerId,
        targetKind: ChatPayloadTargetKind.group,
        recipients: recipients,
        text: payload,
        messageId: messageId,
        kind: 'text',
        replyToMessageId: replyTo?.id,
        replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
        replyToSenderLabel: replySenderLabel(groupChat.peerId, replyTo),
        replyToTextPreview: replyTextPreview(replyTo),
        replyToKind: replyKind(replyTo),
      );
      if (!sendReceipt.sent) {
        throw StateError('group relay payload was not stored');
      }
      relayGroupStored = true;
      await forgetOutgoingRelayMediaState(groupChat.peerId, messageId);
      await updateFileProgress(
        groupChat.peerId,
        messageId,
        sentBytes: fileSizeBytes,
        totalBytes: fileSizeBytes,
        statusText: 'Отправлено',
      );
    } catch (error) {
      hasFailure = true;
      failureError = error;
      final payload = fallbackPayload;
      if (blobId != null && payload != null) {
        final fallbackOk = await _sendFallbackDirectPayloads(
          groupId: groupChat.peerId,
          messageId: messageId,
          recipients: recipients,
          payload: payload,
          replyToMessageId: replyTo?.id,
          replyToSenderPeerId: replyTo?.senderPeerId ?? replyTo?.peerId,
          replyToSenderLabel: replySenderLabel(groupChat.peerId, replyTo),
          replyToTextPreview: replyTextPreview(replyTo),
          replyToKind: replyKind(replyTo),
          relayBlobId: blobId,
          pushes: fallbackDirectPushes,
        );
        if (fallbackOk) {
          hasFailure = false;
          failureError = null;
          await forgetOutgoingRelayMediaState(groupChat.peerId, messageId);
          await _discardPendingGroupPayload(
            groupId: groupChat.peerId,
            messageId: messageId,
          );
          await updateFileProgress(
            groupChat.peerId,
            messageId,
            sentBytes: fileSizeBytes,
            totalBytes: fileSizeBytes,
            statusText: 'Отправлено',
          );
        }
      }
    }

    final local = await _mediaOutboundService.saveLocalMedia(
      peerId: groupChat.peerId,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      mimeType: mimeType,
      saveMediaFile: saveMediaFile,
      saveMediaBytes: saveMediaBytes,
      ensureThumbnail: ensureThumbnail,
    );

    await replaceMessage(
      groupChat.peerId,
      messageId,
      (current) => ChatMessageCopy.copy(
        current,
        transferId: blobId != null
            ? _outboundCodec.groupBlobTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
                blobId: blobId,
              )
            : _outboundCodec.groupFileTransferId(
                groupId: groupChat.peerId,
                messageId: messageId,
              ),
        localFilePath: (local.localPath != null && local.localPath!.isNotEmpty)
            ? local.localPath
            : current.localFilePath,
        thumbnailPath: local.thumbnailPath ?? current.thumbnailPath,
        fileDataBase64: null,
        transferredBytes: hasFailure ? current.transferredBytes : null,
        sendProgress: hasFailure ? current.sendProgress : null,
        transferStatus: hasFailure
            ? transferStatusForError(
                failureError ?? StateError('group media send failed'),
                fallback: 'Ошибка отправки',
              )
            : null,
        status: hasFailure ? MessageStatus.failed : MessageStatus.sent,
      ),
    );
    clearProgressUpdate(groupChat.peerId, messageId);

    setStatus(
      groupChat.peerId,
      hasFailure ? ChatConnectionStatus.error : ChatConnectionStatus.connected,
      error: hasFailure ? 'Failed to send group media' : null,
    );
    if (!hasFailure) {
      if (!relayGroupStored) {
        developer.log(
          'group media push fallback group=${groupChat.peerId} '
          'messageId=$messageId directPushes=${fallbackDirectPushes.length}',
          name: 'chat',
        );
        await _sendFallbackDirectPushes(
          groupId: groupChat.peerId,
          notificationType: fallbackNotificationType ?? 'file',
          pushes: fallbackDirectPushes,
        );
      } else {
        try {
          await _facade.sendGroupPushEvent(
            groupId: groupChat.peerId,
            messageId: messageId,
            recipientUserIds: recipients,
            relayServers: sendReceipt.relayServers,
            notificationType: chatNotificationTypeForFile(
              fileName: fileName,
              mimeType: mimeType,
            ),
            relayScopeKind: 'group',
            relayBlobId: blobId,
            relayMessageId: messageId,
          );
        } catch (error) {
          developer.log(
            'push event send failed group=${groupChat.peerId} '
            'messageId=$messageId error=$error',
            name: 'chat',
          );
        }
      }
    }
    notifyMessageUpdated(groupChat.peerId);
  }

  Future<bool> _sendFallbackDirectPayloads({
    required String groupId,
    required String messageId,
    required List<String> recipients,
    required String payload,
    required String? replyToMessageId,
    required String? replyToSenderPeerId,
    required String? replyToSenderLabel,
    required String? replyToTextPreview,
    required String? replyToKind,
    required String? relayBlobId,
    required List<_FallbackDirectPush> pushes,
  }) async {
    const fanoutConcurrency = 6;
    var hasFailure = false;
    for (
      var batchStart = 0;
      batchStart < recipients.length;
      batchStart += fanoutConcurrency
    ) {
      final batchEnd = (batchStart + fanoutConcurrency > recipients.length)
          ? recipients.length
          : batchStart + fanoutConcurrency;
      final batch = recipients.sublist(batchStart, batchEnd);
      final results = await Future.wait(
        batch.asMap().entries.map((entry) async {
          final recipient = entry.value;
          final recipientIndex = batchStart + entry.key;
          final perRecipientMessageId = '$messageId:$recipientIndex';
          try {
            final receipt = await _facade.sendPayload(
              recipient,
              text: payload,
              messageId: perRecipientMessageId,
              replyToMessageId: replyToMessageId,
              replyToSenderPeerId: replyToSenderPeerId,
              replyToSenderLabel: replyToSenderLabel,
              replyToTextPreview: replyToTextPreview,
              replyToKind: replyToKind,
            );
            if (receipt.sent) {
              pushes.add(
                _FallbackDirectPush(
                  recipient: recipient,
                  messageId: perRecipientMessageId,
                  relayServers: receipt.relayServers,
                  relayBlobId: relayBlobId,
                ),
              );
            }
            return receipt.sent;
          } catch (_) {
            return false;
          }
        }),
      );
      if (results.any((ok) => !ok)) {
        hasFailure = true;
      }
    }
    if (hasFailure) {
      developer.log(
        'group media fallback failed group=$groupId messageId=$messageId',
        name: 'chat',
      );
    }
    return !hasFailure;
  }

  Future<void> _discardPendingGroupPayload({
    required String groupId,
    required String messageId,
  }) async {
    try {
      await _facade.discardPendingPayload(
        targetKind: ChatPayloadTargetKind.group,
        targetId: groupId,
        messageId: messageId,
      );
    } catch (error) {
      developer.log(
        'group media fallback pending cleanup failed group=$groupId '
        'messageId=$messageId error=$error',
        name: 'chat',
      );
    }
  }

  Future<void> _syncOwnerRelayMembershipIfNeeded(Chat groupChat) async {
    final ownerPeerId = (groupChat.ownerPeerId ?? '').trim();
    if (ownerPeerId.isEmpty || ownerPeerId != _facade.peerId) {
      return;
    }
    final members = <String>{
      ...groupChat.memberPeerIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
      _facade.peerId,
    }.toList(growable: false)..sort();
    try {
      await _facade.updateRelayGroupMembers(
        groupId: groupChat.peerId,
        ownerPeerId: ownerPeerId,
        memberPeerIds: members,
      );
      developer.log(
        'group membership sync before send ok group=${groupChat.peerId} '
        'members=${members.length}',
        name: 'chat',
      );
    } catch (error) {
      developer.log(
        'group membership sync before send failed group=${groupChat.peerId} '
        'members=${members.length} error=$error',
        name: 'chat',
      );
    }
  }

  Future<void> _sendFallbackDirectPushes({
    required String groupId,
    required String notificationType,
    required List<_FallbackDirectPush> pushes,
  }) async {
    for (final push in pushes) {
      try {
        await _facade.sendDirectPushEvent(
          directPeerId: push.recipient,
          messageId: push.messageId,
          relayServers: push.relayServers,
          notificationType: notificationType,
          relayScopeKind: 'direct',
          relayBlobId: push.relayBlobId,
          relayMessageId: push.messageId,
          data: <String, dynamic>{'groupId': groupId},
        );
      } catch (error) {
        developer.log(
          'fallback direct push failed group=$groupId '
          'direct=${push.recipient} messageId=${push.messageId} error=$error',
          name: 'chat',
        );
      }
    }
  }
}

class _FallbackDirectPush {
  final String recipient;
  final String messageId;
  final List<String> relayServers;
  final String? relayBlobId;

  const _FallbackDirectPush({
    required this.recipient,
    required this.messageId,
    required this.relayServers,
    this.relayBlobId,
  });
}
