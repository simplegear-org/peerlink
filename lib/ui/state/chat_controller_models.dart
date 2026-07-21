import 'dart:async';

import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';

enum ChatConnectionStatus { disconnected, connecting, connected, error }

class PendingProgressUpdate {
  int sentBytes;
  int? totalBytes;
  String statusText;
  DateTime lastAppliedAt;
  Timer? timer;

  PendingProgressUpdate({
    required this.sentBytes,
    required this.totalBytes,
    required this.statusText,
    required this.lastAppliedAt,
  });
}

class FileTransferCancelledException implements Exception {
  const FileTransferCancelledException();

  @override
  String toString() => 'File transfer cancelled';
}

class IncomingBlobRefPayload {
  final String targetKind;
  final String chatPeerId;
  final String messageId;
  final String contentKind;
  final String blobId;
  final String? fileName;
  final String? mimeType;
  final int? fileSizeBytes;
  final String? textPreview;
  final String? groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final Map<String, dynamic> raw;

  const IncomingBlobRefPayload({
    required this.targetKind,
    required this.chatPeerId,
    required this.messageId,
    required this.contentKind,
    required this.blobId,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    required this.textPreview,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.raw,
  });

  bool get isGroup => targetKind == 'group';
  bool get isDirect => targetKind == 'direct';
}

class IncomingGroupInvitePayload {
  final String groupId;
  final String groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final Map<String, dynamic> raw;

  const IncomingGroupInvitePayload({
    required this.groupId,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.raw,
  });
}

class IncomingGroupMessagePayload {
  final String groupId;
  final String groupMessageId;
  final String text;
  final String groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final Map<String, dynamic> raw;

  const IncomingGroupMessagePayload({
    required this.groupId,
    required this.groupMessageId,
    required this.text,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.raw,
  });
}

class IncomingGroupDeletePayload {
  final String groupId;
  final String groupMessageId;
  final Map<String, dynamic> raw;

  const IncomingGroupDeletePayload({
    required this.groupId,
    required this.groupMessageId,
    required this.raw,
  });
}

enum OutgoingRelayMediaTargetKind { direct, group }

class OutgoingRelayMediaState {
  final String peerId;
  final String messageId;
  final OutgoingRelayMediaTargetKind targetKind;
  final String blobId;
  final String payloadText;
  final List<String>? recipients;
  final String? localFilePath;
  final String? replyToMessageId;
  final String? replyToSenderPeerId;
  final String? replyToSenderLabel;
  final String? replyToTextPreview;
  final String? replyToKind;

  const OutgoingRelayMediaState({
    required this.peerId,
    required this.messageId,
    required this.targetKind,
    required this.blobId,
    required this.payloadText,
    required this.recipients,
    required this.localFilePath,
    required this.replyToMessageId,
    required this.replyToSenderPeerId,
    required this.replyToSenderLabel,
    required this.replyToTextPreview,
    required this.replyToKind,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'peerId': peerId,
    'messageId': messageId,
    'targetKind': targetKind.name,
    'blobId': blobId,
    'payloadText': payloadText,
    'recipients': recipients,
    'localFilePath': localFilePath,
    'replyToMessageId': replyToMessageId,
    'replyToSenderPeerId': replyToSenderPeerId,
    'replyToSenderLabel': replyToSenderLabel,
    'replyToTextPreview': replyToTextPreview,
    'replyToKind': replyToKind,
  };

  static OutgoingRelayMediaState? fromJson(Map<String, dynamic> json) {
    final peerId = json['peerId'];
    final messageId = json['messageId'];
    final targetKindRaw = json['targetKind'];
    final blobId = json['blobId'];
    final payloadText = json['payloadText'];
    if (peerId is! String ||
        messageId is! String ||
        targetKindRaw is! String ||
        blobId is! String ||
        payloadText is! String) {
      return null;
    }
    final kinds = OutgoingRelayMediaTargetKind.values.where(
      (value) => value.name == targetKindRaw,
    );
    if (kinds.isEmpty) {
      return null;
    }
    return OutgoingRelayMediaState(
      peerId: peerId,
      messageId: messageId,
      targetKind: kinds.first,
      blobId: blobId,
      payloadText: payloadText,
      recipients: json['recipients'] is List
          ? (json['recipients'] as List).whereType<String>().toList(
              growable: false,
            )
          : null,
      localFilePath: json['localFilePath'] as String?,
      replyToMessageId: json['replyToMessageId'] as String?,
      replyToSenderPeerId: json['replyToSenderPeerId'] as String?,
      replyToSenderLabel: json['replyToSenderLabel'] as String?,
      replyToTextPreview: json['replyToTextPreview'] as String?,
      replyToKind: json['replyToKind'] as String?,
    );
  }
}

class IncomingGroupChatDeletePayload {
  final String groupId;
  final String groupName;
  final List<String> memberPeerIds;
  final String? ownerPeerId;
  final String? senderPeerId;
  final Map<String, dynamic> raw;

