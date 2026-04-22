import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum MessageStatus {
  sending,
  sent,
  failed,
}

enum MessageKind {
  text,
  file,
}

class Message {
  final String id;
  final String peerId;
  final String text;
  final String? senderPeerId;
  final bool incoming;
  final DateTime timestamp;
  final MessageKind kind;
  final String? fileName;
  final String? mimeType;
  final String? fileDataBase64;
  final String? localFilePath;
  final String? transferId;
  final int? fileSizeBytes;
  final String? replyToMessageId;
  final String? replyToSenderPeerId;
  final String? replyToSenderLabel;
  final String? replyToTextPreview;
  final String? replyToKind;
  int? transferredBytes;
  double? sendProgress;
  String? transferStatus;
  MessageStatus status;
  bool isRead;

  Message({
    required this.id,
    required this.peerId,
    required this.text,
    this.senderPeerId,
    required this.incoming,
    required this.timestamp,
    this.kind = MessageKind.text,
    this.fileName,
    this.mimeType,
    this.fileDataBase64,
    this.localFilePath,
    this.transferId,
    this.fileSizeBytes,
    this.replyToMessageId,
    this.replyToSenderPeerId,
    this.replyToSenderLabel,
    this.replyToTextPreview,
    this.replyToKind,
    this.transferredBytes,
    this.sendProgress,
    this.transferStatus,
    this.status = MessageStatus.sent,
    bool? isRead,
  }) : isRead = isRead ?? !incoming;

  factory Message.fromJson(Map<String, dynamic> json) {
    final hasReadFlag = json.containsKey('isRead');
    return Message(
      id: json['id'] as String,
      peerId: json['peerId'] as String,
      text: json['text'] as String,
      senderPeerId: json['senderPeerId'] as String?,
      incoming: json['incoming'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      kind: MessageKind.values.firstWhere(
        (value) => value.name == (json['kind'] as String? ?? 'text'),
        orElse: () => MessageKind.text,
      ),
      fileName: json['fileName'] as String?,
      mimeType: json['mimeType'] as String?,
      fileDataBase64: json['fileDataBase64'] as String?,
      localFilePath: json['localFilePath'] as String?,
      transferId: json['transferId'] as String?,
      fileSizeBytes: json['fileSizeBytes'] as int?,
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToSenderPeerId: json['replyToSenderPeerId'] as String?,
      replyToSenderLabel: json['replyToSenderLabel'] as String?,
      replyToTextPreview: json['replyToTextPreview'] as String?,
      replyToKind: json['replyToKind'] as String?,
      transferredBytes: json['transferredBytes'] as int?,
      sendProgress: (json['sendProgress'] as num?)?.toDouble(),
      transferStatus: json['transferStatus'] as String?,
      status: MessageStatus.values.firstWhere(
        (s) => s.name == (json['status'] as String? ?? 'sent'),
        orElse: () => MessageStatus.sent,
      ),
      isRead: hasReadFlag ? json['isRead'] as bool? : true,
    );
  }

  factory Message.fromSummaryJson(Map<String, dynamic> json) {
    final sanitized = Map<String, dynamic>.from(json)
      ..remove('fileDataBase64')
      ..remove('transferredBytes')
      ..remove('sendProgress')
      ..remove('transferStatus');
    return Message.fromJson(sanitized);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'peerId': peerId,
      'text': text,
      'senderPeerId': senderPeerId,
      'incoming': incoming,
      'timestamp': timestamp.toIso8601String(),
      'kind': kind.name,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileDataBase64': fileDataBase64,
      'localFilePath': localFilePath,
      'transferId': transferId,
      'fileSizeBytes': fileSizeBytes,
      'replyToMessageId': replyToMessageId,
      'replyToSenderPeerId': replyToSenderPeerId,
      'replyToSenderLabel': replyToSenderLabel,
      'replyToTextPreview': replyToTextPreview,
      'replyToKind': replyToKind,
      'transferredBytes': transferredBytes,
      'sendProgress': sendProgress,
      'transferStatus': transferStatus,
      'status': status.name,
      'isRead': isRead,
    };
  }

