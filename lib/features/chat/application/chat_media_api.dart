// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_file_progress_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_file_queue_service.dart';
import 'package:peerlink/features/chat/application/chat_file_send_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_file_transfer_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_incoming_media_restore_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_media_restore_service.dart';
import 'package:peerlink/features/chat/application/chat_media_thumbnail_service.dart';
import 'package:peerlink/features/chat/application/chat_outgoing_relay_media_resume_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';

abstract interface class ChatMediaApi {
  String get incomingRelayFetchStatus;

  Future<void> sendFile(
    String peerId, {
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    int? fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  });

  Future<void> cancelFileTransfer(String peerId, String messageId);

  Future<void> drainFileQueue();

  void resumeRecoverableFileQueue();

  Future<void> resumePendingOutgoingRelayMedia({required String reason});

  Future<void> resumeInterruptedIncomingMediaQueue({required String reason});

  Future<void> rememberOutgoingRelayMediaState(OutgoingRelayMediaState state);

  Future<void> forgetOutgoingRelayMediaState(String peerId, String messageId);

  Future<void> updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  });

  void clearProgressUpdate(String peerId, String messageId);

  String transferStatusForError(Object error, {required String fallback});

  String incomingMediaKey(String peerId, String messageId);

  Future<String?> restoreMediaFromEmbedded(String peerId, Message message);

  Future<String?> restoreGroupBlobMedia(Message message);

  Future<String?> restoreDirectBlobMedia(Message message);

  Future<String?> ensureThumbnail(Message message);

  void restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force,
  });

  bool isIncomingRelayMediaRestoreInProgress(Message message);

  bool isIncomingRelayMediaRestoreFailed(Message message);

  bool isInitialUnreadAnchor(Message message);

  bool shouldAutoRestoreIncomingMedia(Message message);

  Future<String?> restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  });

  void refreshQueuedFileStatuses();

  void dispose();
}

class ChatControllerMediaApi implements ChatMediaApi {
  const ChatControllerMediaApi({
    required ChatFileSendCoordinator fileSendCoordinator,
    required ChatFileTransferCoordinator fileTransferCoordinator,
    required ChatFileProgressCoordinator fileProgressCoordinator,
    required ChatIncomingMediaRestoreCoordinator
    incomingMediaRestoreCoordinator,
    required ChatOutgoingRelayMediaResumeService
    outgoingRelayMediaResumeService,
    required ChatMediaThumbnailService mediaThumbnailService,
    required ChatMediaRestoreService mediaRestoreService,
    required RelayMediaRetryCoordinator relayMediaRetry,
    required ChatFileQueueService fileQueueService,
    required Map<String, Chat> chats,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat? Function(String peerId) findChat,
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
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(String message) logQueue,
    required Future<String?> Function({
      required String peerId,
      required Message message,
    })
    restoreMediaFromEmbedded,
  }) : _fileSendCoordinator = fileSendCoordinator,
       _fileTransferCoordinator = fileTransferCoordinator,
       _fileProgressCoordinator = fileProgressCoordinator,
       _incomingMediaRestoreCoordinator = incomingMediaRestoreCoordinator,
       _outgoingRelayMediaResumeService = outgoingRelayMediaResumeService,
       _mediaThumbnailService = mediaThumbnailService,
       _mediaRestoreService = mediaRestoreService,
       _relayMediaRetry = relayMediaRetry,
       _fileQueueService = fileQueueService,
       _chats = chats,
       _ensureChatLoaded = ensureChatLoaded,
       _findChat = findChat,
       _replaceMessage = replaceMessage,
       _setStatus = setStatus,
       _notifyMessageUpdated = notifyMessageUpdated,
       _logQueue = logQueue,
       _restoreMediaFromEmbedded = restoreMediaFromEmbedded;

  final ChatFileSendCoordinator _fileSendCoordinator;
  final ChatFileTransferCoordinator _fileTransferCoordinator;
  final ChatFileProgressCoordinator _fileProgressCoordinator;
  final ChatIncomingMediaRestoreCoordinator _incomingMediaRestoreCoordinator;
  final ChatOutgoingRelayMediaResumeService _outgoingRelayMediaResumeService;
  final ChatMediaThumbnailService _mediaThumbnailService;
  final ChatMediaRestoreService _mediaRestoreService;
  final RelayMediaRetryCoordinator _relayMediaRetry;
  final ChatFileQueueService _fileQueueService;
  final Map<String, Chat> _chats;
  final Future<void> Function(String peerId) _ensureChatLoaded;
  final Chat? Function(String peerId) _findChat;
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
  final void Function(String peerId) _notifyMessageUpdated;
  final void Function(String message) _logQueue;
  final Future<String?> Function({
    required String peerId,
    required Message message,
  })
  _restoreMediaFromEmbedded;

  @override
  String get incomingRelayFetchStatus =>
      RelayMediaTransferService.incomingFetchStatus;

