// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_parts.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';

typedef RestoreFindMessage =
    Future<Message?> Function(String peerId, String messageId);
typedef RestoreReplaceMessage =
    Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    );
typedef RestoreUpdateProgress =
    Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    });
typedef RestoreSaveMediaBytes =
    Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required Uint8List bytes,
    });
typedef RestoreEnsureThumbnail = Future<String?> Function(Message message);
typedef RestoreBackground =
    void Function(Message message, {required bool isGroup, bool force});
typedef RestoreGroupOrDirect = Future<String?> Function();

class ChatMediaRestoreService {
  final RelayMediaTransferService relayMediaTransfer;
  final RelayMediaRetryCoordinator relayMediaRetry;
  final RestoreFindMessage findMessage;
  final RestoreReplaceMessage replaceMessage;
  final RestoreUpdateProgress updateFileProgress;
  final RestoreSaveMediaBytes saveMediaBytes;
  final RestoreEnsureThumbnail ensureThumbnail;
  final void Function(String peerId, String messageId) clearProgressUpdate;
  final void Function(String peerId) notifyMessageUpdated;
  final String Function(String peerId, String messageId) mediaKeyFor;
  final bool Function() isMessageUpdatesClosed;

  final Map<String, Future<String?>> _activeRestores =
      <String, Future<String?>>{};

  ChatMediaRestoreService({
    required this.relayMediaTransfer,
    required this.relayMediaRetry,
    required this.findMessage,
    required this.replaceMessage,
    required this.updateFileProgress,
    required this.saveMediaBytes,
    required this.ensureThumbnail,
    required this.clearProgressUpdate,
    required this.notifyMessageUpdated,
    required this.mediaKeyFor,
    required this.isMessageUpdatesClosed,
  });

  void dispose() => _activeRestores.clear();

  bool isIncomingRelayMediaRestoreInProgress(Message message) {
    if (!isIncomingRelayMediaPlaceholder(message)) {
      return false;
    }
    final key = mediaKeyFor(message.peerId, message.id);
    if (_activeRestores.containsKey(key)) {
      return true;
    }
    final status = (message.transferStatus ?? '').trim();
    return isIncomingRelayMediaBusyStatus(status);
  }

  bool isIncomingRelayMediaRestoreFailed(Message message) {
    return isIncomingRelayMediaPlaceholder(message) &&
        _isIncomingRelayFailureStatus((message.transferStatus ?? '').trim());
  }

  bool shouldResumeIncomingMedia(Message message) {
    if (!isIncomingRelayMediaPlaceholder(message)) {
      return false;
    }
    final key = mediaKeyFor(message.peerId, message.id);
    if (_activeRestores.containsKey(key)) {
      return false;
    }
    final status = (message.transferStatus ?? '').trim();
    if (isIncomingRelayMediaBusyStatus(status) ||
        status == RelayMediaTransferService.incomingErrorStatus ||
        status == RelayMediaTransferService.incomingRelayUnavailableStatus) {
      return relayMediaRetry.isDue(key);
    }
    return status.isEmpty;
  }

  bool isIncomingRelayMediaPlaceholder(Message message) {
    if (!message.incoming || message.kind != MessageKind.file) {
      return false;
    }
    if (message.localFilePath?.isNotEmpty == true) {
      return false;
    }
    final transferId = (message.transferId ?? '').trim();
    return transferId.startsWith('dirblob:') ||
        transferId.startsWith('grpblob:');
  }

  bool isIncomingRelayMediaBusyStatus(String status) {
    return status == RelayMediaTransferService.incomingFetchStatus ||
        status == RelayMediaTransferService.incomingRetryStatus ||
        status == RelayMediaTransferService.incomingDownloadStatus ||
        status == RelayMediaTransferService.incomingCompleteStatus ||
        status == RelayMediaTransferService.incomingDecryptStatus ||
        status == RelayMediaTransferService.incomingSaveStatus;
  }

  bool isStaleIncomingRelayProgress({
    required String? currentStatus,
    required double? currentProgress,
    required String nextStatus,
    required double? nextProgress,
  }) {
    final currentRank = _incomingRelayMediaStatusRank(currentStatus);
    final nextRank = _incomingRelayMediaStatusRank(nextStatus);
    if (currentRank > nextRank && nextRank > 0) {
      return true;
    }

    if (currentRank == nextRank &&
        currentRank ==
            _incomingRelayMediaStatusRank(
              RelayMediaTransferService.incomingDownloadStatus,
            ) &&
        currentProgress != null &&
        nextProgress != null &&
        nextProgress < currentProgress) {
      return true;
    }

    return false;
  }

