// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_controller_parts.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_outbound_notification_type.dart';

class ChatOutgoingRelayMediaResumeService {
  static const String storageKey = 'outgoing_relay_media_state.v1';

  ChatOutgoingRelayMediaResumeService({
    required NodeFacade facade,
    required SecureStorageBox settingsBox,
    required ChatOutboundCodec outboundCodec,
  }) : _facade = facade,
       _settingsBox = settingsBox,
       _outboundCodec = outboundCodec;

  final NodeFacade _facade;
  final SecureStorageBox _settingsBox;
  final ChatOutboundCodec _outboundCodec;
  final Set<String> _resumeInFlight = <String>{};

  Future<void> remember(OutgoingRelayMediaState state) async {
    final states = _load();
    states[_stateId(state.peerId, state.messageId)] = state;
    await _save(states);
  }

  Future<void> forget(String peerId, String messageId) async {
    final states = _load();
    if (states.remove(_stateId(peerId, messageId)) == null) {
      return;
    }
    await _save(states);
  }

  Future<void> resumePending({
    required String reason,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat? Function(String peerId) findChat,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    updateFileProgress,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required void Function(String peerId, String messageId) clearProgressUpdate,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(String message) logQueue,
  }) async {
    final states = _load();
    if (states.isEmpty) {
      return;
    }
    var resumed = 0;
    for (final entry in states.entries) {
      final state = entry.value;
      final key = entry.key;
      if (_resumeInFlight.contains(key)) {
        continue;
      }
      _resumeInFlight.add(key);
      resumed += 1;
      unawaited(
        _resumeState(
          state,
          reason: reason,
          ensureChatLoaded: ensureChatLoaded,
          findChat: findChat,
          updateFileProgress: updateFileProgress,
          replaceMessage: replaceMessage,
          clearProgressUpdate: clearProgressUpdate,
          setStatus: setStatus,
          notifyMessageUpdated: notifyMessageUpdated,
          logQueue: logQueue,
        ).whenComplete(() {
          _resumeInFlight.remove(key);
        }),
      );
    }
    logQueue('resume relay-media reason=$reason count=$resumed');
  }

  Map<String, OutgoingRelayMediaState> _load() {
    final raw = _settingsBox.get(storageKey);
    if (raw is! Map) {
      return <String, OutgoingRelayMediaState>{};
    }
    final result = <String, OutgoingRelayMediaState>{};
    raw.forEach((key, value) {
      if (key is! String || value is! Map) {
        return;
      }
      final state = OutgoingRelayMediaState.fromJson(
        Map<String, dynamic>.from(value),
      );
      if (state != null) {
        result[key] = state;
      }
    });
    return result;
  }