  const IncomingGroupChatDeletePayload({
    required this.groupId,
    required this.groupName,
    required this.memberPeerIds,
    required this.ownerPeerId,
    required this.senderPeerId,
    required this.raw,
  });
}

class IncomingGroupMembersPayload {
  final String groupId;
  final String groupName;
  final String ownerPeerId;
  final String action;
  final List<String> memberPeerIds;
  final List<String> changedPeerIds;
  final String? avatarBlobId;
  final String? avatarMimeType;
  final int? avatarUpdatedAtMs;
  final Map<String, dynamic> raw;

  const IncomingGroupMembersPayload({
    required this.groupId,
    required this.groupName,
    required this.ownerPeerId,
    required this.action,
    required this.memberPeerIds,
    required this.changedPeerIds,
    required this.avatarBlobId,
    required this.avatarMimeType,
    required this.avatarUpdatedAtMs,
    required this.raw,
  });
}

class IncomingGroupKeyPayload {
  final String groupId;
  final String groupKey;
  final int keyVersion;
  final Map<String, dynamic> raw;

  const IncomingGroupKeyPayload({
    required this.groupId,
    required this.groupKey,
    required this.keyVersion,
    required this.raw,
  });
}

class IncomingGroupSecurePayload {
  final String groupId;
  final Map<String, dynamic> raw;

  const IncomingGroupSecurePayload({required this.groupId, required this.raw});
}

sealed class IncomingChatDispatch {
  const IncomingChatDispatch();
}

final class IncomingDeleteDispatch extends IncomingChatDispatch {
  const IncomingDeleteDispatch();
}

final class IncomingProfileAvatarDispatch extends IncomingChatDispatch {
  const IncomingProfileAvatarDispatch();
}

final class IncomingProfileAvatarRemoveDispatch extends IncomingChatDispatch {
  const IncomingProfileAvatarRemoveDispatch();
}

final class IncomingProfileAvatarQueryDispatch extends IncomingChatDispatch {
  const IncomingProfileAvatarQueryDispatch();
}

final class IncomingGroupInviteDispatch extends IncomingChatDispatch {
  final IncomingGroupInvitePayload payload;

  const IncomingGroupInviteDispatch(this.payload);
}

final class IncomingGroupKeyDispatch extends IncomingChatDispatch {
  final IncomingGroupKeyPayload payload;

  const IncomingGroupKeyDispatch(this.payload);
}

final class IncomingGroupDeleteDispatch extends IncomingChatDispatch {
  final IncomingGroupDeletePayload payload;

  const IncomingGroupDeleteDispatch(this.payload);
}

final class IncomingGroupChatDeleteDispatch extends IncomingChatDispatch {
  final IncomingGroupChatDeletePayload payload;

  const IncomingGroupChatDeleteDispatch(this.payload);
}

final class IncomingGroupMembersDispatch extends IncomingChatDispatch {
  final IncomingGroupMembersPayload payload;

  const IncomingGroupMembersDispatch(this.payload);
}

final class IncomingGroupMessageDispatch extends IncomingChatDispatch {
  final IncomingGroupMessagePayload payload;

  const IncomingGroupMessageDispatch(this.payload);
}

final class IncomingGroupSecureDispatch extends IncomingChatDispatch {
  final IncomingGroupSecurePayload payload;

  const IncomingGroupSecureDispatch(this.payload);
}

final class IncomingDirectBlobRefDispatch extends IncomingChatDispatch {
  final IncomingBlobRefPayload blobRef;

  const IncomingDirectBlobRefDispatch(this.blobRef);
}

final class IncomingAccountPairRequestDispatch extends IncomingChatDispatch {
  final AccountPairingRequestPayload payload;

  const IncomingAccountPairRequestDispatch(this.payload);
}

final class IncomingAccountPairApprovalDispatch extends IncomingChatDispatch {
  final AccountPairingApprovalPayload payload;

  const IncomingAccountPairApprovalDispatch(this.payload);
}

final class IncomingAccountPairRejectionDispatch extends IncomingChatDispatch {
  final AccountPairingRejectedPayload payload;

  const IncomingAccountPairRejectionDispatch(this.payload);
}

final class IncomingAccountMembershipUpdateDispatch
    extends IncomingChatDispatch {
  final AccountMembershipUpdatePayload payload;

  const IncomingAccountMembershipUpdateDispatch(this.payload);
}

final class IncomingDisplayableDispatch extends IncomingChatDispatch {
  const IncomingDisplayableDispatch();
}

final class IncomingIgnoredDispatch extends IncomingChatDispatch {
  const IncomingIgnoredDispatch();
}
