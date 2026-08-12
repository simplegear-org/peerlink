import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_models.dart';
import 'chat_controller_parts.dart';

class ChatFileQueueService {
  static const Duration _progressThrottleInterval = Duration(milliseconds: 140);

  final Queue<QueuedFileTransfer> _fileSendQueue = Queue<QueuedFileTransfer>();
  final Map<String, PendingProgressUpdate> _pendingProgressUpdates =
      <String, PendingProgressUpdate>{};
  final Set<String> _cancelledFileTransfers = <String>{};

  bool _fileSendInFlight = false;
  String? _activeFileTransferId;

  bool get hasQueuedItems => _fileSendQueue.isNotEmpty;

  bool get isFileSendInFlight => _fileSendInFlight;

  void enqueue(QueuedFileTransfer item) {
    _fileSendQueue.add(item);
  }

  bool isQueuedOrActive(String messageId) {
    if (_activeFileTransferId == messageId) {
      return true;
    }
    return _fileSendQueue.any((item) => item.messageId == messageId);
  }

  Future<void> drain({
    required void Function(String message) logQueue,
    required Future<void> Function(QueuedFileTransfer item) sendFile,
    required Future<void> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required void Function() refreshQueuedFileStatuses,
  }) async {
    if (_fileSendInFlight) {
      logQueue('skip drain already in flight queued=${_fileSendQueue.length}');
      return;
    }

    _fileSendInFlight = true;
    try {
      while (_fileSendQueue.isNotEmpty) {
        final item = _fileSendQueue.removeFirst();
        logQueue(
          'start peer=${item.peerId} messageId=${item.messageId} '
          'remaining=${_fileSendQueue.length}',
        );
        if (_cancelledFileTransfers.remove(item.messageId)) {
          await removeMessageWithMediaCleanup(item.peerId, item.messageId);
          refreshQueuedFileStatuses();
          continue;
        }
        _activeFileTransferId = item.messageId;
        refreshQueuedFileStatuses();
        await sendFile(item);
        _activeFileTransferId = null;
        logQueue('done peer=${item.peerId} messageId=${item.messageId}');
        refreshQueuedFileStatuses();
      }
    } finally {
      _activeFileTransferId = null;
      _fileSendInFlight = false;
      logQueue('idle queued=${_fileSendQueue.length}');
      refreshQueuedFileStatuses();
    }
  }

