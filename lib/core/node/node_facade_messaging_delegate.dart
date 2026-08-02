import 'dart:typed_data';

import '../messaging/chat_service.dart';
import '../messaging/reliable_messaging_service.dart';
import '../relay/relay_models.dart';

class NodeFacadeMessagingDelegate {
  NodeFacadeMessagingDelegate(this._chat);

  final ChatService _chat;

  Future<ChatSendReceipt> sendPayload(
    String targetId, {
    ChatPayloadTargetKind targetKind = ChatPayloadTargetKind.direct,
    List<String>? recipients,
    required String text,
    String kind = 'text',
    String? messageId,
    String? fileName,
    String? mimeType,
    String? transferId,
    int? totalBytes,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
  }) {
    return _chat.sendPayload(
      targetId,
      targetKind: targetKind,
      recipients: recipients,
      text: text,
      kind: kind,
      messageId: messageId,
      fileName: fileName,
      mimeType: mimeType,
      transferId: transferId,
      totalBytes: totalBytes,
      replyToMessageId: replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel,
      replyToTextPreview: replyToTextPreview,
      replyToKind: replyToKind,
    );
  }

  Future<void> updateRelayGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  }) {
    return _chat.updateGroupMembers(
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
    );
  }

  Future<String> uploadBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    return _chat.uploadBlob(
      scopeKind: scopeKind,
      targetId: targetId,
      fileName: fileName,
      mimeType: mimeType,
      bytes: bytes,
      blobId: blobId,
      onProgress: onProgress,
    );
  }

  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) {
    return _chat.downloadBlob(blobId, onProgress: onProgress);
  }

  Future<void> sendDeleteMessage(String peerId, String messageId) {
    return _chat.sendControlMessage(peerId, kind: 'delete', text: messageId);
  }

  Future<void> sendPlainControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _chat.sendControlMessage(
      peerId,
      kind: kind,
      text: text,
      forcePlain: true,
    );
  }

  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) {
    return _chat.sendControlMessage(peerId, kind: kind, text: text);
  }

  Future<void> sendFile(
    String peerId, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int totalBytes,
    String? mimeType,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
    required bool Function() isCancelled,
    required void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })
    onProgress,
  }) {
    return _chat.sendFile(
      peerId,
      messageId: messageId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      totalBytes: totalBytes,
      mimeType: mimeType,
      replyToMessageId: replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel,
      replyToTextPreview: replyToTextPreview,
      replyToKind: replyToKind,
      isCancelled: isCancelled,
      onProgress: onProgress,
    );
  }
}
