import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/node/node_facade.dart';
import '../../core/relay/relay_media_transfer_service.dart';
import '../../core/relay/relay_models.dart';
import '../../core/runtime/app_file_logger.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_media_restore_service.dart';
import 'chat_outbound_codec.dart';

class ChatIncomingMediaRestoreCoordinator {
  const ChatIncomingMediaRestoreCoordinator({
    required ChatMediaRestoreService mediaRestoreService,
    required ChatOutboundCodec outboundCodec,
    required NodeFacade facade,
    required Future<Uint8List> Function({
      required String groupId,
      required Uint8List encryptedBytes,
    })
    decodeGroupBlobBytes,
  }) : _mediaRestoreService = mediaRestoreService,
       _outboundCodec = outboundCodec,
       _facade = facade,
       _decodeGroupBlobBytes = decodeGroupBlobBytes;

  final ChatMediaRestoreService _mediaRestoreService;
  final ChatOutboundCodec _outboundCodec;
  final NodeFacade _facade;
  final Future<Uint8List> Function({
    required String groupId,
    required Uint8List encryptedBytes,
  })
  _decodeGroupBlobBytes;

  Future<void> resumeInterruptedIncomingMediaQueue({
    required Iterable<Chat> chats,
    required String reason,
  }) async {
    var resumed = 0;
    for (final chat in chats) {
      resumed += await resumeInterruptedIncomingMediaForChat(
        chat,
        reason: reason,
      );
    }
    if (resumed > 0) {
      AppFileLogger.log(
        '[chat_media] incoming resume reason=$reason count=$resumed',
      );
    }
  }

  Future<int> resumeInterruptedIncomingMediaForChat(
    Chat chat, {
    required String reason,
  }) async {
    if (!chat.messagesLoaded) {
      return 0;
    }
    var resumed = 0;
    for (final message in chat.messages.toList(growable: false)) {
      if (!shouldResumeIncomingMedia(message)) {
        continue;
      }
      final isGroup = (message.transferId ?? '').startsWith('grpblob:');
      AppFileLogger.log(
        '[chat_media] incoming resume reason=$reason peer=${message.peerId} '
        'messageId=${message.id} group=$isGroup',
      );
      restoreMediaInBackground(message, isGroup: isGroup, force: true);
      resumed += 1;
    }
    return resumed;
  }

  Future<String?> restoreGroupBlobMedia(Message message) {
    return _mediaRestoreService.restoreIncomingRelayMediaOnce(
      message,
      isGroup: true,
      restoreGroup: () => _restoreGroupBlobMediaFromRelay(message),
      restoreDirect: () => _restoreDirectBlobMediaFromRelay(message),
    );
  }

  Future<String?> restoreDirectBlobMedia(Message message) {
    return _mediaRestoreService.restoreIncomingRelayMediaOnce(
      message,
      isGroup: false,
      restoreGroup: () => _restoreGroupBlobMediaFromRelay(message),
      restoreDirect: () => _restoreDirectBlobMediaFromRelay(message),
    );
  }

  void restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
  }) {
    _mediaRestoreService.restoreMediaInBackground(
      message,
      isGroup: isGroup,
      force: force,
      restoreInBackground:
          (message, {required bool isGroup, bool force = false}) {
            final future = isGroup
                ? restoreGroupBlobMedia(message)
                : restoreDirectBlobMedia(message);
            unawaited(future);
          },
    );
  }

  bool isIncomingRelayMediaRestoreInProgress(Message message) {
    return _mediaRestoreService.isIncomingRelayMediaRestoreInProgress(message);
  }

  bool isIncomingRelayMediaRestoreFailed(Message message) {
    return _mediaRestoreService.isIncomingRelayMediaRestoreFailed(message);
  }

  bool isInitialUnreadAnchor(Message message) {
    if (!message.incoming || message.isRead) {
      return false;
    }
    return !isFailedIncomingMediaPlaceholder(message);
  }

  bool isFailedIncomingMediaPlaceholder(Message message) {
    if (!message.incoming || message.kind != MessageKind.file) {
      return false;
    }
    if (message.localFilePath?.trim().isNotEmpty == true) {
      return false;
    }
    return isIncomingRelayMediaRestoreFailed(message);
  }

  bool shouldAutoRestoreIncomingMedia(Message message) {
    return shouldResumeIncomingMedia(message) ||
        ((message.transferStatus ?? '').trim().isEmpty &&
            _mediaRestoreService.isIncomingRelayMediaPlaceholder(message));
  }

  bool shouldResumeIncomingMedia(Message message) {
    return _mediaRestoreService.shouldResumeIncomingMedia(message);
  }

  bool isStaleIncomingRelayProgress({
    required String? currentStatus,
    required double? currentProgress,
    required String nextStatus,
    required double? nextProgress,
  }) {
    return _mediaRestoreService.isStaleIncomingRelayProgress(
      currentStatus: currentStatus,
      currentProgress: currentProgress,
      nextStatus: nextStatus,
      nextProgress: nextProgress,
    );
  }

  Future<String?> restoreMediaFromRelay({
    required String peerId,
    required String messageId,
    required String blobId,
    required String? fileName,
    required RelayMediaDownloadOperation downloadBlob,
    Future<Uint8List> Function(RelayBlobDownload blob)? transformPayload,
    String? transformStatus,
  }) {
    return _mediaRestoreService.restoreMediaFromRelay(
      peerId: peerId,
      messageId: messageId,
      blobId: blobId,
      fileName: fileName,
      downloadBlob: downloadBlob,
      restoreInBackground:
          (message, {required bool isGroup, bool force = false}) {
            restoreMediaInBackground(message, isGroup: isGroup, force: true);
          },
      transformPayload: transformPayload,
      transformStatus: transformStatus,
    );
  }

  Future<String?> restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  }) async {
    try {
      final blob = await _facade.downloadBlob(blobId);
      if (blob.isNotFound) {
        return fallback;
      }
      final bytes = await _decodeGroupBlobBytes(
        groupId: groupId,
        encryptedBytes: blob.payload,
      );
      return utf8.decode(bytes);
    } catch (_) {
      return fallback;
    }
  }

  Future<String?> _restoreGroupBlobMediaFromRelay(Message message) async {
    final route = _outboundCodec.parseGroupBlobTransferId(message.transferId);
    if (route == null) {
      return null;
    }

    return restoreMediaFromRelay(
      peerId: route.groupId,
      messageId: route.messageId,
      blobId: route.blobId,
      fileName: message.fileName,
      downloadBlob: (onProgress) =>
          _facade.downloadBlob(route.blobId, onProgress: onProgress),
      transformStatus: RelayMediaTransferService.incomingDecryptStatus,
      transformPayload: (blob) {
        return _decodeGroupBlobBytes(
          groupId: route.groupId,
          encryptedBytes: blob.payload,
        );
      },
    );
  }

  Future<String?> _restoreDirectBlobMediaFromRelay(Message message) async {
    final route = _outboundCodec.parseDirectBlobTransferId(message.transferId);
    if (route == null) {
      return null;
    }

    return restoreMediaFromRelay(
      peerId: route.peerId,
      messageId: route.messageId,
      blobId: route.blobId,
      fileName: message.fileName,
      downloadBlob: (onProgress) =>
          _facade.downloadBlob(route.blobId, onProgress: onProgress),
    );
  }
}
