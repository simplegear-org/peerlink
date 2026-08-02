import '../../core/messaging/chat_service.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import 'chat_controller_models.dart';

typedef DecodePayload = Map<String, dynamic>? Function(String text);
typedef DecodeAccountPairRequest =
    AccountPairingRequestPayload? Function(ChatMessage msg);
typedef DecodeAccountPairApproval =
    AccountPairingApprovalPayload? Function(ChatMessage msg);
typedef DecodeAccountPairRejection =
    AccountPairingRejectedPayload? Function(ChatMessage msg);
typedef DecodeAccountMembershipUpdate =
    AccountMembershipUpdatePayload? Function(ChatMessage msg);

class ChatInboundClassifier {
  final DecodePayload decodeGroupInvitePayload;
  final DecodePayload decodeGroupKeyPayload;
  final DecodePayload decodeGroupDeletePayload;
  final DecodePayload decodeGroupChatDeletePayload;
  final DecodePayload decodeGroupMembersPayload;
  final DecodePayload decodeGroupMessagePayload;
  final DecodePayload decodeGroupSecurePayloadRaw;
  final DecodePayload decodeDirectBlobRefPayload;
  final DecodePayload decodeGroupBlobRefPayload;
  final DecodeAccountPairRequest decodeAccountPairRequestPayload;
  final DecodeAccountPairApproval decodeAccountPairApprovalPayload;
  final DecodeAccountPairRejection decodeAccountPairRejectionPayload;
  final DecodeAccountMembershipUpdate decodeAccountMembershipUpdatePayload;

  const ChatInboundClassifier({
    required this.decodeGroupInvitePayload,
    required this.decodeGroupKeyPayload,
    required this.decodeGroupDeletePayload,
    required this.decodeGroupChatDeletePayload,
    required this.decodeGroupMembersPayload,
    required this.decodeGroupMessagePayload,
    required this.decodeGroupSecurePayloadRaw,
    required this.decodeDirectBlobRefPayload,
    required this.decodeGroupBlobRefPayload,
    required this.decodeAccountPairRequestPayload,
    required this.decodeAccountPairApprovalPayload,
    required this.decodeAccountPairRejectionPayload,
    required this.decodeAccountMembershipUpdatePayload,
  });

  IncomingChatDispatch classifyIncomingMessage(ChatMessage msg) {
    if (msg.kind == 'delete') {
      return const IncomingDeleteDispatch();
    }
    if (msg.kind == 'profileAvatar') {
      return const IncomingProfileAvatarDispatch();
    }
    if (msg.kind == 'profileAvatarRemove') {
      return const IncomingProfileAvatarRemoveDispatch();
    }
    if (msg.kind == 'profileAvatarQuery') {
      return const IncomingProfileAvatarQueryDispatch();
    }
    final groupInvite = normalizeGroupInvitePayload(msg.text);
    if (groupInvite != null) {
      return IncomingGroupInviteDispatch(groupInvite);
    }
    final groupKey = normalizeGroupKeyPayload(msg.text);
    if (groupKey != null) {
      return IncomingGroupKeyDispatch(groupKey);
    }
    final groupDelete = normalizeGroupDeletePayload(msg.text);
    if (groupDelete != null) {
      return IncomingGroupDeleteDispatch(groupDelete);
    }
    final groupChatDelete = normalizeGroupChatDeletePayload(msg.text);
    if (groupChatDelete != null) {
      return IncomingGroupChatDeleteDispatch(groupChatDelete);
    }
    final groupMembers = normalizeGroupMembersPayload(msg.text);
    if (groupMembers != null) {
      return IncomingGroupMembersDispatch(groupMembers);
    }
    final groupMessage = normalizeGroupMessagePayload(msg.text);
    if (groupMessage != null) {
      return IncomingGroupMessageDispatch(groupMessage);
    }
    final groupSecure = normalizeGroupSecurePayload(msg.text);
    if (groupSecure != null) {
      return IncomingGroupSecureDispatch(groupSecure);
    }
    final blobRef = decodeIncomingBlobRefPayload(msg.text);
    if (blobRef != null && blobRef.isDirect) {
      return IncomingDirectBlobRefDispatch(blobRef);
    }
    final pairingRequest = decodeAccountPairRequestPayload(msg);
    if (pairingRequest != null) {
      return IncomingAccountPairRequestDispatch(pairingRequest);
    }
    final pairingApproval = decodeAccountPairApprovalPayload(msg);
    if (pairingApproval != null) {
      return IncomingAccountPairApprovalDispatch(pairingApproval);
    }
    final pairingRejection = decodeAccountPairRejectionPayload(msg);
    if (pairingRejection != null) {
      return IncomingAccountPairRejectionDispatch(pairingRejection);
    }
    final membershipUpdate = decodeAccountMembershipUpdatePayload(msg);
    if (membershipUpdate != null) {
      return IncomingAccountMembershipUpdateDispatch(membershipUpdate);
    }
    final isDisplayableKind = msg.kind == 'text' || msg.kind == 'file';
    if (isDisplayableKind) {
      return const IncomingDisplayableDispatch();
    }
    return const IncomingIgnoredDispatch();
  }

