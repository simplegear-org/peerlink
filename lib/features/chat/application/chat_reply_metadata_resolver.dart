// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/chat/domain/message.dart';

class ChatReplyMetadataResolver {
  const ChatReplyMetadataResolver({
    required String Function(String peerId, {String? fallback}) contactNameFor,
  }) : _contactNameFor = contactNameFor;

  final String Function(String peerId, {String? fallback}) _contactNameFor;

  String? senderLabel(String chatPeerId, Message? replyTo) {
    if (replyTo == null) {
      return null;
    }
    if (!replyTo.incoming) {
      return 'Вы';
    }
    final senderPeerId = (replyTo.senderPeerId ?? chatPeerId).trim();
    if (senderPeerId.isEmpty) {
      return null;
    }
    final contactName = _contactNameFor(senderPeerId, fallback: null);
    if (contactName.isNotEmpty) {
      return contactName;
    }
    return shortPeerId(senderPeerId);
  }

  String? textPreview(Message? replyTo) {
    if (replyTo == null) {
      return null;
    }
    if (replyTo.kind == MessageKind.file) {
      if (replyTo.isAudio) {
        return 'Голосовое сообщение';
      }
      if (replyTo.isImage) {
        return 'Фото';
      }
      if (replyTo.isVideo) {
        return 'Видео';
      }
      return replyTo.fileName?.trim().isNotEmpty == true
          ? replyTo.fileName!.trim()
          : 'Файл';
    }
    final text = replyTo.text.trim();
    if (text.isEmpty) {
      return 'Сообщение';
    }
    return text.length <= 120 ? text : '${text.substring(0, 120)}…';
  }

  String? kind(Message? replyTo) {
    if (replyTo == null) {
      return null;
    }
    return replyTo.kind == MessageKind.file ? 'file' : 'text';
  }

  static String shortPeerId(String peerId) {
    if (peerId.length <= 8) {
      return peerId;
    }
    return '${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}';
  }
}
