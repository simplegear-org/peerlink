import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_group_content_inbound_handler.dart';
import 'package:peerlink/features/chat/application/chat_inbound_classifier.dart';
import 'package:peerlink/features/chat/application/chat_inbound_service.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/profile/application/avatar_service.dart';

class _FakeNodeFacade extends Fake implements ChatRuntimeApi {}

class _FakeStorageBox extends Fake implements SecureStorageBox {}

class _FakeAvatarService extends Fake implements AvatarService {}

PeerAccessControlService _allowAllAccessControl(StorageService storage) {
  return PeerAccessControlService(
    settingsBox: storage.getSettings(),
    contactsRepository: ContactsRepository(storage: storage),
  );
}

ChatInboundClassifier _emptyInboundClassifier() {
  return ChatInboundClassifier(
    decodeGroupInvitePayload: (_) => null,
    decodeGroupKeyPayload: (_) => null,
    decodeGroupDeletePayload: (_) => null,
    decodeGroupChatDeletePayload: (_) => null,
    decodeGroupMembersPayload: (_) => null,
    decodeGroupMessagePayload: (_) => null,
    decodeGroupSecurePayloadRaw: (_) => null,
    decodeGroupKeyRequestPayload: (_) => null,
    decodeDirectBlobRefPayload: (_) => null,
    decodeGroupBlobRefPayload: (_) => null,
    decodeMessageReceiptPayload: (_) => null,
    decodeAccountPairRequestPayload: (_) => null,
    decodeAccountPairApprovalPayload: (_) => null,
    decodeAccountPairRejectionPayload: (_) => null,
    decodeAccountMembershipUpdatePayload: (_) => null,
  );
}

