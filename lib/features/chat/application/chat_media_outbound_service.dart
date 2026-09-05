// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:typed_data';

import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_media_file_reader.dart';

typedef ChatMediaProgressUpdater =
    Future<void> Function(
      String peerId,
      String messageId, {
      required int sentBytes,
      required int? totalBytes,
      required String statusText,
    });

typedef ChatMediaSaveFile =
    Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required String sourcePath,
    });

typedef ChatMediaSaveBytes =
    Future<String> Function({
      required String peerId,
      required String messageId,
      required String fileName,
      required Uint8List bytes,
    });

class ChatMediaOutboundUploadResult {
  final String blobId;
  final Uint8List originalBytes;

  const ChatMediaOutboundUploadResult({
    required this.blobId,
    required this.originalBytes,
  });
}

class ChatMediaLocalSaveResult {
  final String? localPath;
  final String? thumbnailPath;

  const ChatMediaLocalSaveResult({this.localPath, this.thumbnailPath});
}

class ChatMediaOutboundService {
  const ChatMediaOutboundService({
    required NodeFacade facade,
    required RelayMediaTransferService relayMediaTransfer,
  }) : _facade = facade,
       _relayMediaTransfer = relayMediaTransfer;

  final NodeFacade _facade;
  final RelayMediaTransferService _relayMediaTransfer;

  Future<ChatMediaOutboundUploadResult> prepareAndUpload({
    required String chatPeerId,
    required String messageId,
    required String fileName,
    required Uint8List? fileBytes,
    required String? filePath,
    required int fileSizeBytes,
    required String? mimeType,
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required ChatMediaProgressUpdater updateFileProgress,
    required void Function(String message) logQueue,
    required bool Function() isCancelled,
    Future<Uint8List> Function(Uint8List plainBytes)? transformPayload,
  }) async {
    logQueue(
      'upload prepare peer=$chatPeerId messageId=$messageId file=$fileName '
      'size=$fileSizeBytes path=${filePath?.isNotEmpty == true} '
      'bytes=${fileBytes?.length ?? 0}',
    );
    await updateFileProgress(
      chatPeerId,
      messageId,
      sentBytes: 0,
      totalBytes: fileSizeBytes,
      statusText: 'Подготовка',
    );

    Uint8List? originalBytes = fileBytes;
    if (originalBytes == null && filePath != null && filePath.isNotEmpty) {
      originalBytes = await readMediaFileBytes(filePath);
    }
    if (originalBytes == null) {
      throw StateError('Не удалось прочитать файл');
    }
    if (isCancelled()) {
      throw const FileTransferCancelledException();
    }

    final payloadBytes = transformPayload == null
        ? originalBytes
        : await transformPayload(originalBytes);
    if (isCancelled()) {
      throw const FileTransferCancelledException();
    }
    await updateFileProgress(
      chatPeerId,
      messageId,
      sentBytes: 0,
      totalBytes: fileSizeBytes,
      statusText: 'Загрузка в relay',
    );
    logQueue(
      'upload blob start peer=$chatPeerId messageId=$messageId bytes=${payloadBytes.length}',
    );

    final uploadResult = await _relayMediaTransfer.uploadBlob(
      peerId: chatPeerId,
      messageId: messageId,
      upload: (onProgress) => _facade.uploadBlob(
        scopeKind: scopeKind,
        targetId: targetId,
        fileName: fileName,
        mimeType: mimeType,
        bytes: payloadBytes,
        blobId: 'blob:$messageId',
        onProgress: onProgress,
      ),
      onProgress:
          ({
            required int sentBytes,
            required int totalBytes,
            required String status,
          }) {
            unawaited(
              updateFileProgress(
                chatPeerId,
                messageId,
                sentBytes: sentBytes,
                totalBytes: totalBytes,
                statusText: status,
              ),
            );
          },
    );
    if (!uploadResult.isUploaded) {
      throw uploadResult.error ?? StateError('Relay blob upload failed');
    }
    if (isCancelled()) {
      throw const FileTransferCancelledException();
    }
    logQueue(
      'upload blob done peer=$chatPeerId messageId=$messageId blobId=${uploadResult.blobId}',
    );
    return ChatMediaOutboundUploadResult(
      blobId: uploadResult.blobId!,
      originalBytes: originalBytes,
    );
  }

  Future<ChatMediaLocalSaveResult> saveLocalMedia({
    required String peerId,
    required String messageId,
    required String fileName,
    required Uint8List? fileBytes,
    required String? filePath,
    required String? mimeType,
    required ChatMediaSaveFile saveMediaFile,
    required ChatMediaSaveBytes saveMediaBytes,
    required Future<String?> Function(Message message) ensureThumbnail,
  }) async {
    String? localPath;
    if (filePath != null && filePath.isNotEmpty) {
      localPath = await saveMediaFile(
        peerId: peerId,
        messageId: messageId,
        fileName: fileName,
        sourcePath: filePath,
      );
    } else if (fileBytes != null) {
      localPath = await saveMediaBytes(
        peerId: peerId,
        messageId: messageId,
        fileName: fileName,
        bytes: fileBytes,
      );
    }
    final thumbnailPath = localPath == null || localPath.isEmpty
        ? null
        : await ensureThumbnail(
            Message(
              id: messageId,
              peerId: peerId,
              text: fileName,
              incoming: false,
              timestamp: DateTime.now(),
              kind: MessageKind.file,
              fileName: fileName,
              mimeType: mimeType,
              localFilePath: localPath,
            ),
          );
    return ChatMediaLocalSaveResult(
      localPath: localPath,
      thumbnailPath: thumbnailPath,
    );
  }
}