  @override
  Future<void> sendFile(
    String peerId, {
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    int? fileSizeBytes,
    String? mimeType,
    Message? replyTo,
  }) {
    return _fileSendCoordinator.sendFile(
      peerId,
      fileName: fileName,
      fileBytes: fileBytes,
      filePath: filePath,
      fileSizeBytes: fileSizeBytes,
      mimeType: mimeType,
      replyTo: replyTo,
    );
  }

  @override
  Future<void> cancelFileTransfer(String peerId, String messageId) {
    return _fileTransferCoordinator.cancelFileTransfer(peerId, messageId);
  }

  @override
  Future<void> drainFileQueue() {
    return _fileTransferCoordinator.drainFileQueue();
  }

  @override
  void resumeRecoverableFileQueue() {
    _fileTransferCoordinator.resumeRecoverableFileQueue();
  }

  @override
  Future<void> resumePendingOutgoingRelayMedia({required String reason}) {
    return _outgoingRelayMediaResumeService.resumePending(
      reason: reason,
      ensureChatLoaded: _ensureChatLoaded,
      findChat: _findChat,
      updateFileProgress: updateFileProgress,
      replaceMessage: _replaceMessage,
      clearProgressUpdate: clearProgressUpdate,
      setStatus: _setStatus,
      notifyMessageUpdated: _notifyMessageUpdated,
      logQueue: _logQueue,
    );
  }

  @override
  Future<void> resumeInterruptedIncomingMediaQueue({required String reason}) {
    return _incomingMediaRestoreCoordinator.resumeInterruptedIncomingMediaQueue(
      chats: _chats.values,
      reason: reason,
    );
  }

  @override
  Future<void> rememberOutgoingRelayMediaState(OutgoingRelayMediaState state) {
    return _outgoingRelayMediaResumeService.remember(state);
  }

  @override
  Future<void> forgetOutgoingRelayMediaState(String peerId, String messageId) {
    return _outgoingRelayMediaResumeService.forget(peerId, messageId);
  }

  @override
  Future<void> updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) {
    return _fileProgressCoordinator.updateFileProgress(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
    );
  }

  @override
  void clearProgressUpdate(String peerId, String messageId) {
    _fileProgressCoordinator.clearProgressUpdate(peerId, messageId);
  }

  @override
  String transferStatusForError(Object error, {required String fallback}) {
    return _fileProgressCoordinator.transferStatusForError(
      error,
      fallback: fallback,
    );
  }

  @override
  String incomingMediaKey(String peerId, String messageId) {
    return RelayMediaRetryCoordinator.mediaKey(peerId, messageId);
  }

  @override
  Future<String?> restoreMediaFromEmbedded(String peerId, Message message) {
    return _restoreMediaFromEmbedded(peerId: peerId, message: message);
  }

  @override
  Future<String?> restoreGroupBlobMedia(Message message) {
    return _incomingMediaRestoreCoordinator.restoreGroupBlobMedia(message);
  }

  @override
  Future<String?> restoreDirectBlobMedia(Message message) {
    return _incomingMediaRestoreCoordinator.restoreDirectBlobMedia(message);
  }

  @override
  Future<String?> ensureThumbnail(Message message) {
    return _mediaThumbnailService.ensureThumbnail(message);
  }

  @override
  void restoreMediaInBackground(
    Message message, {
    required bool isGroup,
    bool force = false,
  }) {
    _incomingMediaRestoreCoordinator.restoreMediaInBackground(
      message,
      isGroup: isGroup,
      force: force,
    );
  }

  @override
  bool isIncomingRelayMediaRestoreInProgress(Message message) {
    return _incomingMediaRestoreCoordinator
        .isIncomingRelayMediaRestoreInProgress(message);
  }

  @override
  bool isIncomingRelayMediaRestoreFailed(Message message) {
    return _incomingMediaRestoreCoordinator.isIncomingRelayMediaRestoreFailed(
      message,
    );
  }

  @override
  bool isInitialUnreadAnchor(Message message) {
    return _incomingMediaRestoreCoordinator.isInitialUnreadAnchor(message);
  }

  @override
  bool shouldAutoRestoreIncomingMedia(Message message) {
    return _incomingMediaRestoreCoordinator.shouldAutoRestoreIncomingMedia(
      message,
    );
  }

  @override
  Future<String?> restoreGroupBlobText({
    required String groupId,
    required String blobId,
    String? fallback,
  }) {
    return _incomingMediaRestoreCoordinator.restoreGroupBlobText(
      groupId: groupId,
      blobId: blobId,
      fallback: fallback,
    );
  }

  @override
  void refreshQueuedFileStatuses() {
    _fileTransferCoordinator.refreshQueuedFileStatuses();
  }

  @override
  void dispose() {
    _fileQueueService.dispose();
    _relayMediaRetry.dispose();
    _mediaRestoreService.dispose();
  }
}