  Map<String, dynamic> toPersistentJson() {
    return {
      'id': id,
      'peerId': peerId,
      'text': text,
      'senderPeerId': senderPeerId,
      'incoming': incoming,
      'timestamp': timestamp.toIso8601String(),
      'kind': kind.name,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileDataBase64': null,
      'localFilePath': localFilePath,
      'transferId': transferId,
      'fileSizeBytes': fileSizeBytes,
      'replyToMessageId': replyToMessageId,
      'replyToSenderPeerId': replyToSenderPeerId,
      'replyToSenderLabel': replyToSenderLabel,
      'replyToTextPreview': replyToTextPreview,
      'replyToKind': replyToKind,
      'transferredBytes': transferredBytes,
      'sendProgress': sendProgress,
      'transferStatus': transferStatus,
      'status': status.name,
      'isRead': isRead,
    };
  }

  Map<String, dynamic> toSummaryJson() {
    return {
      'id': id,
      'peerId': peerId,
      'text': text,
      'senderPeerId': senderPeerId,
      'incoming': incoming,
      'timestamp': timestamp.toIso8601String(),
      'kind': kind.name,
      'fileName': fileName,
      'mimeType': mimeType,
      'localFilePath': localFilePath,
      'fileSizeBytes': fileSizeBytes,
      'replyToMessageId': replyToMessageId,
      'replyToSenderPeerId': replyToSenderPeerId,
      'replyToSenderLabel': replyToSenderLabel,
      'replyToTextPreview': replyToTextPreview,
      'replyToKind': replyToKind,
      'status': status.name,
      'isRead': isRead,
    };
  }

  Uint8List? get fileBytes {
    final raw = fileDataBase64;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return Uint8List.fromList(base64Decode(raw));
  }

  File? get localFile {
    final path = localFilePath;
    if (path == null || path.isEmpty) {
      return null;
    }
    return File(path);
  }

  double? get transferProgress {
    if (sendProgress != null) {
      return sendProgress;
    }
    final total = fileSizeBytes;
    final transferred = transferredBytes;
    if (total == null || total <= 0 || transferred == null) {
      return null;
    }
    return (transferred / total).clamp(0.0, 1.0);
  }

  String? get fileExtension {
    final rawName = fileName ?? text;
    final dotIndex = rawName.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < rawName.length - 1) {
      return rawName.substring(dotIndex + 1).toLowerCase();
    }
    final rawMime = mimeType?.toLowerCase();
    if (rawMime == null || rawMime.isEmpty) {
      return null;
    }
    if (rawMime.contains('/')) {
      return rawMime.split('/').last;
    }
    return rawMime;
  }

  bool get isImage {
    final extension = fileExtension;
    if (extension == null) {
      return false;
    }
    return const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
    }.contains(extension);
  }

  bool get isVideo {
    final extension = fileExtension;
    if (extension == null) {
      return false;
    }
    return const {
      'mp4',
      'mov',
      'm4v',
      'avi',
      'mkv',
      'webm',
      '3gp',
      'mpeg',
      'mpg',
    }.contains(extension);
  }

  bool get isMedia => isImage || isVideo;

  bool get isAudio {
    final extension = fileExtension;
    if (extension == null) {
      return false;
    }
    return const {
      'm4a',
      'aac',
      'mp3',
      'wav',
      'ogg',
      'oga',
      'opus',
      'amr',
      'caf',
      'flac',
    }.contains(extension);
  }

  bool get isPendingOutgoingTransfer {
    if (incoming || kind != MessageKind.file) {
      return false;
    }
    if (status != MessageStatus.sending) {
      return false;
    }
    final progress = transferProgress;
    return progress == null || progress < 1.0;
  }

  bool get isQueuedOutgoingTransfer {
    if (!isPendingOutgoingTransfer) {
      return false;
    }
    final statusText = transferStatus;
    if (statusText == null) {
      return false;
    }
    return statusText == 'В очереди' || statusText.startsWith('Ожидает отправки');
  }

  bool get isActiveOutgoingTransfer {
    return isPendingOutgoingTransfer && !isQueuedOutgoingTransfer;
  }
}