  int recoverPendingTransfersForChat(
    Chat chat, {
    required bool Function(Message message) isRecoverableOutgoingFile,
    required Message? Function(String peerId, Message message) rebuildReply,
    required void Function(String peerId) schedulePersistLoadedChat,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function() refreshQueuedFileStatuses,
    required void Function(String message) logQueue,
  }) {
    if (chat.isGroup) {
      return 0;
    }
    var recovered = 0;
    var changed = false;
    for (var i = 0; i < chat.messages.length; i++) {
      final message = chat.messages[i];
      if (!isRecoverableOutgoingFile(message)) {
        continue;
      }
      final path = message.localFilePath?.trim();
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        chat.messages[i] = ChatMessageCopy.copy(
          message,
          transferredBytes: 0,
          sendProgress: 0.0,
          transferStatus: 'Файл недоступен',
          status: MessageStatus.failed,
        );
        changed = true;
        continue;
      }
      if (isQueuedOrActive(message.id)) {
        continue;
      }
      enqueue(
        QueuedFileTransfer(
          peerId: chat.peerId,
          messageId: message.id,
          fileName: message.fileName ?? message.text,
          fileBytes: null,
          filePath: path,
          fileSizeBytes: message.fileSizeBytes ?? File(path).lengthSync(),
          mimeType: message.mimeType,
          replyTo: rebuildReply(chat.peerId, message),
        ),
      );
      recovered += 1;
      changed = true;
    }
    if (changed) {
      schedulePersistLoadedChat(chat.peerId);
      notifyMessageUpdated(chat.peerId);
    }
    if (recovered > 0) {
      logQueue('recover peer=${chat.peerId} recovered=$recovered');
      refreshQueuedFileStatuses();
    }
    return recovered;
  }

  void resumeRecoverableFileQueue({
    required Iterable<Chat> chats,
    required int Function(Chat chat) recoverPendingTransfersForChat,
    required void Function(String message) logQueue,
    required void Function() refreshQueuedFileStatuses,
  }) {
    var recovered = 0;
    for (final chat in chats) {
      if (!chat.messagesLoaded) {
        continue;
      }
      recovered += recoverPendingTransfersForChat(chat);
    }
    logQueue(
      'resume recovered=$recovered queued=${_fileSendQueue.length} '
      'inFlight=$_fileSendInFlight',
    );
    if (_fileSendQueue.isNotEmpty) {
      refreshQueuedFileStatuses();
    }
  }

  Future<void> cancelFileTransfer(
    String peerId,
    String messageId, {
    required Future<void> Function(String peerId, String messageId)
    forgetOutgoingRelayMediaState,
    required Future<void> Function(String peerId, String messageId)
    removeMessageWithMediaCleanup,
    required void Function() refreshQueuedFileStatuses,
    required void Function(String peerId) notifyMessageUpdated,
  }) async {
    final queuedBefore = _fileSendQueue.length;
    _fileSendQueue.removeWhere((item) => item.messageId == messageId);
    final removedFromQueue = _fileSendQueue.length != queuedBefore;

    _cancelledFileTransfers.add(messageId);
    await forgetOutgoingRelayMediaState(peerId, messageId);
    await removeMessageWithMediaCleanup(peerId, messageId);
    if (removedFromQueue) {
      refreshQueuedFileStatuses();
    }
    notifyMessageUpdated(peerId);
  }

  bool removeCancelledTransfer(String messageId) {
    return _cancelledFileTransfers.remove(messageId);
  }

  bool isTransferCancelled(String messageId) {
    return _cancelledFileTransfers.contains(messageId);
  }

  void markTransferCancelled(String messageId) {
    _cancelledFileTransfers.add(messageId);
  }

  void removeQueuedItemsForPeer(String peerId, List<Message> storedMessages) {
    _fileSendQueue.removeWhere((item) => item.peerId == peerId);
    _cancelledFileTransfers.removeWhere((messageId) {
      return storedMessages.any((message) => message.id == messageId);
    });
    if (_activeFileTransferId != null &&
        storedMessages.any((message) => message.id == _activeFileTransferId)) {
      _cancelledFileTransfers.add(_activeFileTransferId!);
    }
  }

  void refreshQueuedFileStatuses({
    required Map<String, Chat> chats,
    required void Function(String peerId) schedulePersistLoadedChat,
    required void Function(String peerId) notifyMessageUpdated,
  }) {
    if (_fileSendQueue.isEmpty) {
      return;
    }

    final queueSnapshot = _fileSendQueue.toList(growable: false);
    final total = queueSnapshot.length;
    final changedPeers = <String>{};
    for (var index = 0; index < queueSnapshot.length; index++) {
      final item = queueSnapshot[index];
      final chat = chats[item.peerId];
      if (chat == null || !chat.messagesLoaded) {
        continue;
      }
      for (var i = 0; i < chat.messages.length; i++) {
        final msg = chat.messages[i];
        if (msg.id != item.messageId) {
          continue;
        }
        if (msg.status != MessageStatus.sending) {
          break;
        }
        final nextStatus = 'Ожидает отправки (${index + 1} из $total)';
        if (msg.transferStatus != nextStatus || msg.sendProgress != 0.02) {
          chat.messages[i] = ChatMessageCopy.copy(
            msg,
            transferStatus: nextStatus,
            sendProgress: 0.02,
          );
          changedPeers.add(item.peerId);
        }
        break;
      }
    }

    for (final peerId in changedPeers) {
      schedulePersistLoadedChat(peerId);
      notifyMessageUpdated(peerId);
    }
  }

  Future<void> updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
    required Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    })
    applyFileProgressUpdate,
  }) async {
    final key = '$peerId::$messageId';
    final now = DateTime.now();
    final pending = _pendingProgressUpdates[key];
    if (pending != null) {
      pending
        ..sentBytes = sentBytes
        ..totalBytes = totalBytes
        ..statusText = statusText;
      final elapsed = now.difference(pending.lastAppliedAt);
      if (elapsed >= _progressThrottleInterval) {
        pending.timer?.cancel();
        pending.timer = null;
        await applyFileProgressUpdate(
          peerId,
          messageId,
          sentBytes: pending.sentBytes,
          totalBytes: pending.totalBytes,
          statusText: pending.statusText,
        );
        pending.lastAppliedAt = DateTime.now();
        _pendingProgressUpdates[key] = pending;
        return;
      }
      pending.timer ??= Timer(_progressThrottleInterval - elapsed, () {
        final currentPending = _pendingProgressUpdates[key];
        if (currentPending == null) {
          return;
        }
        currentPending.timer = null;
        unawaited(
          applyFileProgressUpdate(
            peerId,
            messageId,
            sentBytes: currentPending.sentBytes,
            totalBytes: currentPending.totalBytes,
            statusText: currentPending.statusText,
          ),
        );
        currentPending.lastAppliedAt = DateTime.now();
        _pendingProgressUpdates[key] = currentPending;
      });
      _pendingProgressUpdates[key] = pending;
      return;
    }

    _pendingProgressUpdates[key] = PendingProgressUpdate(
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
      lastAppliedAt: now,
    );
    await applyFileProgressUpdate(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
    );
  }

  void clearProgressUpdate(String peerId, String messageId) {
    final key = '$peerId::$messageId';
    final pending = _pendingProgressUpdates.remove(key);
    pending?.timer?.cancel();
  }

  void dispose() {
    final pendingUpdates = List<PendingProgressUpdate>.from(
      _pendingProgressUpdates.values,
    );
    for (final pending in pendingUpdates) {
      pending.timer?.cancel();
    }
    _pendingProgressUpdates.clear();
  }
}
