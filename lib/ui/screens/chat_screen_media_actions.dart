import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/runtime/app_file_logger.dart';
import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import 'media_viewer_screen.dart';

class ChatScreenMediaActions {
  const ChatScreenMediaActions();

  Future<void> handleFileTap({
    required BuildContext context,
    required Chat chat,
    required ChatController controller,
    required Message message,
  }) async {
    try {
      final activeMessage = chat.messages.firstWhere(
        (item) => item.id == message.id,
        orElse: () => message,
      );
      final localFile = activeMessage.localFile;
      final hasLocalFile = localFile != null && await localFile.exists();
      final hasEmbeddedBytes = activeMessage.fileBytes != null;
      final canRestoreFromBytes =
          !hasLocalFile &&
          hasEmbeddedBytes &&
          activeMessage.kind == MessageKind.file;
      if (controller.isIncomingRelayMediaRestoreInProgress(activeMessage)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.mediaStillLoading)),
        );
        return;
      }

      if (controller.isIncomingRelayMediaRestoreFailed(activeMessage) &&
          !hasLocalFile &&
          !canRestoreFromBytes) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.strings.downloadError)));
        return;
      }

      if (activeMessage.isMedia && (hasLocalFile || hasEmbeddedBytes)) {
        final mediaMessages = chat.messages
            .where((item) => item.isMedia)
            .toList(growable: false);
        final initialIndex = mediaMessages.indexWhere(
          (item) => item.id == activeMessage.id,
        );
        if (!context.mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaViewerScreen(
              mediaMessages: mediaMessages,
              initialIndex: initialIndex == -1 ? 0 : initialIndex,
            ),
          ),
        );
        return;
      }

      if (canRestoreFromBytes) {
        try {
          final restoredPath = await controller.restoreMediaFromEmbedded(
            chat.peerId,
            activeMessage,
          );
          if (restoredPath != null && restoredPath.isNotEmpty) {
            final restoredFile = File(restoredPath);
            if (await restoredFile.exists()) {
              final refreshed = chat.messages.firstWhere(
                (item) => item.id == message.id,
                orElse: () => message,
              );
              if (!context.mounted) return;
              if (refreshed.isMedia) {
                final mediaMessages = chat.messages
                    .where((item) => item.isMedia)
                    .toList(growable: false);
                final initialIndex = mediaMessages.indexWhere(
                  (item) => item.id == refreshed.id,
                );
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MediaViewerScreen(
                      mediaMessages: mediaMessages,
                      initialIndex: initialIndex == -1 ? 0 : initialIndex,
                    ),
                  ),
                );
              } else {
                await openFileMessage(context: context, message: refreshed);
              }
              return;
            }
          }
        } catch (_) {}
      }

      if (!hasLocalFile && activeMessage.kind == MessageKind.file) {
        try {
          final restoredPath = chat.isGroup
              ? await controller.restoreGroupBlobMedia(activeMessage)
              : await controller.restoreDirectBlobMedia(activeMessage);
          if (restoredPath != null && restoredPath.isNotEmpty) {
            final restoredFile = File(restoredPath);
            if (await restoredFile.exists()) {
              final refreshed = chat.messages.firstWhere(
                (item) => item.id == activeMessage.id,
                orElse: () => activeMessage,
              );
              if (!context.mounted) return;
              if (refreshed.isMedia) {
                final mediaMessages = chat.messages
                    .where((item) => item.isMedia)
                    .toList(growable: false);
                final initialIndex = mediaMessages.indexWhere(
                  (item) => item.id == refreshed.id,
                );
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MediaViewerScreen(
                      mediaMessages: mediaMessages,
                      initialIndex: initialIndex == -1 ? 0 : initialIndex,
                    ),
                  ),
                );
              } else {
                await openFileMessage(context: context, message: refreshed);
              }
              return;
            }
          }
        } catch (_) {}
      }

      if (!context.mounted) return;
      if (activeMessage.isMedia) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.mediaUnavailable)),
        );
        return;
      }

      await openFileMessage(context: context, message: activeMessage);
    } catch (error) {
      AppFileLogger.log(
        '[chat_ui] handleFileTap failed messageId=${message.id} error=$error',
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.downloadError)));
    }
  }

  Future<void> openFileMessage({
    required BuildContext context,
    required Message message,
  }) async {
    final file = message.localFile;
    if (file == null || !await file.exists()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.fileUnavailableOpen)),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        text: message.fileName ?? message.text,
        files: [XFile(file.path)],
      ),
    );
  }

  Future<void> pickAndSendGalleryMedia({
    required BuildContext context,
    required ChatController controller,
    required String peerId,
    required int maxFileSize,
    required void Function(String message) showPlaceholder,
    Message? replyTo,
  }) async {
    final strings = context.strings;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.media,
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      AppFileLogger.log('[chat_ui] media pick cancelled');
      return;
    }
    AppFileLogger.log('[chat_ui] media pick count=${result.files.length}');

    var failedCount = 0;
    String? firstError;
    for (final file in result.files) {
      final path = file.path;
      if (path == null || path.isEmpty || file.name.isEmpty) {
        AppFileLogger.log(
          '[chat_ui] media skip missing path name=${file.name}',
        );
        continue;
      }
      if (file.size > maxFileSize) {
        AppFileLogger.log(
          '[chat_ui] media skip too large file=${file.name} size=${file.size}',
        );
        showPlaceholder(strings.fileTooLarge);
        continue;
      }

      try {
        AppFileLogger.log(
          '[chat_ui] media enqueue file=${file.name} size=${file.size}',
        );
        await controller.sendFile(
          peerId,
          fileName: file.name,
          filePath: path,
          fileSizeBytes: file.size,
          mimeType: file.extension,
          replyTo: replyTo,
        );
      } catch (error) {
        failedCount += 1;
        firstError ??= error.toString();
        AppFileLogger.log(
          '[chat_ui] enqueue media failed file=${file.name}: $error',
        );
        debugPrint('[chat_ui] enqueue media failed file=${file.name}: $error');
      }
    }

    if (!context.mounted) return;
    if (failedCount > 0) {
      final total = result.files.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.strings.addFilesFailed(failedCount, total, firstError),
          ),
        ),
      );
    }
  }
}
