import 'dart:typed_data';

import '../models/message.dart';

class ChatMessageCopy {
  static const Object _sentinel = Object();

  static Message copy(
    Message source, {
    String? text,
    String? senderPeerId,
    bool? incoming,
    DateTime? timestamp,
    MessageKind? kind,
    String? fileName,
    String? mimeType,
    Object? fileDataBase64 = _sentinel,
    Object? localFilePath = _sentinel,
    String? transferId,
    int? fileSizeBytes,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
    Object? transferredBytes = _sentinel,
    Object? sendProgress = _sentinel,
    Object? transferStatus = _sentinel,
    MessageStatus? status,
    bool? isRead,
  }) {
    return Message(
      id: source.id,
      peerId: source.peerId,
      text: text ?? source.text,
      senderPeerId: senderPeerId ?? source.senderPeerId,
      incoming: incoming ?? source.incoming,
      timestamp: timestamp ?? source.timestamp,
      kind: kind ?? source.kind,
      fileName: fileName ?? source.fileName,
      mimeType: mimeType ?? source.mimeType,
      fileDataBase64: identical(fileDataBase64, _sentinel)
          ? source.fileDataBase64
          : fileDataBase64 as String?,
      localFilePath: identical(localFilePath, _sentinel)
          ? source.localFilePath
          : localFilePath as String?,
      transferId: transferId ?? source.transferId,
      fileSizeBytes: fileSizeBytes ?? source.fileSizeBytes,
      replyToMessageId: replyToMessageId ?? source.replyToMessageId,
      replyToSenderPeerId: replyToSenderPeerId ?? source.replyToSenderPeerId,
      replyToSenderLabel: replyToSenderLabel ?? source.replyToSenderLabel,
      replyToTextPreview: replyToTextPreview ?? source.replyToTextPreview,
      replyToKind: replyToKind ?? source.replyToKind,
      transferredBytes: identical(transferredBytes, _sentinel)
          ? source.transferredBytes
          : transferredBytes as int?,
      sendProgress: identical(sendProgress, _sentinel)
          ? source.sendProgress
          : sendProgress as double?,
      transferStatus: identical(transferStatus, _sentinel)
          ? source.transferStatus
          : transferStatus as String?,
      status: status ?? source.status,
      isRead: isRead ?? source.isRead,
    );
  }
}

class QueuedFileTransfer {
  final String peerId;
  final String messageId;
  final String fileName;
  final Uint8List? fileBytes;
  final String? filePath;
  final int fileSizeBytes;
  final String? mimeType;
  final Message? replyTo;

  const QueuedFileTransfer({
    required this.peerId,
    required this.messageId,
    required this.fileName,
    required this.fileBytes,
    required this.filePath,
    required this.fileSizeBytes,
    required this.mimeType,
    required this.replyTo,
  });
}
