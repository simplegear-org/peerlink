import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import '../../core/runtime/storage_service.dart';
import '../models/message.dart';
import 'chat_controller_parts.dart';

class ChatControllerMedia {
  static const String _incomingRelayFetchStatus = 'Получение из relay';
  static const String _incomingRelayRetryStatus = 'Повторная загрузка';
  static const String _incomingRelayDownloadStatus = 'Загрузка';
  static const String _incomingRelayCompleteStatus = 'Загрузка завершена';
  static const String _incomingRelayDecryptStatus = 'Расшифровка';
  static const String _incomingRelaySaveStatus = 'Сохранение';
  static const String _incomingRelayErrorStatus = 'Ошибка загрузки';

  static Future<void> processLoadedMessages({
    required StorageService storage,
    required String peerId,
    required List<Message> stored,
    required Future<void> Function(String peerId, List<Message> messages)
    writeStoredMessages,
    required Future<void> Function(String peerId, List<Message> messages)
    upsertStoredMessages,
    required Future<void> Function(String peerId, List<String> messageIds)
    deleteStoredMessagesByIds,
    required Future<void> Function(String peerId) persistChatSummary,
    required Future<void> Function(Message message)
    deleteManagedMediaForMessage,
  }) async {
    developer.log(
      '[chat_media] processLoadedMessages start peer=$peerId count=${stored.length}',
      name: 'chat',
    );
    var changed = false;
    final messagesToRemove = <int>[];
    final removedMessageIds = <String>[];
    final changedMessages = <String, Message>{};
    var recoveredCount = 0;
    var normalizedCount = 0;

    for (var i = 0; i < stored.length; i++) {
      final message = stored[i];

      if (_isStaleIncomingRelayRestore(message)) {
        final updated = ChatMessageCopy.copy(
          message,
          transferredBytes: 0,
          sendProgress: 0.0,
          transferStatus: _incomingRelayErrorStatus,
        );
        stored[i] = updated;
        changedMessages[updated.id] = updated;
        changed = true;
        normalizedCount += 1;
        continue;
      }

      if (!message.incoming &&
          message.status == MessageStatus.failed &&
          message.transferStatus == 'Отменено') {
        await deleteManagedMediaForMessage(message);
        messagesToRemove.add(i);
        removedMessageIds.add(message.id);
        changed = true;
        continue;
      }

      if (message.localFilePath != null && message.localFilePath!.isNotEmpty) {
        final file = File(message.localFilePath!);
        if (await file.exists()) {
          if (!storage.isManagedMediaPath(message.localFilePath)) {
            try {
              final path = await storage.saveMediaFile(
                peerId: peerId,
                messageId: message.id,
                fileName: message.fileName ?? message.text,
                sourcePath: message.localFilePath!,
              );
              if (path.isNotEmpty && path != message.localFilePath) {
                final updated = ChatMessageCopy.copy(
                  message,
                  localFilePath: path,
                );
                stored[i] = updated;
                changedMessages[updated.id] = updated;
                changed = true;
                normalizedCount += 1;
              }
            } catch (_) {}
          }
          continue;
        }

        final recoveredPath = await storage.recoverMediaFromLegacy(
          peerId: peerId,
          messageId: message.id,
          fileName: message.fileName ?? message.text,
          previousPath: message.localFilePath,
        );
        if (recoveredPath != null && recoveredPath.isNotEmpty) {
          final updated = ChatMessageCopy.copy(
            message,
            localFilePath: recoveredPath,
          );
          stored[i] = updated;
          changedMessages[updated.id] = updated;
          changed = true;
          recoveredCount += 1;
          continue;
        }

        if (message.fileDataBase64 != null &&
            message.fileDataBase64!.isNotEmpty) {
          try {
            final path = await storage.saveMediaBytes(
              peerId: peerId,
              messageId: message.id,
              fileName: message.fileName ?? message.text,
              bytes: base64Decode(message.fileDataBase64!),
            );
            if (path.isNotEmpty) {
              final updated = ChatMessageCopy.copy(
                message,
                localFilePath: path,
              );
              stored[i] = updated;
              changedMessages[updated.id] = updated;
              changed = true;
              normalizedCount += 1;
              continue;
            }
          } catch (_) {}
        }

        final updated = ChatMessageCopy.copy(message, localFilePath: null);
        stored[i] = updated;
        changedMessages[updated.id] = updated;
        changed = true;
        normalizedCount += 1;
        continue;
      }

      final recoveredPath = await storage.recoverMediaFromLegacy(
        peerId: peerId,
        messageId: message.id,
        fileName: message.fileName ?? message.text,
      );
      if (recoveredPath != null && recoveredPath.isNotEmpty) {
        final updated = ChatMessageCopy.copy(
          message,
          localFilePath: recoveredPath,
        );
        stored[i] = updated;
        changedMessages[updated.id] = updated;
        changed = true;
        recoveredCount += 1;
        continue;
      }

      final bytes = message.fileBytes;
      if (bytes == null || bytes.isEmpty) {
        continue;
      }

      final path = await storage.saveMediaBytes(
        peerId: peerId,
        messageId: message.id,
        fileName: message.fileName ?? message.text,
        bytes: bytes,
      );
      if (path.isEmpty) {
        continue;
      }

      final updated = ChatMessageCopy.copy(
        message,
        fileDataBase64: null,
        localFilePath: path,
      );
      stored[i] = updated;
      changedMessages[updated.id] = updated;
      changed = true;
      normalizedCount += 1;
    }

    for (final index in messagesToRemove.reversed) {
      stored.removeAt(index);
    }

    if (changed) {
      developer.log(
        '[chat_media] processLoadedMessages persist peer=$peerId '
        'count=${stored.length} recovered=$recoveredCount normalized=$normalizedCount '
        'removed=${messagesToRemove.length} upserts=${changedMessages.length}',
        name: 'chat',
      );
      if (removedMessageIds.isNotEmpty) {
        await deleteStoredMessagesByIds(peerId, removedMessageIds);
      }
      if (changedMessages.isNotEmpty) {
        await upsertStoredMessages(
          peerId,
          changedMessages.values.toList(growable: false),
        );
      } else if (messagesToRemove.isNotEmpty) {
        await writeStoredMessages(peerId, stored);
      }
      await persistChatSummary(peerId);
    }
    developer.log(
      '[chat_media] processLoadedMessages done peer=$peerId count=${stored.length} '
      'changed=$changed recovered=$recoveredCount normalized=$normalizedCount '
      'removed=${messagesToRemove.length}',
      name: 'chat',
    );
  }