  IncomingBlobRefPayload? decodeIncomingBlobRefPayload(String text) {
    final direct = decodeDirectBlobRefPayload(text);
    if (direct != null) {
      return normalizeBlobRefPayload(
        direct,
        targetKind: 'direct',
        chatPeerId: (direct['peerId'] as String? ?? '').trim(),
        messageId: (direct['messageId'] as String? ?? '').trim(),
      );
    }

    final group = decodeGroupBlobRefPayload(text);
    if (group != null) {
      return normalizeBlobRefPayload(
        group,
        targetKind: 'group',
        chatPeerId: (group['groupId'] as String? ?? '').trim(),
        messageId: (group['groupMessageId'] as String? ?? '').trim(),
      );
    }
    return null;
  }

  IncomingGroupInvitePayload? normalizeGroupInvitePayload(String text) {
    final raw = decodeGroupInvitePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupName = (raw['groupName'] as String? ?? '').trim();
    if (groupId.isEmpty || groupName.isEmpty) {
      return null;
    }
    final memberPeerIds = _readStringList(raw['memberPeerIds']);
    return IncomingGroupInvitePayload(
      groupId: groupId,
      groupName: groupName,
      memberPeerIds: memberPeerIds,
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  IncomingGroupMessagePayload? normalizeGroupMessagePayload(String text) {
    final raw = decodeGroupMessagePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupMessageId = (raw['groupMessageId'] as String? ?? '').trim();
    final messageText = (raw['text'] as String? ?? '').trim();
    if (groupId.isEmpty || groupMessageId.isEmpty || messageText.isEmpty) {
      return null;
    }
    final memberPeerIds = _readStringList(raw['memberPeerIds']);
    return IncomingGroupMessagePayload(
      groupId: groupId,
      groupMessageId: groupMessageId,
      text: messageText,
      groupName: (raw['groupName'] as String? ?? '').trim(),
      memberPeerIds: memberPeerIds,
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  IncomingGroupDeletePayload? normalizeGroupDeletePayload(String text) {
    final raw = decodeGroupDeletePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupMessageId = (raw['groupMessageId'] as String? ?? '').trim();
    if (groupId.isEmpty || groupMessageId.isEmpty) {
      return null;
    }
    return IncomingGroupDeletePayload(
      groupId: groupId,
      groupMessageId: groupMessageId,
      raw: raw,
    );
  }

  IncomingGroupChatDeletePayload? normalizeGroupChatDeletePayload(
    String text,
  ) {
    final raw = decodeGroupChatDeletePayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    if (groupId.isEmpty) {
      return null;
    }
    return IncomingGroupChatDeletePayload(
      groupId: groupId,
      groupName: (raw['groupName'] as String? ?? '').trim(),
      memberPeerIds: _readStringList(raw['memberPeerIds']),
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      senderPeerId: (raw['senderPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  IncomingGroupMembersPayload? normalizeGroupMembersPayload(String text) {
    final raw = decodeGroupMembersPayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final rawMembers = raw['memberPeerIds'];
    if (groupId.isEmpty || rawMembers is! List) {
      return null;
    }
    final rawUpdatedAtMs = raw['avatarUpdatedAtMs'];
    final updatedAtMs = rawUpdatedAtMs is int
        ? rawUpdatedAtMs
        : int.tryParse('${rawUpdatedAtMs ?? ''}');
    return IncomingGroupMembersPayload(
      groupId: groupId,
      groupName: (raw['groupName'] as String? ?? '').trim(),
      ownerPeerId: (raw['ownerPeerId'] as String? ?? '').trim(),
      action: (raw['action'] as String? ?? '').trim(),
      memberPeerIds: _readStringList(rawMembers),
      changedPeerIds: _readStringList(raw['changedPeerIds']),
      avatarBlobId: (raw['avatarBlobId'] as String?)?.trim(),
      avatarMimeType: (raw['avatarMimeType'] as String?)?.trim(),
      avatarUpdatedAtMs: updatedAtMs,
      raw: raw,
    );
  }

  IncomingGroupKeyPayload? normalizeGroupKeyPayload(String text) {
    final raw = decodeGroupKeyPayload(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    final groupKey = (raw['groupKey'] as String? ?? '').trim();
    if (groupId.isEmpty || groupKey.isEmpty) {
      return null;
    }
    final keyVersion = raw['keyVersion'] is int
        ? raw['keyVersion'] as int
        : int.tryParse('${raw['keyVersion']}') ?? 1;
    return IncomingGroupKeyPayload(
      groupId: groupId,
      groupKey: groupKey,
      keyVersion: keyVersion,
      raw: raw,
    );
  }

  IncomingGroupSecurePayload? normalizeGroupSecurePayload(String text) {
    final raw = decodeGroupSecurePayloadRaw(text);
    if (raw == null) {
      return null;
    }
    final groupId = (raw['groupId'] as String? ?? '').trim();
    if (groupId.isEmpty) {
      return null;
    }
    return IncomingGroupSecurePayload(groupId: groupId, raw: raw);
  }

  IncomingBlobRefPayload? normalizeBlobRefPayload(
    Map<String, dynamic> raw, {
    required String targetKind,
    required String chatPeerId,
    required String messageId,
  }) {
    final blobId = (raw['blobId'] as String? ?? '').trim();
    if (chatPeerId.isEmpty || messageId.isEmpty || blobId.isEmpty) {
      return null;
    }
    return IncomingBlobRefPayload(
      targetKind: targetKind,
      chatPeerId: chatPeerId,
      messageId: messageId,
      contentKind: (raw['contentKind'] as String? ?? '').trim(),
      blobId: blobId,
      fileName: (raw['fileName'] as String?)?.trim(),
      mimeType: (raw['mimeType'] as String?)?.trim(),
      fileSizeBytes: raw['fileSizeBytes'] as int?,
      textPreview: (raw['textPreview'] as String?)?.trim(),
      groupName: (raw['groupName'] as String?)?.trim(),
      memberPeerIds: _readStringList(raw['memberPeerIds']),
      ownerPeerId: (raw['ownerPeerId'] as String?)?.trim(),
      raw: raw,
    );
  }

  List<String> _readStringList(Object? raw) {
    if (raw is! List) {
      return <String>[];
    }
    final values = <String>[];
    for (final item in raw) {
      if (item is String && item.trim().isNotEmpty) {
        values.add(item.trim());
      }
    }
    return values;
  }
}
