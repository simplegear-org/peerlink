import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/node/node_facade.dart';
import '../../core/security/group_key_service.dart';
import '../models/chat.dart';
import 'chat_outbound_codec.dart';

class ChatGroupFlowService {
  final NodeFacade facade;
  final GroupKeyService groupKeyService;
  final ChatOutboundCodec outboundCodec;
  final String Function() nextLocalMessageId;

  const ChatGroupFlowService({
    required this.facade,
    required this.groupKeyService,
    required this.outboundCodec,
    required this.nextLocalMessageId,
  });

  Future<String> ensureGroupKey(Chat groupChat) {
    return groupKeyService.ensureGroupKey(groupChat.peerId);
  }

  List<String> collectGroupRecipients(Chat groupChat) {
    final recipients = <String>{};
    for (final item in groupChat.memberPeerIds) {
      final peerId = item.trim();
      if (peerId.isNotEmpty && peerId != facade.peerId) {
        recipients.add(peerId);
      }
    }
    final list = recipients.toList(growable: false);
    list.sort();
    return list;
  }

  Future<void> sendGroupKeyToRecipients(
    Chat groupChat,
    List<String> recipients, {
    String? groupKeyBase64,
    int? keyVersion,
  }) async {
    final groupKey = groupKeyBase64 ?? await ensureGroupKey(groupChat);
    final versionCandidate =
        keyVersion ?? groupKeyService.keyVersionForGroup(groupChat.peerId);
    final resolvedVersion = versionCandidate <= 0 ? 1 : versionCandidate;
    final payload = outboundCodec.encodeGroupKeyPayload(
      groupChat: groupChat,
      groupKeyBase64: groupKey,
      keyVersion: resolvedVersion,
    );
    final targets = recipients
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != facade.peerId)
        .toSet()
        .toList(growable: false);
    for (var i = 0; i < targets.length; i++) {
      try {
        await facade.sendControlMessage(
          targets[i],
          kind: 'groupKey',
          text: payload,
        );
      } catch (_) {
        // Best effort, peer may be offline; relay retry/poll will reconcile.
      }
    }
  }

  Future<void> rotateGroupKey(
    Chat groupChat, {
    required List<String> recipients,
  }) async {
    final rotation = await groupKeyService.rotateGroupKey(groupChat.peerId);
    await sendGroupKeyToRecipients(
      groupChat,
      recipients,
      groupKeyBase64: rotation.keyBase64,
      keyVersion: rotation.version,
    );
  }

  Future<void> syncGroupMembershipWithRelay(Chat groupChat) async {
    final ownerPeerId = (groupChat.ownerPeerId ?? '').trim();
    if (ownerPeerId.isEmpty || ownerPeerId != facade.peerId) {
      return;
    }
    final members = <String>{
      ...groupChat.memberPeerIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
      facade.peerId,
    }.toList(growable: false)..sort();
    try {
      await facade.updateRelayGroupMembers(
        groupId: groupChat.peerId,
        ownerPeerId: ownerPeerId,
        memberPeerIds: members,
      );
    } catch (error) {
      developer.log(
        'group membership sync failed group=${groupChat.peerId} error=$error',
        name: 'chat',
      );
    }
  }

  Future<void> sendGroupInvites(
    Chat groupChat, {
    List<String>? recipients,
  }) async {
    final targetRecipients = (recipients ?? groupChat.memberPeerIds)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != facade.peerId)
        .toSet()
        .toList(growable: false);
    if (targetRecipients.isEmpty) {
      return;
    }

    final allMembers = <String>{
      ...groupChat.memberPeerIds
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty),
      facade.peerId,
    }.toList(growable: false);
    final payload = outboundCodec.encodeGroupInvitePayload(
      groupId: groupChat.peerId,
      groupName: groupChat.name,
      memberPeerIds: allMembers,
      ownerPeerId: groupChat.ownerPeerId ?? facade.peerId,
    );

    for (var i = 0; i < targetRecipients.length; i++) {
      final recipient = targetRecipients[i];
      final messageId =
          'invite:${groupChat.peerId}:${nextLocalMessageId()}:$i';
      try {
        developer.log(
          'group invite send start group=${groupChat.peerId} recipient=$recipient messageId=$messageId',
          name: 'chat',
        );
        await facade.sendControlMessage(
          recipient,
          kind: 'groupInvite',
          text: payload,
        );
        developer.log(
          'group invite send queued group=${groupChat.peerId} recipient=$recipient messageId=$messageId',
          name: 'chat',
        );
      } catch (error) {
        developer.log(
          'group invite send failed group=${groupChat.peerId} recipient=$recipient error=$error',
          name: 'chat',
        );
      }
    }
  }

  Future<void> broadcastGroupMembersUpdate({
    required Chat groupChat,
    required List<String> recipients,
    required String action,
    required List<String> changedPeerIds,
    String? avatarBlobId,
    String? avatarMimeType,
    int? avatarFileSizeBytes,
    int? avatarUpdatedAtMs,
  }) async {
    final payload = outboundCodec.encodeGroupMembersPayload(
      groupChat: groupChat,
      action: action,
      changedPeerIds: changedPeerIds,
      avatarBlobId: avatarBlobId,
      avatarMimeType: avatarMimeType,
      avatarFileSizeBytes: avatarFileSizeBytes,
      avatarUpdatedAtMs: avatarUpdatedAtMs,
    );
    final targets = recipients
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != facade.peerId)
        .toSet()
        .toList(growable: false);
    Map<String, dynamic>? pushPayload;
    if (action == 'remove') {
      pushPayload = outboundCodec.decodeGroupMembersPayloadForPush(payload);
    }
    for (final peerId in targets) {
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'groupMembers',
          text: payload,
        );
      } catch (_) {
        // Best effort.
      }
      if (pushPayload != null) {
        try {
          await facade.sendDirectPushEvent(
            directPeerId: peerId,
            messageId:
                'group-members:${groupChat.peerId}:${DateTime.now().microsecondsSinceEpoch}',
            data: <String, dynamic>{
              'type': 'group_members_update',
              'groupMembers': pushPayload,
            },
          );
        } catch (_) {
          // Best effort.
        }
      }
    }
  }

  Future<void> broadcastGroupChatDelete(Chat groupChat) async {
    final recipients = <String>{...collectGroupRecipients(groupChat)};
    final ownerPeerId = groupChat.ownerPeerId?.trim();
    if (ownerPeerId != null &&
        ownerPeerId.isNotEmpty &&
        ownerPeerId != facade.peerId) {
      recipients.add(ownerPeerId);
    }
    if (recipients.isEmpty) {
      return;
    }

    final payload = outboundCodec.encodeGroupChatDeletePayload(groupChat);
    for (final peerId in recipients) {
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'groupChatDelete',
          text: payload,
        );
      } catch (error) {
        developer.log(
          'group chat delete send failed group=${groupChat.peerId} recipient=$peerId error=$error',
          name: 'chat',
        );
      }
    }
  }

  Future<void> sendGroupLeaveBeforeLocalDelete(Chat groupChat) async {
    final selfPeerId = facade.peerId;
    final remainingMembers = groupChat.memberPeerIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item != selfPeerId)
        .toSet()
        .toList(growable: false);
    remainingMembers.sort();

    final recipients = <String>{...remainingMembers};
    final ownerPeerId = groupChat.ownerPeerId?.trim();
    if (ownerPeerId != null &&
        ownerPeerId.isNotEmpty &&
        ownerPeerId != selfPeerId) {
      recipients.add(ownerPeerId);
      if (!remainingMembers.contains(ownerPeerId)) {
        remainingMembers.add(ownerPeerId);
        remainingMembers.sort();
      }
    }
    if (recipients.isEmpty) {
      return;
    }

    final payload = outboundCodec.encodeGroupMembersPayload(
      groupChat: groupChat,
      action: 'leave',
      changedPeerIds: <String>[selfPeerId],
      memberPeerIds: remainingMembers,
    );
    for (final peerId in recipients) {
      try {
        await facade.sendControlMessage(
          peerId,
          kind: 'groupMembers',
          text: payload,
        );
      } catch (error) {
        developer.log(
          'group leave send failed group=${groupChat.peerId} recipient=$peerId error=$error',
          name: 'chat',
        );
      }
    }
  }
}