  Future<void> _save(Map<String, OutgoingRelayMediaState> states) {
    return _settingsBox.put(
      storageKey,
      states.map(
        (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
      ),
    );
  }

  String _stateId(String peerId, String messageId) => '$peerId::$messageId';

  Future<void> _resumeState(
    OutgoingRelayMediaState state, {
    required String reason,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat? Function(String peerId) findChat,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    updateFileProgress,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
    required void Function(String peerId, String messageId) clearProgressUpdate,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(String message) logQueue,
  }) async {
    try {
      await ensureChatLoaded(state.peerId);
      final chat = findChat(state.peerId);
      if (chat == null) {
        await forget(state.peerId, state.messageId);
        return;
      }
      final index = chat.messages.indexWhere(
        (message) => message.id == state.messageId,
      );
      if (index < 0) {
        await forget(state.peerId, state.messageId);
        return;
      }
      final message = chat.messages[index];
      final alreadySentTransferId = message.transferId?.trim() ?? '';
      if (message.status == MessageStatus.sent &&
          alreadySentTransferId.contains(state.blobId)) {
        await forget(state.peerId, state.messageId);
        return;
      }
      if (message.incoming || message.kind != MessageKind.file) {
        await forget(state.peerId, state.messageId);
        return;
      }

      await updateFileProgress(
        state.peerId,
        state.messageId,
        sentBytes: message.fileSizeBytes ?? 0,
        totalBytes: message.fileSizeBytes ?? 0,
        statusText: 'Повторная отправка',
      );

      final sendReceipt = await _facade.sendPayload(
        state.peerId,
        targetKind: state.targetKind == OutgoingRelayMediaTargetKind.group
            ? ChatPayloadTargetKind.group
            : ChatPayloadTargetKind.direct,
        recipients: state.recipients,
        text: state.payloadText,
        messageId: state.messageId,
        replyToMessageId: state.replyToMessageId,
        replyToSenderPeerId: state.replyToSenderPeerId,
        replyToSenderLabel: state.replyToSenderLabel,
        replyToTextPreview: state.replyToTextPreview,
        replyToKind: state.replyToKind,
      );
      if (!sendReceipt.sent) {
        throw StateError('relay media payload was not stored');
      }

      await replaceMessage(
        state.peerId,
        state.messageId,
        (current) => ChatMessageCopy.copy(
          current,
          transferId: state.targetKind == OutgoingRelayMediaTargetKind.group
              ? _outboundCodec.groupBlobTransferId(
                  groupId: state.peerId,
                  messageId: state.messageId,
                  blobId: state.blobId,
                )
              : _outboundCodec.directBlobTransferId(
                  peerId: state.peerId,
                  messageId: state.messageId,
                  blobId: state.blobId,
                ),
          localFilePath:
              current.localFilePath ??
              ((state.localFilePath?.isNotEmpty ?? false)
                  ? state.localFilePath
                  : current.localFilePath),
          transferredBytes: null,
          sendProgress: null,
          transferStatus: null,
          status: MessageStatus.sent,
          receiptStatus: MessageReceiptStatus.sent,
        ),
      );
      clearProgressUpdate(state.peerId, state.messageId);
      await _sendPushAfterResume(
        state: state,
        chat: chat,
        message: message,
        relayServers: sendReceipt.relayServers,
        logQueue: logQueue,
      );
      await forget(state.peerId, state.messageId);
      setStatus(state.peerId, ChatConnectionStatus.connected);
      notifyMessageUpdated(state.peerId);
      logQueue(
        'resume relay-media done reason=$reason peer=${state.peerId} '
        'messageId=${state.messageId} blobId=${state.blobId}',
      );
    } catch (error) {
      logQueue(
        'resume relay-media failed reason=$reason peer=${state.peerId} '
        'messageId=${state.messageId} error=$error',
      );
    }
  }

  Future<void> _sendPushAfterResume({
    required OutgoingRelayMediaState state,
    required Chat chat,
    required Message message,
    required List<String> relayServers,
    required void Function(String message) logQueue,
  }) async {
    final notificationType = chatNotificationTypeForFile(
      fileName: message.fileName ?? message.text,
      mimeType: message.mimeType,
    );
    try {
      if (state.targetKind == OutgoingRelayMediaTargetKind.group) {
        final recipients =
            (state.recipients == null || state.recipients!.isEmpty
                    ? chat.memberPeerIds
                    : state.recipients!)
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList(growable: false)
              ..sort();
        await _facade.sendGroupPushEvent(
          groupId: state.peerId,
          messageId: state.messageId,
          recipientUserIds: recipients,
          relayServers: relayServers,
          notificationType: notificationType,
          relayScopeKind: 'group',
          relayBlobId: state.blobId,
          relayMessageId: state.messageId,
        );
        return;
      }
      await _facade.sendDirectPushEvent(
        directPeerId: state.peerId,
        messageId: state.messageId,
        relayServers: relayServers,
        notificationType: notificationType,
        relayScopeKind: 'direct',
        relayBlobId: state.blobId,
        relayMessageId: state.messageId,
      );
    } catch (error) {
      logQueue(
        'resume relay-media push failed peer=${state.peerId} '
        'messageId=${state.messageId} error=$error',
      );
    }
  }
}