  static Future<void> replaceCompletedFileMessage({
    required StorageService storage,
    required Message existing,
    required Uint8List bytes,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
  }) async {
    String? path;
    try {
      path = await storage.saveMediaBytes(
        peerId: existing.peerId,
        messageId: existing.id,
        fileName: existing.fileName ?? existing.text,
        bytes: bytes,
      );
    } catch (e, stack) {
      developer.log(
        '[chat] Failed to save media bytes: $e\n$stack',
        name: 'chat',
      );
      path = null;
    }

    await replaceMessage(
      existing.peerId,
      existing.id,
      (current) => ChatMessageCopy.copy(
        current,
        fileDataBase64: null,
        localFilePath: (path != null && path.isNotEmpty) ? path : null,
        fileSizeBytes: current.fileSizeBytes ?? bytes.length,
        transferredBytes: null,
        sendProgress: null,
        transferStatus: null,
      ),
    );
  }

  static Future<String?> restoreMediaFromEmbedded({
    required StorageService storage,
    required String peerId,
    required Message message,
    required Future<void> Function(
      String peerId,
      String messageId,
      Message Function(Message current) transform,
    )
    replaceMessage,
  }) async {
    final bytes = message.fileBytes;
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    try {
      final path = await storage.saveMediaBytes(
        peerId: peerId,
        messageId: message.id,
        fileName: message.fileName ?? message.text,
        bytes: bytes,
      );

      if (path.isNotEmpty) {
        await replaceMessage(
          peerId,
          message.id,
          (current) => ChatMessageCopy.copy(current, localFilePath: path),
        );
      }

      return path.isNotEmpty ? path : null;
    } catch (_) {
      return null;
    }
  }

  static bool _isStaleIncomingRelayRestore(Message message) {
    if (!message.incoming || message.kind != MessageKind.file) {
      return false;
    }
    if (message.localFilePath?.trim().isNotEmpty == true) {
      return false;
    }
    final transferId = (message.transferId ?? '').trim();
    if (!transferId.startsWith('dirblob:') &&
        !transferId.startsWith('grpblob:')) {
      return false;
    }
    final status = (message.transferStatus ?? '').trim();
    return status == _incomingRelayFetchStatus ||
        status == _incomingRelayRetryStatus ||
        status == _incomingRelayDownloadStatus ||
        status == _incomingRelayCompleteStatus ||
        status == _incomingRelayDecryptStatus ||
        status == _incomingRelaySaveStatus;
  }
}
