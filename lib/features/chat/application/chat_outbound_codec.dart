// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:peerlink/features/chat/domain/chat.dart';

class ChatOutboundCodec {
  final String Function() localPeerIdProvider;

  const ChatOutboundCodec({required this.localPeerIdProvider});

  static const String groupInvitePrefix = '__peerlink_group_invite_v1__:';
  static const String groupMessagePrefix = '__peerlink_group_msg_v1__:';
  static const String groupDeletePrefix = '__peerlink_group_delete_v1__:';
  static const String groupChatDeletePrefix =
      '__peerlink_group_chat_delete_v1__:';
  static const String groupMembersPrefix = '__peerlink_group_members_v1__:';
  static const String groupKeyPrefix = '__peerlink_group_key_v1__:';
  static const String groupKeyRequestPrefix =
      '__peerlink_group_key_request_v1__:';
  static const String groupSecurePrefix = '__peerlink_group_secure_v1__:';
  static const String groupBlobRefPrefix = '__peerlink_group_blob_ref_v1__:';
  static const String directBlobRefPrefix = '__peerlink_direct_blob_ref_v1__:';
  static const String messageReceiptPrefix = '__peerlink_message_receipt_v1__:';

  String _localPeerId() => localPeerIdProvider();

  String encodeGroupKeyPayload({
    required Chat groupChat,
    required String groupKeyBase64,
    required int keyVersion,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_key',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupName': groupChat.name,
      'ownerPeerId': groupChat.ownerPeerId ?? _localPeerId(),
      'groupKey': groupKeyBase64,
      'keyVersion': keyVersion,
      'senderPeerId': _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupKeyPrefix${jsonEncode(payload)}';
  }

  String encodeGroupKeyRequestPayload({
    required String groupId,
    required String ownerPeerId,
    required String failedMessageId,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_key_request',
      'v': 1,
      'groupId': groupId,
      'ownerPeerId': ownerPeerId,
      'requesterPeerId': _localPeerId(),
      'failedMessageId': failedMessageId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupKeyRequestPrefix${jsonEncode(payload)}';
  }

  String encodeGroupInvitePayload({
    required String groupId,
    required String groupName,
    required List<String> memberPeerIds,
    required String ownerPeerId,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_invite',
      'v': 1,
      'groupId': groupId,
      'groupName': groupName,
      'memberPeerIds': memberPeerIds,
      'inviterPeerId': _localPeerId(),
      'ownerPeerId': ownerPeerId,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupInvitePrefix${jsonEncode(payload)}';
  }

  String encodeGroupMessagePayload({
    required Chat groupChat,
    required String messageId,
    required String text,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_message',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupMessageId': messageId,
      'groupName': groupChat.name,
      'text': text,
      'memberPeerIds': groupChat.memberPeerIds,
      'senderPeerId': _localPeerId(),
      'ownerPeerId': groupChat.ownerPeerId ?? _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupMessagePrefix${jsonEncode(payload)}';
  }

  String encodeGroupDeletePayload({
    required String groupId,
    required String messageId,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_delete',
      'v': 1,
      'groupId': groupId,
      'groupMessageId': messageId,
      'senderPeerId': _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupDeletePrefix${jsonEncode(payload)}';
  }

  String encodeGroupChatDeletePayload(Chat groupChat) {
    final payload = <String, dynamic>{
      'type': 'group_chat_delete',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupName': groupChat.name,
      'memberPeerIds': groupChat.memberPeerIds,
      'ownerPeerId': groupChat.ownerPeerId ?? _localPeerId(),
      'senderPeerId': _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupChatDeletePrefix${jsonEncode(payload)}';
  }

  String encodeGroupBlobRefPayload({
    required Chat groupChat,
    required String messageId,
    required String contentKind,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    String? textPreview,
    required String blobId,
    List<String> blobRelayServers = const <String>[],
  }) {
    final payload = <String, dynamic>{
      'type': 'group_blob_ref',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupMessageId': messageId,
      'groupName': groupChat.name,
      'contentKind': contentKind,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSizeBytes': fileSizeBytes,
      'textPreview': textPreview,
      'blobId': blobId,
      if (blobRelayServers.isNotEmpty) 'blobRelayServers': blobRelayServers,
      'memberPeerIds': groupChat.memberPeerIds,
      'senderPeerId': _localPeerId(),
      'ownerPeerId': groupChat.ownerPeerId ?? _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$groupBlobRefPrefix${jsonEncode(payload)}';
  }

  String encodeGroupMembersPayload({
    required Chat groupChat,
    required String action,
    required List<String> changedPeerIds,
    List<String>? memberPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) {
    final payload = <String, dynamic>{
      'type': 'group_members',
      'v': 1,
      'groupId': groupChat.peerId,
      'groupName': groupChat.name,
      'ownerPeerId': groupChat.ownerPeerId ?? _localPeerId(),
      'memberPeerIds': memberPeerIds ?? groupChat.memberPeerIds,
      'changedPeerIds': changedPeerIds,
      'action': action,
      'senderPeerId': _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (avatarBlobId != null && avatarBlobId.trim().isNotEmpty) {
      payload['avatarBlobId'] = avatarBlobId.trim();
    }
    if (avatarMimeType != null && avatarMimeType.trim().isNotEmpty) {
      payload['avatarMimeType'] = avatarMimeType.trim();
    }
    if (avatarFileSizeBytes != null && avatarFileSizeBytes > 0) {
      payload['avatarFileSizeBytes'] = avatarFileSizeBytes;
    }
    if (avatarUpdatedAtMs != null && avatarUpdatedAtMs > 0) {
      payload['avatarUpdatedAtMs'] = avatarUpdatedAtMs;
    }
    return '$groupMembersPrefix${jsonEncode(payload)}';
  }

  String encodeDirectBlobRefPayload({
    required String peerId,
    required String messageId,
    required String contentKind,
    String? fileName,
    String? mimeType,
    int? fileSizeBytes,
    required String blobId,
    List<String> blobRelayServers = const <String>[],
  }) {
    final payload = <String, dynamic>{
      'type': 'direct_blob_ref',
      'v': 1,
      'peerId': _localPeerId(),
      'counterpartyPeerId': peerId,
      'messageId': messageId,
      'contentKind': contentKind,
      'fileName': fileName,
      'mimeType': mimeType,
      'fileSizeBytes': fileSizeBytes,
      'blobId': blobId,
      if (blobRelayServers.isNotEmpty) 'blobRelayServers': blobRelayServers,
      'senderPeerId': _localPeerId(),
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (contentKind == 'media') {
      payload['mediaCipher'] = 'direct_session_v1';
    }
    return '$directBlobRefPrefix${jsonEncode(payload)}';
  }

  String encodeMessageReceiptPayload({
    required String chatId,
    required bool isGroup,
    required List<String> messageIds,
    required String status,
    required int atMs,
  }) {
    final payload = <String, dynamic>{
      'type': 'message_receipt',
      'v': 1,
      'chatId': chatId,
      'chatKind': isGroup ? 'group' : 'direct',
      'messageIds': messageIds,
      'status': status,
      'senderPeerId': _localPeerId(),
      'atMs': atMs,
      'createdAt': DateTime.now().toIso8601String(),
    };
    return '$messageReceiptPrefix${jsonEncode(payload)}';
  }

  Map<String, dynamic>? decodeGroupInvitePayload(String text) =>
      _decodePrefixedJson(text, groupInvitePrefix);
  Map<String, dynamic>? decodeGroupMessagePayload(String text) =>
      _decodePrefixedJson(text, groupMessagePrefix);
  Map<String, dynamic>? decodeGroupDeletePayload(String text) =>
      _decodePrefixedJson(text, groupDeletePrefix);
  Map<String, dynamic>? decodeGroupChatDeletePayload(String text) =>
      _decodePrefixedJson(text, groupChatDeletePrefix);
  Map<String, dynamic>? decodeGroupMembersPayload(String text) =>
      _decodePrefixedJson(text, groupMembersPrefix);
  Map<String, dynamic>? decodeGroupKeyPayload(String text) =>
      _decodePrefixedJson(text, groupKeyPrefix);
  Map<String, dynamic>? decodeGroupKeyRequestPayload(String text) =>
      _decodePrefixedJson(text, groupKeyRequestPrefix);
  Map<String, dynamic>? decodeGroupSecurePayloadRaw(String text) =>
      _decodePrefixedJson(text, groupSecurePrefix);
  Map<String, dynamic>? decodeGroupBlobRefPayload(String text) =>
      _decodePrefixedJson(text, groupBlobRefPrefix);
  Map<String, dynamic>? decodeDirectBlobRefPayload(String text) =>
      _decodePrefixedJson(text, directBlobRefPrefix);
  Map<String, dynamic>? decodeMessageReceiptPayload(String text) =>
      _decodePrefixedJson(text, messageReceiptPrefix);

  Map<String, dynamic>? decodeGroupMembersPayloadForPush(String payloadText) =>
      _decodePrefixedJson(payloadText, groupMembersPrefix);

  String groupFileTransferId({
    required String groupId,
    required String messageId,
  }) => 'grpfile:$groupId|$messageId';
  String groupBlobTransferId({
    required String groupId,
    required String messageId,
    required String blobId,
    List<String> blobRelayServers = const <String>[],
  }) => _blobTransferId(
    prefix: 'grpblob',
    targetId: groupId,
    messageId: messageId,
    blobId: blobId,
    blobRelayServers: blobRelayServers,
  );
  String directBlobTransferId({
    required String peerId,
    required String messageId,
    required String blobId,
    List<String> blobRelayServers = const <String>[],
  }) => _blobTransferId(
    prefix: 'dirblob',
    targetId: peerId,
    messageId: messageId,
    blobId: blobId,
    blobRelayServers: blobRelayServers,
  );

  ({
    String groupId,
    String messageId,
    String blobId,
    List<String> blobRelayServers,
  })?
  parseGroupBlobTransferId(String? transferId) {
    final raw = transferId?.trim() ?? '';
    if (!raw.startsWith('grpblob:')) {
      return null;
    }
    final body = raw.substring('grpblob:'.length);
    final first = body.indexOf('|');
    final second = body.indexOf('|', first + 1);
    if (first <= 0 || second <= first + 1 || second >= body.length - 1) {
      return null;
    }
    final groupId = body.substring(0, first).trim();
    final messageId = body.substring(first + 1, second).trim();
    final remainder = body.substring(second + 1);
    final third = remainder.indexOf('|');
    final blobId = (third == -1 ? remainder : remainder.substring(0, third))
        .trim();
    if (groupId.isEmpty || messageId.isEmpty || blobId.isEmpty) {
      return null;
    }
    return (
      groupId: groupId,
      messageId: messageId,
      blobId: blobId,
      blobRelayServers: _decodeBlobRelayServers(
        third == -1 ? null : remainder.substring(third + 1),
      ),
    );
  }

  ({
    String peerId,
    String messageId,
    String blobId,
    List<String> blobRelayServers,
  })?
  parseDirectBlobTransferId(String? transferId) {
    final raw = transferId?.trim() ?? '';
    if (!raw.startsWith('dirblob:')) {
      return null;
    }
    final body = raw.substring('dirblob:'.length);
    final first = body.indexOf('|');
    final second = body.indexOf('|', first + 1);
    if (first <= 0 || second <= first + 1 || second >= body.length - 1) {
      return null;
    }
    final peerId = body.substring(0, first).trim();
    final messageId = body.substring(first + 1, second).trim();
    final remainder = body.substring(second + 1);
    final third = remainder.indexOf('|');
    final blobId = (third == -1 ? remainder : remainder.substring(0, third))
        .trim();
    if (peerId.isEmpty || messageId.isEmpty || blobId.isEmpty) {
      return null;
    }
    return (
      peerId: peerId,
      messageId: messageId,
      blobId: blobId,
      blobRelayServers: _decodeBlobRelayServers(
        third == -1 ? null : remainder.substring(third + 1),
      ),
    );
  }

  String _blobTransferId({
    required String prefix,
    required String targetId,
    required String messageId,
    required String blobId,
    required List<String> blobRelayServers,
  }) {
    final relays = blobRelayServers
        .map((server) => server.trim())
        .where((server) => server.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (relays.isEmpty) {
      return '$prefix:$targetId|$messageId|$blobId';
    }
    return '$prefix:$targetId|$messageId|$blobId|${base64UrlEncode(utf8.encode(jsonEncode(relays)))}';
  }

  List<String> _decodeBlobRelayServers(String? encoded) {
    if (encoded == null || encoded.isEmpty) return const <String>[];
    try {
      final decoded = jsonDecode(utf8.decode(base64Url.decode(encoded)));
      if (decoded is! List) return const <String>[];
      return decoded
          .whereType<String>()
          .map((server) => server.trim())
          .where((server) => server.isNotEmpty)
          .toSet()
          .toList(growable: false);
    } catch (_) {
      return const <String>[];
    }
  }

  Map<String, dynamic>? _decodePrefixedJson(String text, String prefix) {
    if (!text.startsWith(prefix)) {
      return null;
    }
    final raw = text.substring(prefix.length).trim();
    if (raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
