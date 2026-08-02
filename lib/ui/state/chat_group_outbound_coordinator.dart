import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_group_flow_service.dart';
import 'chat_outbound_codec.dart';
import 'chat_outbound_service.dart';

class ChatGroupOutboundCoordinator {
  const ChatGroupOutboundCoordinator({
    required NodeFacade facade,
    required ChatOutboundService outboundService,
    required ChatGroupFlowService groupFlowService,
    required ChatOutboundCodec outboundCodec,
    required StorageService storage,
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
    required String Function(Object error, {required String fallback})
    transferStatusForError,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
    required void Function(String peerId) notifyMessageUpdated,
    required Future<void> Function(
      String peerId,
      String messageId,
      MessageStatus status,
    )
    updateMessageStatusById,
    required Future<void> Function(
      ChatMessage message, {
      IncomingGroupMembersPayload? payload,
    })
    handleIncomingGroupMembersUpdate,
  }) : _facade = facade,
       _outboundService = outboundService,
       _groupFlowService = groupFlowService,
       _outboundCodec = outboundCodec,
       _storage = storage,
       _persistChatSummary = persistChatSummary,
       _ensureGroupKey = ensureGroupKey,
       _encryptGroupBytes = encryptGroupBytes,
       _encryptGroupText = encryptGroupText,
       _collectGroupRecipients = collectGroupRecipients,
       _replySenderLabel = replySenderLabel,
       _replyTextPreview = replyTextPreview,
       _replyKind = replyKind,
       _updateFileProgress = updateFileProgress,
       _rememberOutgoingRelayMediaState = rememberOutgoingRelayMediaState,
       _forgetOutgoingRelayMediaState = forgetOutgoingRelayMediaState,
       _replaceMessage = replaceMessage,
       _clearProgressUpdate = clearProgressUpdate,
       _transferStatusForError = transferStatusForError,
       _setStatus = setStatus,
       _notifyMessageUpdated = notifyMessageUpdated,
       _updateMessageStatusById = updateMessageStatusById,
       _handleIncomingGroupMembersUpdate = handleIncomingGroupMembersUpdate;