void main() {
  late StorageService storage;

  setUp(() async {
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(
      rootDirectory: Directory.systemTemp.createTempSync('peerlink-test-'),
    );
  });

  test(
    'unknown peer with contacts-only does not append direct message',
    () async {
      final service = ChatInboundService(
        facade: _FakeNodeFacade(),
        settingsBox: _FakeStorageBox(),
        avatarService: _FakeAvatarService(),
        accessControl: _allowAllAccessControl(storage),
        inboundClassifier: _emptyInboundClassifier(),
      );
      final appended = <Message>[];
      var notified = false;

      await service.handleIncomingMessage(
        ChatMessage(id: 'm1', peerId: 'unknown-peer', text: 'hello'),
        handleIncomingGroupInvite: (_, _) async =>
            fail('unexpected group invite'),
        handleIncomingGroupKey: (_, _) async => fail('unexpected group key'),
        handleIncomingGroupKeyRequest: (_, _) async =>
            fail('unexpected group key request'),
        handleIncomingGroupDelete: (_, _) async =>
            fail('unexpected group delete'),
        handleIncomingGroupChatDelete: (_, _) async =>
            fail('unexpected group chat delete'),
        handleIncomingGroupMembersUpdate: (_, _) async =>
            fail('unexpected members update'),
        handleIncomingGroupMessage: (_, _) async =>
            fail('unexpected group message'),
        handleIncomingGroupSecureMessage: (_, _) async =>
            fail('unexpected group secure'),
        handleIncomingDirectBlobRef: (_, _) async =>
            fail('unexpected direct blob'),
        handleIncomingMessageReceipt: (_) async =>
            fail('unexpected message receipt'),
        removeMessageWithMediaCleanup: (_, _) async => false,
        removeMessageByAuthorWithMediaCleanup: (_, _, _) async => false,
        isGroupDeletePayload: (_) => false,
        setStatus: (_, _, {error}) {},
        appendMessage: (_, message) async => appended.add(message),
        unreadMessagesCount: () => 0,
        notifyMessageUpdated: (_) => notified = true,
        notifyNewMessage: (_) => notified = true,
        showMessageNotification:
            ({
              required fromPeerId,
              required message,
              required badgeCount,
            }) async {
              notified = true;
            },
      );

      expect(appended, isEmpty);
      expect(notified, isFalse);
    },
  );

  test('blocked peer does not append direct message', () async {
    final accessControl = _allowAllAccessControl(storage);
    await accessControl.blockPeer('blocked-peer');
    final service = ChatInboundService(
      facade: _FakeNodeFacade(),
      settingsBox: _FakeStorageBox(),
      avatarService: _FakeAvatarService(),
      accessControl: accessControl,
      inboundClassifier: _emptyInboundClassifier(),
    );
    final appended = <Message>[];

    await service.handleIncomingMessage(
      ChatMessage(id: 'm1', peerId: 'blocked-peer', text: 'hello'),
      handleIncomingGroupInvite: (_, _) async =>
          fail('unexpected group invite'),
      handleIncomingGroupKey: (_, _) async => fail('unexpected group key'),
      handleIncomingGroupKeyRequest: (_, _) async =>
          fail('unexpected group key request'),
      handleIncomingGroupDelete: (_, _) async =>
          fail('unexpected group delete'),
      handleIncomingGroupChatDelete: (_, _) async =>
          fail('unexpected group chat delete'),
      handleIncomingGroupMembersUpdate: (_, _) async =>
          fail('unexpected members update'),
      handleIncomingGroupMessage: (_, _) async =>
          fail('unexpected group message'),
      handleIncomingGroupSecureMessage: (_, _) async =>
          fail('unexpected group secure'),
      handleIncomingDirectBlobRef: (_, _) async =>
          fail('unexpected direct blob'),
      handleIncomingMessageReceipt: (_) async =>
          fail('unexpected message receipt'),
      removeMessageWithMediaCleanup: (_, _) async => false,
      removeMessageByAuthorWithMediaCleanup: (_, _, _) async => false,
      isGroupDeletePayload: (_) => false,
      setStatus: (_, _, {error}) {},
      appendMessage: (_, message) async => appended.add(message),
      unreadMessagesCount: () => 0,
      notifyMessageUpdated: (_) {},
      notifyNewMessage: (_) {},
      showMessageNotification:
          ({
            required fromPeerId,
            required message,
            required badgeCount,
          }) async {},
    );

    expect(appended, isEmpty);
  });

  test('group blob-ref restores missing group chat summary', () async {
    final service = ChatInboundService(
      facade: _FakeNodeFacade(),
      settingsBox: _FakeStorageBox(),
      avatarService: _FakeAvatarService(),
      accessControl: _allowAllAccessControl(storage),
      inboundClassifier: ChatInboundClassifier(
        decodeGroupInvitePayload: (_) => null,
        decodeGroupKeyPayload: (_) => null,
        decodeGroupDeletePayload: (_) => null,
        decodeGroupChatDeletePayload: (_) => null,
        decodeGroupMembersPayload: (_) => null,
        decodeGroupMessagePayload: (_) => null,
        decodeGroupSecurePayloadRaw: (_) => null,
        decodeGroupKeyRequestPayload: (_) => null,
        decodeDirectBlobRefPayload: (_) => null,
        decodeGroupBlobRefPayload: (_) => null,
        decodeMessageReceiptPayload: (_) => null,
        decodeAccountPairRequestPayload: (_) => null,
        decodeAccountPairApprovalPayload: (_) => null,
        decodeAccountPairRejectionPayload: (_) => null,
        decodeAccountMembershipUpdatePayload: (_) => null,
      ),
    );
    final chat = Chat(
      peerId: 'group:lost',
      name: 'group:lost',
      isGroup: true,
      memberPeerIds: const <String>['owner-peer', 'sender-peer'],
      ownerPeerId: 'sender-peer',
      messagesLoaded: true,
      hasMoreMessages: false,
    );
    final persisted = <Chat>[];
    final appended = <Message>[];

    await service.handleIncomingGroupBlobRef(
      ChatMessage(
        id: 'relay-1',
        peerId: 'group:lost',
        senderPeerId: 'sender-peer',
        text: 'encrypted-blob-ref',
      ),
      groupId: 'group:lost',
      groupChat: chat,
      existingGroupChat: null,
      blobRef: const IncomingBlobRefPayload(
        targetKind: 'group',
        chatPeerId: 'group:lost',
        messageId: 'group-msg-1',
        contentKind: 'text',
        blobId: 'blob-1',
        fileName: null,
        mimeType: null,
        fileSizeBytes: null,
        textPreview: 'hello',
        groupName: 'Recovered Group',
        memberPeerIds: <String>['owner-peer', 'sender-peer'],
        ownerPeerId: 'owner-peer',
        raw: <String, dynamic>{},
      ),
      notificationSenderLabel: 'Recovered Group',
      localPeerId: 'owner-peer',
      restoreGroupBlobText:
          ({required groupId, required blobId, relayServers, fallback}) =>
              Future<String?>.value(fallback),
      downloadBlob: (_) => throw UnimplementedError(),
      decodeGroupBlobBytes:
          ({required groupId, required encryptedBytes}) async => encryptedBytes,
      saveGroupAvatarBytes:
          ({
            required groupChat,
            required bytes,
            required mimeType,
            required updatedAtMs,
          }) async {},
      persistChatSummary: (chat) async {
        persisted.add(Chat.fromJson(Map<String, dynamic>.from(chat.toJson())));
      },
      groupBlobTransferId:
          ({
            required groupId,
            required messageId,
            required blobId,
            blobRelayServers = const <String>[],
          }) => '$groupId|$messageId|$blobId',
      appendMessage: (peerId, message) async => appended.add(message),
      notifyMessageUpdated: (_) {},
      restoreMediaInBackground: (_, {required isGroup, force = false}) {},
      notifyNewMessage: (_) {},
      unreadMessagesCount: () => 1,
      showMessageNotification:
          ({required fromPeerId, required message, required badgeCount}) async {
            expect(fromPeerId, 'Recovered Group');
          },
    );

    expect(persisted, isNotEmpty);
    expect(persisted.first.peerId, 'group:lost');
    expect(persisted.first.isGroup, isTrue);
    expect(persisted.first.name, 'Recovered Group');
    expect(persisted.first.ownerPeerId, 'owner-peer');
    expect(
      persisted.first.memberPeerIds,
      containsAll(<String>['owner-peer', 'sender-peer']),
    );
    expect(appended.single.peerId, 'group:lost');
    expect(appended.single.text, 'hello');
  });

  test('group secure restores owner tombstone before decrypting', () async {
    final service = ChatInboundService(
      facade: _FakeNodeFacade(),
      settingsBox: _FakeStorageBox(),
      avatarService: _FakeAvatarService(),
      accessControl: _allowAllAccessControl(storage),
      inboundClassifier: ChatInboundClassifier(
        decodeGroupInvitePayload: (_) => null,
        decodeGroupKeyPayload: (_) => null,
        decodeGroupDeletePayload: (_) => null,
        decodeGroupChatDeletePayload: (_) => null,
        decodeGroupMembersPayload: (_) => null,
        decodeGroupMessagePayload: (_) => null,
        decodeGroupSecurePayloadRaw: (_) => null,
        decodeGroupKeyRequestPayload: (_) => null,
        decodeDirectBlobRefPayload: (_) => null,
        decodeGroupBlobRefPayload: (_) => null,
        decodeMessageReceiptPayload: (_) => null,
        decodeAccountPairRequestPayload: (_) => null,
        decodeAccountPairApprovalPayload: (_) => null,
        decodeAccountPairRejectionPayload: (_) => null,
        decodeAccountMembershipUpdatePayload: (_) => null,
      ),
    );
    final chats = <String, Chat>{};
    var restored = false;
    final persisted = <Chat>[];
    final appended = <Message>[];

    await service.handleIncomingGroupSecureMessage(
      ChatMessage(
        id: 'secure-1',
        peerId: 'group:lost',
        senderPeerId: 'sender-peer',
        text: 'secure-payload',
      ),
      payload: const IncomingGroupSecurePayload(
        groupId: 'group:lost',
        raw: <String, dynamic>{},
      ),
      normalizePayload: (_) => null,
      isGroupDeleted: (_) => !restored,
      shouldRestoreDeletedGroup: (_) => true,
      restoreDeletedGroup: (_) async {
        restored = true;
      },
      decryptGroupText: (_) async => 'restored text',
      handleGroupSecureDecryptFailed:
          ({
            required groupId,
            required sourcePeerId,
            required messageId,
          }) async {
            fail('decrypt recovery should not run after successful decrypt');
          },
      chats: chats,
      localPeerId: 'owner-peer',
      decodeIncomingBlobRefPayload: (_) => null,
      handleIncomingGroupBlobRef:
          (
            _, {
            required groupId,
            required groupChat,
            required existingGroupChat,
            required blobRef,
            required notificationSenderLabel,
          }) async {},
      persistChatSummary: (chat) async {
        persisted.add(Chat.fromJson(Map<String, dynamic>.from(chat.toJson())));
      },
      appendMessage: (peerId, message) async => appended.add(message),
      notifyMessageUpdated: (_) {},
      notifyNewMessage: (_) {},
      unreadMessagesCount: () => 1,
      showMessageNotification:
          ({
            required fromPeerId,
            required message,
            required badgeCount,
          }) async {},
    );

    expect(restored, isTrue);
    expect(chats['group:lost'], isNotNull);
    expect(persisted.single.peerId, 'group:lost');
    expect(persisted.single.isGroup, isTrue);
    expect(appended.single.text, 'restored text');
  });

  test('group secure decrypt failure asks owner recovery callback', () async {
    final service = ChatInboundService(
      facade: _FakeNodeFacade(),
      settingsBox: _FakeStorageBox(),
      avatarService: _FakeAvatarService(),
      accessControl: _allowAllAccessControl(storage),
      inboundClassifier: ChatInboundClassifier(
        decodeGroupInvitePayload: (_) => null,
        decodeGroupKeyPayload: (_) => null,
        decodeGroupDeletePayload: (_) => null,
        decodeGroupChatDeletePayload: (_) => null,
        decodeGroupMembersPayload: (_) => null,
        decodeGroupMessagePayload: (_) => null,
        decodeGroupSecurePayloadRaw: (_) => null,
        decodeGroupKeyRequestPayload: (_) => null,
        decodeDirectBlobRefPayload: (_) => null,
        decodeGroupBlobRefPayload: (_) => null,
        decodeMessageReceiptPayload: (_) => null,
        decodeAccountPairRequestPayload: (_) => null,
        decodeAccountPairApprovalPayload: (_) => null,
        decodeAccountPairRejectionPayload: (_) => null,
        decodeAccountMembershipUpdatePayload: (_) => null,
      ),
    );
    ({String groupId, String sourcePeerId, String messageId})? recovery;

    await expectLater(
      service.handleIncomingGroupSecureMessage(
        ChatMessage(
          id: 'secure-2',
          peerId: 'group:lost',
          senderPeerId: 'sender-peer',
          text: 'secure-payload',
        ),
        payload: const IncomingGroupSecurePayload(
          groupId: 'group:lost',
          raw: <String, dynamic>{},
        ),
        normalizePayload: (_) => null,
        isGroupDeleted: (_) => false,
        shouldRestoreDeletedGroup: (_) => false,
        restoreDeletedGroup: (_) async {},
        decryptGroupText: (_) async => null,
        handleGroupSecureDecryptFailed:
            ({
              required groupId,
              required sourcePeerId,
              required messageId,
            }) async {
              recovery = (
                groupId: groupId,
                sourcePeerId: sourcePeerId,
                messageId: messageId,
              );
            },
        chats: <String, Chat>{},
        localPeerId: 'owner-peer',
        decodeIncomingBlobRefPayload: (_) => null,
        handleIncomingGroupBlobRef:
            (
              _, {
              required groupId,
              required groupChat,
              required existingGroupChat,
              required blobRef,
              required notificationSenderLabel,
            }) async {},
        persistChatSummary: (_) async {},
        appendMessage: (_, _) async {},
        notifyMessageUpdated: (_) {},
        notifyNewMessage: (_) {},
        unreadMessagesCount: () => 0,
        showMessageNotification:
            ({
              required fromPeerId,
              required message,
              required badgeCount,
            }) async {},
      ),
      throwsA(isA<GroupInboundDeferredException>()),
    );

    expect(recovery?.groupId, 'group:lost');
    expect(recovery?.sourcePeerId, 'sender-peer');
    expect(recovery?.messageId, 'secure-2');
  });
}
