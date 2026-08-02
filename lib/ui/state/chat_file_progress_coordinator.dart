import '../../core/relay/relay_models.dart';
import '../models/chat.dart';
import '../models/message.dart';
import 'chat_controller_parts.dart';
import 'chat_file_queue_service.dart';
import 'chat_incoming_media_restore_coordinator.dart';

class ChatFileProgressCoordinator {
  const ChatFileProgressCoordinator({
    required ChatFileQueueService fileQueueService,
    required Map<String, Chat> chats,
    required ChatIncomingMediaRestoreCoordinator
    incomingMediaRestoreCoordinator,
    required String incomingRelayErrorStatus,
    required String incomingRelayNotConfiguredStatus,
    required String incomingRelayUnavailableStatus,
    required void Function(String peerId) notifyMessageUpdated,
  }) : _fileQueueService = fileQueueService,
       _chats = chats,
       _incomingMediaRestoreCoordinator = incomingMediaRestoreCoordinator,
       _incomingRelayErrorStatus = incomingRelayErrorStatus,
       _incomingRelayNotConfiguredStatus = incomingRelayNotConfiguredStatus,
       _incomingRelayUnavailableStatus = incomingRelayUnavailableStatus,
       _notifyMessageUpdated = notifyMessageUpdated;

  final ChatFileQueueService _fileQueueService;
  final Map<String, Chat> _chats;
  final ChatIncomingMediaRestoreCoordinator _incomingMediaRestoreCoordinator;
  final String _incomingRelayErrorStatus;
  final String _incomingRelayNotConfiguredStatus;
  final String _incomingRelayUnavailableStatus;
  final void Function(String peerId) _notifyMessageUpdated;

  String transferStatusForError(Object error, {required String fallback}) {
    if (error is RelayUnavailableException) {
      return error.isNotConfigured
          ? _incomingRelayNotConfiguredStatus
          : _incomingRelayUnavailableStatus;
    }
    return fallback;
  }

  Future<void> updateFileProgress(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    await _fileQueueService.updateFileProgress(
      peerId,
      messageId,
      sentBytes: sentBytes,
      totalBytes: totalBytes,
      statusText: statusText,
      applyFileProgressUpdate: applyFileProgressUpdate,
    );
  }

  void clearProgressUpdate(String peerId, String messageId) {
    _fileQueueService.clearProgressUpdate(peerId, messageId);
  }

  Future<void> applyFileProgressUpdate(
    String peerId,
    String messageId, {
    required int sentBytes,
    required int? totalBytes,
    required String statusText,
  }) async {
    final chat = _chats[peerId];
    if (chat == null || !chat.messagesLoaded) {
      return;
    }

    for (var i = 0; i < chat.messages.length; i++) {
      final msg = chat.messages[i];
      if (msg.id != messageId) {
        continue;
      }
      final relayTransferId = (msg.transferId ?? '').trim();
      final isIncomingRelayMedia =
          msg.incoming &&
          msg.kind == MessageKind.file &&
          (relayTransferId.startsWith('dirblob:') ||
              relayTransferId.startsWith('grpblob:'));
      if (isIncomingRelayMedia &&
          ((msg.localFilePath?.isNotEmpty ?? false) ||
              msg.transferStatus == _incomingRelayErrorStatus)) {
        return;
      }
      final nextProgress = (totalBytes == null || totalBytes <= 0)
          ? null
          : (sentBytes / totalBytes).clamp(0.0, 1.0).toDouble();
      if (isIncomingRelayMedia &&
          _incomingMediaRestoreCoordinator.isStaleIncomingRelayProgress(
            currentStatus: msg.transferStatus,
            currentProgress: msg.transferProgress,
            nextStatus: statusText,
            nextProgress: nextProgress,
          )) {
        return;
      }
      final changed =
          msg.transferredBytes != sentBytes ||
          msg.sendProgress != nextProgress ||
          msg.transferStatus != statusText;
      if (!changed) {
        return;
      }
      chat.messages[i] = ChatMessageCopy.copy(
        msg,
        transferredBytes: sentBytes,
        sendProgress: nextProgress,
        transferStatus: statusText,
      );
      _notifyMessageUpdated(peerId);
      return;
    }
  }
}