  final NodeFacade _facade;
  final ChatOutboundService _outboundService;
  final ChatGroupFlowService _groupFlowService;
  final ChatOutboundCodec _outboundCodec;
  final StorageService _storage;
  final Future<void> Function(Chat chat) _persistChatSummary;
  final Future<String> Function(Chat chat) _ensureGroupKey;
  final Future<Uint8List?> Function({
    required String groupId,
    required Uint8List plainBytes,
  })
  _encryptGroupBytes;
  final Future<String?> Function({
    required String groupId,
    required String plainText,
  })
  _encryptGroupText;
  final List<String> Function(Chat chat) _collectGroupRecipients;
  final String? Function(String chatPeerId, Message? replyTo) _replySenderLabel;
  final String? Function(Message? replyTo) _replyTextPreview;
  final String? Function(Message? replyTo) _replyKind;
  final Future<void> Function(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  })
  _updateFileProgress;
  final Future<void> Function(OutgoingRelayMediaState state)
  _rememberOutgoingRelayMediaState;
  final Future<void> Function(String peerId, String messageId)
  _forgetOutgoingRelayMediaState;
  final Future<void> Function(
    String peerId,
    String messageId,
    Message Function(Message current) transform,
  )
  _replaceMessage;
  final void Function(String peerId, String messageId) _clearProgressUpdate;
  final String Function(Object error, {required String fallback})
  _transferStatusForError;
  final void Function(
    String peerId,
    ChatConnectionStatus status, {
    String? error,
  })
  _setStatus;
  final void Function(String peerId) _notifyMessageUpdated;
  final Future<void> Function(
    String peerId,
    String messageId,
    MessageStatus status,
  )
  _updateMessageStatusById;
  final Future<void> Function(
    ChatMessage message, {
    IncomingGroupMembersPayload? payload,
  })
  _handleIncomingGroupMembersUpdate;

  Future<void> sendGroupFile(
    Chat groupChat, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) {
    return _outboundService.sendGroupFile(
      groupChat,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
      persistChatSummary: _persistChatSummary,
      collectGroupRecipients: _collectGroupRecipients,
      ensureGroupKey: _ensureGroupKey,
      encryptGroupBytes: _encryptGroupBytes,
      encryptGroupText: _encryptGroupText,
      replySenderLabel: _replySenderLabel,
      replyTextPreview: _replyTextPreview,
      replyKind: _replyKind,
      updateFileProgress: _updateFileProgress,
      rememberOutgoingRelayMediaState: _rememberOutgoingRelayMediaState,
      forgetOutgoingRelayMediaState: _forgetOutgoingRelayMediaState,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: _clearProgressUpdate,
      saveMediaFile: _storage.saveMediaFile,
      saveMediaBytes: _storage.saveMediaBytes,
      transferStatusForError: _transferStatusForError,
      setStatus: _setStatus,
      notifyMessageUpdated: _notifyMessageUpdated,
    );
  }

  Future<void> sendGroupMessage(Chat groupChat, Message message) {
    return _outboundService.sendGroupMessage(
      groupChat,
      message,
      persistChatSummary: _persistChatSummary,
      ensureGroupKey: _ensureGroupKey,
      encryptGroupBytes: _encryptGroupBytes,
      encryptGroupText: _encryptGroupText,
      collectGroupRecipients: _collectGroupRecipients,
      updateMessageStatusById: _updateMessageStatusById,
      setStatus: _setStatus,
    );
  }

  Future<void> requestDeleteForEveryone(
    String peerId,
    String messageId, {
    required Chat? chat,
  }) async {
    try {
      if (chat != null && chat.isGroup) {
        final recipients = chat.memberPeerIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty && item != _facade.peerId)
            .toSet()
            .toList(growable: false);
        final payload = _outboundCodec.encodeGroupDeletePayload(
          groupId: chat.peerId,
          messageId: messageId,
        );
        for (var i = 0; i < recipients.length; i++) {
          await _facade.sendPayload(
            recipients[i],
            text: payload,
            messageId: 'delete:$messageId:$i',
          );
        }
        return;
      }
      await _facade.sendDeleteMessage(peerId, messageId);
    } catch (e, stack) {
      developer.log('[chat] delete request failed: $e\n$stack', name: 'chat');
    }
  }

  Future<void> broadcastGroupChatDelete(Chat groupChat) {
    return _groupFlowService.broadcastGroupChatDelete(groupChat);
  }

  Future<void> sendGroupLeaveBeforeLocalDelete(Chat groupChat) {
    return _groupFlowService.sendGroupLeaveBeforeLocalDelete(groupChat);
  }

  Future<void> broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) {
    return _groupFlowService.broadcastGroupMembersUpdate(
      groupChat: groupChat,
      recipients: recipients,
      action: action,
      changedPeerIds: changedPeerIds,
      avatarBlobId: avatarBlobId,
      avatarMimeType: avatarMimeType,
      avatarFileSizeBytes: avatarFileSizeBytes,
      avatarUpdatedAtMs: avatarUpdatedAtMs,
    );
  }

  Future<void> applyGroupMembersUpdateFromPush(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  }) async {
    final senderPeerId = sourcePeerId?.trim().isNotEmpty == true
        ? sourcePeerId!.trim()
        : (payload['senderPeerId'] as String? ?? '').trim();
    if (senderPeerId.isEmpty) {
      return;
    }
    final message = ChatMessage(
      id: 'push-group-members:${DateTime.now().microsecondsSinceEpoch}',
      peerId: senderPeerId,
      kind: 'groupMembers',
      text: '${ChatOutboundCodec.groupMembersPrefix}${jsonEncode(payload)}',
    );
    await _handleIncomingGroupMembersUpdate(message);
  }
}
