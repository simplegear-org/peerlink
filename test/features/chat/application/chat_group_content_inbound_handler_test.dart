import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/application/chat_group_content_inbound_handler.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_group_flow_service.dart';
import 'package:peerlink/features/chat/application/chat_group_service.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';

const _groupId = 'group:1';
const _owner = 'owner-peer';
const _local = 'local-peer';

class _FakeChatRuntimeApi extends Fake implements ChatRuntimeApi {
  @override
  String get peerId => 'admin-peer';
}

class _FakeStorageService extends Fake implements StorageService {}

class _FakeGroupFlowService extends Fake implements ChatGroupFlowService {}

Chat _groupChat() => Chat(
  peerId: _groupId,
  name: 'Group',
  isGroup: true,
  memberPeerIds: <String>[_owner, _local, 'member-peer'],
  ownerPeerId: _owner,
);

IncomingGroupMembersPayload _payload({
  required String action,
  required List<String> members,
  required String ownerPeerId,
  List<String> changedPeerIds = const <String>[],
  Map<String, dynamic> raw = const <String, dynamic>{},
}) => IncomingGroupMembersPayload(
  groupId: _groupId,
  groupName: 'Group',
  ownerPeerId: ownerPeerId,
  action: action,
  memberPeerIds: members,
  changedPeerIds: changedPeerIds,
  avatarBlobId: null,
  avatarMimeType: null,
  avatarUpdatedAtMs: null,
  raw: raw,
);

Future<void> _apply(
  Map<String, Chat> chats, {
  required String sourcePeerId,
  required IncomingGroupMembersPayload payload,
  void Function(Chat chat)? onPersist,
  Future<void> Function(
    ChatMessage msg, {
    required IncomingGroupMembersPayload payload,
  })?
  onLeave,
}) {
  return const ChatGroupContentInboundHandler()
      .handleIncomingGroupMembersUpdate(
        ChatMessage(
          id: 'control-1',
          peerId: sourcePeerId,
          senderPeerId: sourcePeerId,
          text: 'ignored',
        ),
        payload: payload,
        normalizePayload: (_) => null,
        isGroupDeleted: (_) => false,
        restoreDeletedGroup: (_) async {},
        chats: chats,
        knownGroupOwnerPeerId: (groupId) => groupId == _groupId ? _owner : null,
        localPeerId: _local,
        persistChatSummary: (chat) async => onPersist?.call(chat),
        saveGroupAvatarBytes:
            ({
              required groupChat,
              required bytes,
              required mimeType,
              required updatedAtMs,
            }) async {},
        downloadBlob: (_) => throw UnimplementedError(),
        decryptGroupBytes:
            ({required groupId, required encryptedBytes}) async => Uint8List(0),
        handleIncomingGroupLeave: onLeave ?? (msg, {required payload}) async {},
        notifyMessageUpdated: (_) {},
      );
}

void main() {
  test('known owner can apply an add membership mutation', () async {
    final chats = <String, Chat>{_groupId: _groupChat()};
    var persisted = 0;

    await _apply(
      chats,
      sourcePeerId: _owner,
      payload: _payload(
        action: 'add',
        ownerPeerId: _owner,
        members: <String>[_owner, _local, 'member-peer', 'new-peer'],
        changedPeerIds: const <String>['new-peer'],
      ),
      onPersist: (_) => persisted++,
    );

    expect(chats[_groupId]!.memberPeerIds, contains('new-peer'));
    expect(chats[_groupId]!.ownerPeerId, _owner);
    expect(persisted, 1);
  });

  test('known owner can apply a remove membership mutation', () async {
    final chats = <String, Chat>{_groupId: _groupChat()};

    await _apply(
      chats,
      sourcePeerId: _owner,
      payload: _payload(
        action: 'remove',
        ownerPeerId: _owner,
        members: <String>[_owner, _local],
        changedPeerIds: const <String>['member-peer'],
      ),
    );

    expect(chats[_groupId]!.memberPeerIds, isNot(contains('member-peer')));
    expect(chats[_groupId]!.ownerPeerId, _owner);
  });

  test('ordinary member cannot mutate membership', () async {
    final chats = <String, Chat>{_groupId: _groupChat()};
    var persisted = 0;

    await _apply(
      chats,
      sourcePeerId: 'member-peer',
      payload: _payload(
        action: 'remove',
        ownerPeerId: _owner,
        members: <String>[_owner, _local, 'member-peer'],
        changedPeerIds: const <String>['new-peer'],
      ),
      onPersist: (_) => persisted++,
    );

    expect(chats[_groupId]!.memberPeerIds, isNot(contains('new-peer')));
    expect(persisted, 0);
  });

  test('forged owner or admin metadata cannot authorize a member', () async {
    final chats = <String, Chat>{_groupId: _groupChat()};
    var persisted = 0;

    await _apply(
      chats,
      sourcePeerId: 'member-peer',
      payload: _payload(
        action: 'add',
        ownerPeerId: 'member-peer',
        members: <String>[_owner, _local, 'member-peer', 'attacker-peer'],
        changedPeerIds: const <String>['attacker-peer'],
        raw: const <String, dynamic>{
          'ownerPeerId': 'member-peer',
          'adminPeerIds': <String>['member-peer'],
        },
      ),
      onPersist: (_) => persisted++,
    );

    expect(chats[_groupId]!.memberPeerIds, isNot(contains('attacker-peer')));
    expect(chats[_groupId]!.ownerPeerId, _owner);
    expect(persisted, 0);
  });

  test('legacy leave remains a separate member-originated flow', () async {
    final chats = <String, Chat>{_groupId: _groupChat()};
    var leaves = 0;

    await _apply(
      chats,
      sourcePeerId: 'member-peer',
      payload: _payload(
        action: 'leave',
        ownerPeerId: 'member-peer',
        members: const <String>[],
      ),
      onLeave: (_, {required payload}) async => leaves++,
    );

    expect(leaves, 1);
  });

  test('local admin cannot start participant mutation side effects', () async {
    final chat = _groupChat()..adminPeerIds = <String>['admin-peer'];
    final chats = <String, Chat>{_groupId: chat};
    final service = ChatGroupService(
      facade: _FakeChatRuntimeApi(),
      storage: _FakeStorageService(),
      groupFlowService: _FakeGroupFlowService(),
    );
    var persisted = 0;

    await expectLater(
      service.addGroupParticipants(
        groupId: _groupId,
        participantPeerIds: const <String>['new-peer'],
        chats: chats,
        persistChatSummary: (_) async => persisted++,
        notifyMessageUpdated: (_) {},
      ),
      throwsA(isA<StateError>()),
    );

    expect(chat.memberPeerIds, isNot(contains('new-peer')));
    expect(persisted, 0);
  });
}