  Future<String?> restoreIncomingRelayMediaOnce(
    Message message, {
    required bool isGroup,
    required RestoreGroupOrDirect restoreGroup,
    required RestoreGroupOrDirect restoreDirect,
  }) {
    final key = mediaKeyFor(message.peerId, message.id);
    final activeRestore = _activeRestores[key];
    if (activeRestore != null) {
      return activeRestore;
    }

    relayMediaRetry.cancelTimerForKey(key);
    late final Future<String?> restoreFuture;
    restoreFuture = (isGroup ? restoreGroup() : restoreDirect())
        .catchError((Object error, StackTrace stackTrace) {
          AppFileLogger.log(
            '[chat_media] restore relay single-flight swallowed '
            'peer=${message.peerId} messageId=${message.id} error=$error',
          );
          return null;
        })
        .whenComplete(() {
          if (identical(_activeRestores[key], restoreFuture)) {
            _activeRestores.remove(key);
          }
        });
    _activeRestores[key] = restoreFuture;
    return restoreFuture;
  }

  void restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
    required RestoreBackground restoreInBackground,
  }) {
    if (force) {
      if (!isIncomingRelayMediaPlaceholder(message)) {
        return;
      }
    } else if (!_shouldAutoRestoreIncomingMedia(message)) {
      return;
    }
    final key = mediaKeyFor(message.peerId, message.id);
    if (_activeRestores.containsKey(key)) {
      return;
    }
    try {
      if (isGroup) {
        restoreInBackground(message, isGroup: true, force: true);
      } else {
        restoreInBackground(message, isGroup: false, force: true);
      }
    } catch (error) {
      AppFileLogger.log(
        '[chat_media] background restore failed peer=${message.peerId} '
        'messageId=${message.id} group=$isGroup error=$error',
      );
    }
  }

  Future<String?> restoreMediaFromRelay({
    required String peerId,
    required String messageId,
    required String blobId,
    required String? fileName,
    required RelayMediaDownloadOperation downloadBlob,
    required RestoreBackground restoreInBackground,
    Future<Uint8List> Function(RelayBlobDownload blob)? transformPayload,
    String? transformStatus,
    String? transferId,
  }) async {
    return _restoreMediaFromRelay(
      peerId: peerId,
      messageId: messageId,
      blobId: blobId,
      fileName: fileName,
      downloadBlob: downloadBlob,
      restoreInBackground: restoreInBackground,
      transformPayload: transformPayload,
      transformStatus: transformStatus,
      transferId: transferId,
    );
  }

  Future<String?> _restoreMediaFromRelay({
    required String peerId,
    required String messageId,
    required String blobId,
    required String? fileName,
    required RelayMediaDownloadOperation downloadBlob,
    required RestoreBackground restoreInBackground,
    Future<Uint8List> Function(RelayBlobDownload blob)? transformPayload,
    String? transformStatus,
    String? transferId,
  }) async {
    try {
      final result = await relayMediaTransfer.restoreIncomingMedia(
        peerId: peerId,
        messageId: messageId,
        blobId: blobId,
        fileName: fileName,
        downloadBlob: downloadBlob,
        transformPayload: transformPayload,
        transformStatus: transformStatus,
        transferId: transferId,
        saveBytes: ({required fileName, required bytes}) {
          return saveMediaBytes(
            peerId: peerId,
            messageId: messageId,
            fileName: fileName,
            bytes: bytes,
          );
        },
        onStage:
            ({
              required int? transferredBytes,
              required double? sendProgress,
              required String transferStatus,
            }) {
              return replaceMessage(
                peerId,
                messageId,
                (current) => ChatMessageCopy.copy(
                  current,
                  transferredBytes: transferredBytes,
                  sendProgress: sendProgress,
                  transferStatus: transferStatus,
                ),
              );
            },
        onProgress:
            ({
              required int receivedBytes,
              required int totalBytes,
              required String status,
            }) {
              unawaited(
                updateFileProgress(
                  peerId,
                  messageId,
                  sentBytes: receivedBytes,
                  totalBytes: totalBytes <= 0 ? null : totalBytes,
                  statusText: status,
                ),
              );
            },
      );

      if (!result.isSaved) {
        if (result.isNotFound) {
          AppFileLogger.log(
            '[chat_media] restore relay missing peer=$peerId '
            'messageId=$messageId blobId=$blobId',
          );
        }
        await _markIncomingRelayRestoreFailed(
          peerId: peerId,
          messageId: messageId,
          blobId: blobId,
          errorKind: result.errorKind,
          error: result.error,
          allowRetry: _allowsRelayRetry(result.errorKind),
          restoreInBackground: restoreInBackground,
        );
        return null;
      }

      final path = result.path;
      if (path == null || path.isEmpty) {
        await _markIncomingRelayRestoreFailed(
          peerId: peerId,
          messageId: messageId,
          blobId: blobId,
          errorKind: RelayMediaRestoreFailureKind.saveFailed,
          error: StateError('Relay restore returned empty path'),
          allowRetry: false,
          restoreInBackground: restoreInBackground,
        );
        return null;
      }

      clearProgressUpdate(peerId, messageId);
      AppFileLogger.log(
        '[chat_media] message-find-start peerId=$peerId '
        'messageId=$messageId blobId=$blobId localFilePath=$path',
      );
      final currentMessage = await findMessage(peerId, messageId);
      if (currentMessage == null) {
        AppFileLogger.log(
          '[chat_media] message-find-failed peerId=$peerId '
          'messageId=$messageId blobId=$blobId localFilePath=$path',
        );
        await _markIncomingRelayRestoreFailed(
          peerId: peerId,
          messageId: messageId,
          blobId: blobId,
          errorKind: 'message_update_failed',
          error: StateError('Message not found after relay media save'),
          allowRetry: false,
          restoreInBackground: restoreInBackground,
        );
        return null;
      }
      AppFileLogger.log(
        '[chat_media] message-find-success peerId=$peerId '
        'messageId=$messageId blobId=$blobId '
        'transferId=${currentMessage.transferId ?? ""} '
        'transferStatus=${currentMessage.transferStatus ?? ""}',
      );
      AppFileLogger.log(
        '[chat_media] message-replace-start peerId=$peerId '
        'messageId=$messageId blobId=$blobId localFilePath=$path',
      );
      await replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          localFilePath: path,
          fileDataBase64: null,
          transferredBytes: null,
          sendProgress: null,
          transferStatus: null,
        ),
      );
      AppFileLogger.log(
        '[chat_media] message-replace-success peerId=$peerId '
        'messageId=$messageId blobId=$blobId localFilePath=$path',
      );
      AppFileLogger.log(
        '[chat_media] retry-clear-start peerId=$peerId '
        'messageId=$messageId blobId=$blobId',
      );
      try {
        await relayMediaRetry.clear(peerId, messageId);
        AppFileLogger.log(
          '[chat_media] retry-clear-success peerId=$peerId '
          'messageId=$messageId blobId=$blobId',
        );
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[chat_media] retry-clear-failed peerId=$peerId '
          'messageId=$messageId blobId=$blobId localFilePath=$path '
          'exception=$error stackTrace=$stackTrace',
        );
      }
      notifyMessageUpdated(peerId);
      unawaited(
        _ensureThumbnailBestEffort(
          peerId: peerId,
          messageId: messageId,
          blobId: blobId,
          path: path,
          source: currentMessage,
        ),
      );
      return path;
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[chat_media] restore relay failed peer=$peerId '
        'messageId=$messageId blobId=$blobId exception=$error '
        'stackTrace=$stackTrace',
      );
      await _markIncomingRelayRestoreFailed(
        peerId: peerId,
        messageId: messageId,
        blobId: blobId,
        errorKind: error is RelayUnavailableException
            ? RelayMediaRestoreFailureKind.unavailable
            : 'message_update_failed',
        error: error,
        allowRetry: error is RelayUnavailableException,
        restoreInBackground: restoreInBackground,
      );
      return null;
    }
  }

  Future<void> _ensureThumbnailBestEffort({
    required String peerId,
    required String messageId,
    required String blobId,
    required String path,
    required Message source,
  }) async {
    try {
      AppFileLogger.log(
        '[chat_media] thumbnail-start peerId=$peerId messageId=$messageId '
        'blobId=$blobId localFilePath=$path',
      );
      final thumbnailPath = await ensureThumbnail(
        ChatMessageCopy.copy(source, localFilePath: path),
      );
      if (thumbnailPath == null || thumbnailPath.isEmpty) {
        AppFileLogger.log(
          '[chat_media] thumbnail-failed peerId=$peerId messageId=$messageId '
          'blobId=$blobId localFilePath=$path exception=empty-thumbnail',
        );
        return;
      }
      await replaceMessage(
        peerId,
        messageId,
        (current) =>
            ChatMessageCopy.copy(current, thumbnailPath: thumbnailPath),
      );
      AppFileLogger.log(
        '[chat_media] thumbnail-success peerId=$peerId messageId=$messageId '
        'blobId=$blobId localFilePath=$path thumbnailPath=$thumbnailPath',
      );
      if (!isMessageUpdatesClosed()) {
        notifyMessageUpdated(peerId);
      }
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[chat_media] thumbnail-failed peerId=$peerId messageId=$messageId '
        'blobId=$blobId localFilePath=$path exception=$error '
        'stackTrace=$stackTrace',
      );
    }
  }

  Future<void> markIncomingRelayRestoreFailed({
    required String peerId,
    required String messageId,
    required String blobId,
    required String errorKind,
    Object? error,
    bool allowRetry = true,
    required RestoreBackground restoreInBackground,
  }) {
    return _markIncomingRelayRestoreFailed(
      peerId: peerId,
      messageId: messageId,
      blobId: blobId,
      errorKind: errorKind,
      error: error,
      allowRetry: allowRetry,
      restoreInBackground: restoreInBackground,
    );
  }

  Future<void> _markIncomingRelayRestoreFailed({
    required String peerId,
    required String messageId,
    required String blobId,
    required String errorKind,
    Object? error,
    bool allowRetry = true,
    required RestoreBackground restoreInBackground,
  }) async {
    AppFileLogger.log(
      '[chat_media] restore relay mark failed peer=$peerId '
      'messageId=$messageId blobId=$blobId kind=$errorKind error=$error',
    );
    var canRetry = false;
    try {
      if (allowRetry) {
        AppFileLogger.log(
          '[chat_media] retry-record-start peerId=$peerId '
          'messageId=$messageId blobId=$blobId kind=$errorKind',
        );
        canRetry = await relayMediaRetry.recordFailure(
          peerId: peerId,
          messageId: messageId,
          errorKind: errorKind,
        );
        AppFileLogger.log(
          '[chat_media] retry-record-success peerId=$peerId '
          'messageId=$messageId blobId=$blobId kind=$errorKind '
          'canRetry=$canRetry',
        );
      }
    } catch (stateError) {
      AppFileLogger.log(
        '[chat_media] restore relay retry-state failed peer=$peerId '
        'messageId=$messageId error=$stateError',
      );
    }

    final transferStatus = canRetry
        ? RelayMediaTransferService.incomingRetryStatus
        : _failureStatus(errorKind, error);
    clearProgressUpdate(peerId, messageId);
    try {
      AppFileLogger.log(
        '[chat_media] message-replace-start peerId=$peerId '
        'messageId=$messageId blobId=$blobId transferStatus=$transferStatus',
      );
      await replaceMessage(
        peerId,
        messageId,
        (current) => ChatMessageCopy.copy(
          current,
          sendProgress: 0.0,
          transferStatus: transferStatus,
        ),
      );
      AppFileLogger.log(
        '[chat_media] message-replace-success peerId=$peerId '
        'messageId=$messageId blobId=$blobId transferStatus=$transferStatus',
      );
    } catch (updateError, updateStackTrace) {
      AppFileLogger.log(
        '[chat_media] message-replace-failed peerId=$peerId '
        'messageId=$messageId blobId=$blobId exception=$updateError '
        'stackTrace=$updateStackTrace',
      );
    }

    Message? failedMessage;
    try {
      AppFileLogger.log(
        '[chat_media] message-find-start peerId=$peerId '
        'messageId=$messageId blobId=$blobId',
      );
      failedMessage = await findMessage(peerId, messageId);
      AppFileLogger.log(
        '[chat_media] ${failedMessage == null ? "message-find-failed" : "message-find-success"} '
        'peerId=$peerId messageId=$messageId blobId=$blobId '
        'localFilePath=${failedMessage?.localFilePath ?? ""} '
        'transferStatus=${failedMessage?.transferStatus ?? ""}',
      );
    } catch (findError, findStackTrace) {
      AppFileLogger.log(
        '[chat_media] message-find-failed peerId=$peerId '
        'messageId=$messageId blobId=$blobId exception=$findError '
        'stackTrace=$findStackTrace',
      );
    }

    final key = mediaKeyFor(peerId, messageId);
    if (failedMessage != null &&
        failedMessage.incoming &&
        failedMessage.kind == MessageKind.file &&
        (failedMessage.localFilePath?.isNotEmpty != true) &&
        canRetry) {
      relayMediaRetry.scheduleRetry(
        peerId: peerId,
        messageId: messageId,
        findMessage: (retryPeerId, retryMessageId) async {
          final message = await findMessage(retryPeerId, retryMessageId);
          if (message == null) {
            return null;
          }
          return RelayRetryMessage(
            incoming: message.incoming,
            isFile: message.kind == MessageKind.file,
            localFilePath: message.localFilePath,
            transferId: message.transferId,
          );
        },
        markRetrying: (retryPeerId, retryMessageId) {
          return replaceMessage(
            retryPeerId,
            retryMessageId,
            (current) => ChatMessageCopy.copy(
              current,
              transferredBytes: 0,
              sendProgress: null,
              transferStatus: RelayMediaTransferService.incomingRetryStatus,
            ),
          );
        },
        restoreInBackground:
            (retryPeerId, retryMessageId, {required bool isGroup}) {
              final original = failedMessage;
              if (original == null ||
                  original.peerId != retryPeerId ||
                  original.id != retryMessageId) {
                return;
              }
              restoreInBackground(original, isGroup: isGroup, force: true);
            },
      );
    } else {
      relayMediaRetry.cancelTimerForKey(key);
    }

    if (!isMessageUpdatesClosed()) {
      notifyMessageUpdated(peerId);
    }
  }

  bool _shouldAutoRestoreIncomingMedia(Message message) {
    if (!isIncomingRelayMediaPlaceholder(message)) {
      return false;
    }
    final status = (message.transferStatus ?? '').trim();
    if (status.isEmpty) {
      return true;
    }
    if (isIncomingRelayMediaBusyStatus(status)) {
      return true;
    }
    if (status == RelayMediaTransferService.incomingErrorStatus ||
        status == RelayMediaTransferService.incomingRelayUnavailableStatus) {
      return relayMediaRetry.isDue(mediaKeyFor(message.peerId, message.id));
    }
    return false;
  }

  bool _isIncomingRelayFailureStatus(String status) {
    return status ==
            RelayMediaTransferService.incomingRelayNotConfiguredStatus ||
        status == RelayMediaTransferService.incomingErrorStatus ||
        status == RelayMediaTransferService.incomingDecryptErrorStatus ||
        status == RelayMediaTransferService.incomingSaveErrorStatus ||
        status == RelayMediaTransferService.incomingMessageUpdateErrorStatus ||
        status == RelayMediaTransferService.incomingRelayUnavailableStatus;
  }

  String _failureStatus(String errorKind, Object? error) {
    if (error is RelayUnavailableException) {
      return error.isNotConfigured
          ? RelayMediaTransferService.incomingRelayNotConfiguredStatus
          : RelayMediaTransferService.incomingRelayUnavailableStatus;
    }
    return switch (errorKind) {
      RelayMediaRestoreFailureKind.decryptFailed =>
        RelayMediaTransferService.incomingDecryptErrorStatus,
      RelayMediaRestoreFailureKind.saveFailed =>
        RelayMediaTransferService.incomingSaveErrorStatus,
      'message_update_failed' || 'persistence_failed' =>
        RelayMediaTransferService.incomingMessageUpdateErrorStatus,
      _ => RelayMediaTransferService.incomingErrorStatus,
    };
  }

  bool _allowsRelayRetry(String errorKind) {
    return errorKind == RelayMediaRestoreFailureKind.downloadFailed ||
        errorKind == RelayMediaRestoreFailureKind.unavailable;
  }

  int _incomingRelayMediaStatusRank(String? status) {
    final normalized = (status ?? '').trim();
    if (normalized == RelayMediaTransferService.incomingFetchStatus ||
        normalized == RelayMediaTransferService.incomingRetryStatus) {
      return 1;
    }
    if (normalized == RelayMediaTransferService.incomingDownloadStatus) {
      return 2;
    }
    if (normalized == RelayMediaTransferService.incomingCompleteStatus) {
      return 3;
    }
    if (normalized == RelayMediaTransferService.incomingDecryptStatus) {
      return 4;
    }
    if (normalized == RelayMediaTransferService.incomingSaveStatus) {
      return 5;
    }
    return 0;
  }
}
