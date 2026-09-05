// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:peerlink/features/chat/domain/chat.dart';
import '../models/contact.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_media_file_reader.dart';

class ChatForwardTarget {
  final String peerId;
  final String name;
  final bool isGroup;
  final DateTime? lastMessageAt;

  const ChatForwardTarget({
    required this.peerId,
    required this.name,
    required this.isGroup,
    required this.lastMessageAt,
  });
}

class ChatForwardService {
  const ChatForwardService();

  List<ChatForwardTarget> targets({
    required List<Chat> chats,
    required List<Contact> contacts,
  }) {
    final byPeerId = <String, ChatForwardTarget>{};
    for (final chat in chats) {
      byPeerId[chat.peerId] = ChatForwardTarget(
        peerId: chat.peerId,
        name: chat.name,
        isGroup: chat.isGroup,
        lastMessageAt: chat.lastMessage?.timestamp,
      );
    }
    for (final contact in contacts) {
      byPeerId.putIfAbsent(
        contact.peerId,
        () => ChatForwardTarget(
          peerId: contact.peerId,
          name: contact.name,
          isGroup: false,
          lastMessageAt: null,
        ),
      );
    }
    final result = byPeerId.values.toList(growable: false);
    result.sort((a, b) {
      final at = a.lastMessageAt;
      final bt = b.lastMessageAt;
      if (at != null && bt != null) {
        return bt.compareTo(at);
      }
      if (at != null) {
        return -1;
      }
      if (bt != null) {
        return 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return result;
  }

  Future<void> forward({
    required Message message,
    required ChatForwardTarget target,
    required Future<void> Function(String peerId, String text) sendMessage,
    required Future<void> Function(
      String peerId, {
      required String fileName,
      Uint8List? fileBytes,
      String? filePath,
      int? fileSizeBytes,
      String? mimeType,
    })
    sendFile,
    required Future<String?> Function(Message message) ensureLocalMedia,
  }) async {
    if (message.kind == MessageKind.text) {
      await sendMessage(target.peerId, message.text);
      return;
    }

    final fileName = message.fileName ?? message.text;
    var filePath = message.localFilePath?.trim();
    if (filePath != null && filePath.isEmpty) {
      filePath = null;
    }
    var hasLocalFile = filePath != null && await File(filePath).exists();
    if (!hasLocalFile) {
      filePath = await ensureLocalMedia(message);
      hasLocalFile = filePath != null && await File(filePath).exists();
    }

    Uint8List? fileBytes;
    if (hasLocalFile) {
      fileBytes = await readMediaFileBytes(filePath!);
    } else {
      final embedded = message.fileDataBase64;
      if (embedded != null && embedded.isNotEmpty) {
        fileBytes = base64Decode(embedded);
      }
    }
    if (!hasLocalFile && (fileBytes == null || fileBytes.isEmpty)) {
      throw StateError('forward source file unavailable');
    }
    final resolvedBytes = fileBytes;
    if (resolvedBytes == null || resolvedBytes.isEmpty) {
      throw StateError('forward source file unavailable');
    }

    await sendFile(
      target.peerId,
      fileName: fileName,
      fileBytes: resolvedBytes,
      filePath: null,
      fileSizeBytes: resolvedBytes.length,
      mimeType: message.mimeType,
    );
  }
}
