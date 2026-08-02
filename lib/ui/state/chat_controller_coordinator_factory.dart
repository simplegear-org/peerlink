import 'dart:typed_data';

import '../models/chat.dart';
import '../models/message.dart';
import 'chat_direct_lifecycle_service.dart';
import 'chat_file_progress_coordinator.dart';
import 'chat_file_send_coordinator.dart';
import 'chat_file_transfer_coordinator.dart';
import 'chat_incoming_media_restore_coordinator.dart';
import 'chat_controller_models.dart';
import '../../core/node/node_facade.dart';
import 'chat_file_queue_service.dart';

class ChatControllerCoordinatorFactory {
  const ChatControllerCoordinatorFactory._();

  static ChatDirectLifecycleService directLifecycle({
    required NodeFacade facade,
    required Map<String, Chat> chats,
    required String Function(String peerId, {String? fallback}) contactNameFor,
    required Future<void> Function(Chat chat) persistChatSummary,
    required void Function(String peerId) schedulePersistChatSummary,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function(
      String peerId,
      ChatConnectionStatus status, {
      String? error,
    })
    setStatus,
  }) {
    return ChatDirectLifecycleService(
      facade: facade,
      chats: chats,
      contactNameFor: contactNameFor,
      persistChatSummary: persistChatSummary,
      schedulePersistChatSummary: schedulePersistChatSummary,
      notifyMessageUpdated: notifyMessageUpdated,
      setStatus: setStatus,
    );
  }

  static ChatFileProgressCoordinator fileProgress({
    required ChatFileQueueService fileQueueService,
    required Map<String, Chat> chats,
    required ChatIncomingMediaRestoreCoordinator
    incomingMediaRestoreCoordinator,
    required String incomingRelayErrorStatus,
    required String incomingRelayNotConfiguredStatus,
    required String incomingRelayUnavailableStatus,
    required void Function(String peerId) notifyMessageUpdated,
  }) {
    return ChatFileProgressCoordinator(
      fileQueueService: fileQueueService,
      chats: chats,
      incomingMediaRestoreCoordinator: incomingMediaRestoreCoordinator,
      incomingRelayErrorStatus: incomingRelayErrorStatus,
      incomingRelayNotConfiguredStatus: incomingRelayNotConfiguredStatus,
      incomingRelayUnavailableStatus: incomingRelayUnavailableStatus,
      notifyMessageUpdated: notifyMessageUpdated,
    );
  }

  static ChatFileSendCoordinator fileSend({
    required ChatFileTransferCoordinator fileTransferCoordinator,
    required Future<void> Function(String peerId) ensureChatLoaded,
    required Chat Function(String peerId) ensureChat,
    required String Function() nextLocalMessageId,
    required Future<void> Function(String peerId) persistLoadedChat,
    required String? Function(String chatPeerId, Message? replyTo)
    replySenderLabel,
    required String? Function(Message? replyTo) replyTextPreview,
    required String? Function(Message? replyTo) replyKind,
    required void Function(String message) logQueue,
    required void Function(String peerId) notifyMessageUpdated,
    required void Function() refreshQueuedFileStatuses,
    required Future<void> Function() drainFileQueue,
    required Future<void> Function(
      Chat groupChat, {
      required String messageId,
      required String fileName,
      Uint8List? fileBytes,
      String? filePath,
      required int fileSizeBytes,
      String? mimeType,
      Message? replyTo,
    })
    sendGroupFile,
  }) {
    return ChatFileSendCoordinator(
      fileTransferCoordinator: fileTransferCoordinator,
      ensureChatLoaded: ensureChatLoaded,
      ensureChat: ensureChat,
      nextLocalMessageId: nextLocalMessageId,
      persistLoadedChat: persistLoadedChat,
      replySenderLabel: replySenderLabel,
      replyTextPreview: replyTextPreview,
      replyKind: replyKind,
      logQueue: logQueue,
      notifyMessageUpdated: notifyMessageUpdated,
      refreshQueuedFileStatuses: refreshQueuedFileStatuses,
      drainFileQueue: drainFileQueue,
      sendGroupFile: sendGroupFile,
    );
  }
}
