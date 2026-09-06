import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/core/security/group_key_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_group_flow_service.dart';
import 'package:peerlink/features/chat/application/chat_group_outbound_handler.dart';
import 'package:peerlink/features/chat/application/chat_inbound_classifier.dart';
import 'package:peerlink/features/chat/application/chat_media_outbound_service.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';

class _MemoryGroupKeyStore implements GroupKeyStore {
  final Map<String, dynamic> data = <String, dynamic>{};

  @override
  Iterable<String> get keys => data.keys;

  @override
  dynamic get(String key) => data[key];

  @override
  Future<void> put(String key, dynamic value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}

class _FakeNodeFacade extends Fake implements ChatRuntimeApi {
  final List<({String peerId, String kind})> controls = [];
  final List<({String peerId, Map<String, dynamic>? data})> pushes = [];
  final List<String> groupPushMessageIds = [];
  final List<
    ({ChatPayloadTargetKind targetKind, String targetId, String messageId})
  >
  discardedPendingPayloads = [];
  final List<({String groupId, String ownerPeerId, List<String> memberPeerIds})>
  groupMemberUpdates = [];
  ChatSendReceipt sendPayloadReceipt = ChatSendReceipt.empty;
  ChatSendReceipt? groupSendPayloadReceipt;
  ChatSendReceipt? directSendPayloadReceipt;

  @override
  String get peerId => 'owner-peer';

  @override
  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) async {
    controls.add((peerId: peerId, kind: kind));
  }

  @override
  Future<void> sendDirectPushEvent({
    required String directPeerId,
    required String messageId,
    List<String>? relayServers,
    String? notificationType,
    String? relayServerId,
    String? relayScopeKind,
    String? relayBlobId,
    String? relayMessageId,
    Map<String, dynamic>? data,
  }) async {
    pushes.add((peerId: directPeerId, data: data));
  }

  @override
  Future<String> uploadBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) async {
    return blobId ?? 'blob:test';
  }

  @override
  Future<ChatSendReceipt> sendPayload(
    String targetId, {
    ChatPayloadTargetKind targetKind = ChatPayloadTargetKind.direct,
    List<String>? recipients,
    required String text,
    String kind = 'text',
    String? messageId,
    String? fileName,
    String? mimeType,
    String? transferId,
    int? totalBytes,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
  }) async {
    if (targetKind == ChatPayloadTargetKind.group) {
      return groupSendPayloadReceipt ?? sendPayloadReceipt;
    }
    if (targetKind == ChatPayloadTargetKind.direct) {
      return directSendPayloadReceipt ?? sendPayloadReceipt;
    }
    return sendPayloadReceipt;
  }

  @override
  Future<void> updateRelayGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  }) async {
    groupMemberUpdates.add((
      groupId: groupId,
      ownerPeerId: ownerPeerId,
      memberPeerIds: memberPeerIds,
    ));
  }

  @override
  Future<void> sendGroupPushEvent({
    required String groupId,
    required String messageId,
    required List<String> recipientUserIds,
    List<String>? relayServers,
    String? notificationType,
    String? relayServerId,
    String? relayScopeKind,
    String? relayBlobId,
    String? relayMessageId,
  }) async {
    groupPushMessageIds.add(messageId);
  }

  @override
  Future<void> discardPendingPayload({
    required ChatPayloadTargetKind targetKind,
    required String targetId,
    required String messageId,
  }) async {
    discardedPendingPayloads.add((
      targetKind: targetKind,
      targetId: targetId,
      messageId: messageId,
    ));
  }
}

void main() {
  late _FakeNodeFacade facade;
  late ChatGroupFlowService service;

  setUp(() {
    facade = _FakeNodeFacade();
    service = ChatGroupFlowService(
      facade: facade,
      groupKeyService: GroupKeyService(_MemoryGroupKeyStore()),
      outboundCodec: ChatOutboundCodec(
        localPeerIdProvider: () => facade.peerId,
      ),
      nextLocalMessageId: () => 'm1',
    );
  });

  Chat groupChat() => Chat(
    peerId: 'group:1',
    name: 'Group',
    isGroup: true,
    memberPeerIds: const <String>['owner-peer', 'peer-a', 'peer-b'],
    ownerPeerId: 'owner-peer',
  );

  test('sendGroupKeyToRecipients wakes recipients with direct push', () async {
    await service.sendGroupKeyToRecipients(
      groupChat(),
      const <String>['peer-a', 'peer-b'],
      groupKeyBase64: base64Encode(List<int>.filled(32, 1)),
      keyVersion: 2,
    );

    expect(facade.controls.map((item) => item.kind), ['groupKey', 'groupKey']);
    expect(facade.pushes.map((item) => item.peerId), ['peer-a', 'peer-b']);
    expect(facade.pushes.map((item) => item.data?['type']), [
      'direct_update',
      'direct_update',
    ]);
    expect(facade.pushes.map((item) => item.data?['groupId']), [
      'group:1',
      'group:1',
    ]);
  });

  test('group key request payload is classified for owner recovery', () {
    final codec = ChatOutboundCodec(localPeerIdProvider: () => 'peer-a');
    final classifier = ChatInboundClassifier(
      decodeGroupInvitePayload: codec.decodeGroupInvitePayload,
      decodeGroupKeyPayload: codec.decodeGroupKeyPayload,
      decodeGroupDeletePayload: codec.decodeGroupDeletePayload,
      decodeGroupChatDeletePayload: codec.decodeGroupChatDeletePayload,
      decodeGroupMembersPayload: codec.decodeGroupMembersPayload,
      decodeGroupMessagePayload: codec.decodeGroupMessagePayload,
      decodeGroupSecurePayloadRaw: codec.decodeGroupSecurePayloadRaw,
      decodeGroupKeyRequestPayload: codec.decodeGroupKeyRequestPayload,
      decodeDirectBlobRefPayload: codec.decodeDirectBlobRefPayload,
      decodeGroupBlobRefPayload: codec.decodeGroupBlobRefPayload,
      decodeMessageReceiptPayload: codec.decodeMessageReceiptPayload,
      decodeAccountPairRequestPayload: (_) => null,
      decodeAccountPairApprovalPayload: (_) => null,
      decodeAccountPairRejectionPayload: (_) => null,
      decodeAccountMembershipUpdatePayload: (_) => null,
    );

    final text = codec.encodeGroupKeyRequestPayload(
      groupId: 'group:1',
      ownerPeerId: 'owner-peer',
      failedMessageId: 'msg-1',
    );
    final dispatch = classifier.classifyIncomingMessage(
      ChatMessage(id: 'request-1', peerId: 'peer-a', text: text),
    );

    expect(dispatch, isA<IncomingGroupKeyRequestDispatch>());
    final payload = (dispatch as IncomingGroupKeyRequestDispatch).payload;
    expect(payload.groupId, 'group:1');
    expect(payload.ownerPeerId, 'owner-peer');
    expect(payload.requesterPeerId, 'peer-a');
    expect(payload.failedMessageId, 'msg-1');
  });

  test(
    'group outbound does not push when relay store is not confirmed',
    () async {
      final handler = ChatGroupOutboundHandler(
        facade: facade,
        outboundCodec: ChatOutboundCodec(
          localPeerIdProvider: () => facade.peerId,
        ),
        mediaOutboundService: ChatMediaOutboundService(
          facade: facade,
          relayMediaTransfer: const RelayMediaTransferService(),
        ),
      );
      MessageStatus? status;
      ChatConnectionStatus? connectionStatus;

      await handler.sendMessage(
        groupChat(),
        Message(
          id: 'msg-1',
          peerId: 'group:1',
          text: 'hello',
          incoming: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1),
          status: MessageStatus.sending,
        ),
        persistChatSummary: (_) async {},
        ensureGroupKey: (_) async => 'key',
        encryptGroupBytes: ({required groupId, required plainBytes}) async =>
            plainBytes,
        encryptGroupText: ({required groupId, required plainText}) async =>
            plainText,
        collectGroupRecipients: (_) => const <String>['peer-a'],
        updateMessageStatusById: (_, _, nextStatus) async {
          status = nextStatus;
        },
        setStatus: (_, nextStatus, {error}) {
          connectionStatus = nextStatus;
        },
      );

      expect(status, MessageStatus.failed);
      expect(connectionStatus, ChatConnectionStatus.error);
      expect(facade.groupPushMessageIds, isEmpty);
    },
  );

  test('group outbound wakes fallback direct recipients', () async {
    facade.groupSendPayloadReceipt = ChatSendReceipt.empty;
    facade.directSendPayloadReceipt = const ChatSendReceipt(
      sent: true,
      relayServers: <String>['https://relay.test'],
    );
    final handler = ChatGroupOutboundHandler(
      facade: facade,
      outboundCodec: ChatOutboundCodec(
        localPeerIdProvider: () => facade.peerId,
      ),
      mediaOutboundService: ChatMediaOutboundService(
        facade: facade,
        relayMediaTransfer: const RelayMediaTransferService(),
      ),
    );
    MessageStatus? status;

    await handler.sendMessage(
      groupChat(),
      Message(
        id: 'msg-fallback',
        peerId: 'group:1',
        text: 'hello',
        incoming: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        status: MessageStatus.sending,
      ),
      persistChatSummary: (_) async {},
      ensureGroupKey: (_) async => 'key',
      encryptGroupBytes: ({required groupId, required plainBytes}) async =>
          plainBytes,
      encryptGroupText: ({required groupId, required plainText}) async =>
          plainText,
      collectGroupRecipients: (_) => const <String>['peer-a', 'peer-b'],
      updateMessageStatusById: (_, _, nextStatus) async {
        status = nextStatus;
      },
      setStatus: (_, _, {error}) {},
    );

    expect(status, MessageStatus.sent);
    expect(facade.groupPushMessageIds, isEmpty);
    expect(facade.pushes.map((item) => item.peerId), ['peer-a', 'peer-b']);
    expect(facade.pushes.map((item) => item.data?['groupId']), [
      'group:1',
      'group:1',
    ]);
  });

  test('group media outbound wakes fallback direct recipients', () async {
    facade.groupSendPayloadReceipt = ChatSendReceipt.empty;
    facade.directSendPayloadReceipt = const ChatSendReceipt(
      sent: true,
      relayServers: <String>['https://relay.test'],
    );
    final handler = ChatGroupOutboundHandler(
      facade: facade,
      outboundCodec: ChatOutboundCodec(
        localPeerIdProvider: () => facade.peerId,
      ),
      mediaOutboundService: ChatMediaOutboundService(
        facade: facade,
        relayMediaTransfer: const RelayMediaTransferService(),
      ),
    );
    MessageStatus? status;

    await handler.sendFile(
      groupChat(),
      messageId: 'media-fallback',
      fileName: 'photo.jpg',
      fileBytes: Uint8List.fromList(<int>[1, 2, 3]),
      fileSizeBytes: 3,
      mimeType: 'image/jpeg',
      persistChatSummary: (_) async {},
      collectGroupRecipients: (_) => const <String>['peer-a', 'peer-b'],
      ensureGroupKey: (_) async => 'key',
      encryptGroupBytes: ({required groupId, required plainBytes}) async =>
          plainBytes,
      encryptGroupText: ({required groupId, required plainText}) async =>
          plainText,
      replySenderLabel: (_, _) => null,
      replyTextPreview: (_) => null,
      replyKind: (_) => null,
      updateFileProgress:
          (
            _,
            _, {
            required sentBytes,
            required totalBytes,
            required statusText,
          }) async {},
      rememberOutgoingRelayMediaState: (_) async {},
      forgetOutgoingRelayMediaState: (_, _) async {},
      replaceMessage: (_, _, transform) async {
        final current = Message(
          id: 'media-fallback',
          peerId: 'group:1',
          text: 'photo.jpg',
          incoming: false,
          timestamp: DateTime.fromMillisecondsSinceEpoch(1),
          kind: MessageKind.file,
          status: MessageStatus.sending,
        );
        status = transform(current).status;
      },
      clearProgressUpdate: (_, _) {},
      saveMediaFile:
          ({
            required peerId,
            required messageId,
            required fileName,
            required sourcePath,
          }) async {
            return sourcePath;
          },
      saveMediaBytes:
          ({
            required peerId,
            required messageId,
            required fileName,
            required bytes,
          }) async {
            return '/tmp/$fileName';
          },
      ensureThumbnail: (_) async => null,
      transferStatusForError: (_, {required fallback}) => fallback,
      setStatus: (_, _, {error}) {},
      notifyMessageUpdated: (_) {},
    );

    expect(status, MessageStatus.sent);
    expect(facade.groupPushMessageIds, isEmpty);
    expect(
      facade.discardedPendingPayloads.single.targetKind,
      ChatPayloadTargetKind.group,
    );
    expect(facade.discardedPendingPayloads.single.targetId, 'group:1');
    expect(facade.discardedPendingPayloads.single.messageId, 'media-fallback');
    expect(facade.pushes.map((item) => item.peerId), ['peer-a', 'peer-b']);
    expect(facade.pushes.map((item) => item.data?['groupId']), [
      'group:1',
      'group:1',
    ]);
  });

  test('owner syncs relay group membership before outbound message', () async {
    facade.sendPayloadReceipt = const ChatSendReceipt(
      sent: true,
      relayServers: <String>['https://relay.test'],
    );
    final handler = ChatGroupOutboundHandler(
      facade: facade,
      outboundCodec: ChatOutboundCodec(
        localPeerIdProvider: () => facade.peerId,
      ),
      mediaOutboundService: ChatMediaOutboundService(
        facade: facade,
        relayMediaTransfer: const RelayMediaTransferService(),
      ),
    );

    await handler.sendMessage(
      groupChat(),
      Message(
        id: 'msg-2',
        peerId: 'group:1',
        text: 'hello',
        incoming: false,
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        status: MessageStatus.sending,
      ),
      persistChatSummary: (_) async {},
      ensureGroupKey: (_) async => 'key',
      encryptGroupBytes: ({required groupId, required plainBytes}) async =>
          plainBytes,
      encryptGroupText: ({required groupId, required plainText}) async =>
          plainText,
      collectGroupRecipients: (_) => const <String>['peer-a', 'peer-b'],
      updateMessageStatusById: (_, _, _) async {},
      setStatus: (_, _, {error}) {},
    );

    expect(facade.groupMemberUpdates, hasLength(1));
    expect(facade.groupMemberUpdates.single.groupId, 'group:1');
    expect(facade.groupMemberUpdates.single.ownerPeerId, 'owner-peer');
    expect(facade.groupMemberUpdates.single.memberPeerIds, [
      'owner-peer',
      'peer-a',
      'peer-b',
    ]);
    expect(facade.groupPushMessageIds, ['msg-2']);
  });

  test('broadcastGroupMembersUpdate wakes recipients on add', () async {
    await service.broadcastGroupMembersUpdate(
      groupChat: groupChat(),
      recipients: const <String>['peer-a', 'peer-b'],
      action: 'add',
      changedPeerIds: const <String>['peer-b'],
    );

    expect(facade.controls.map((item) => item.kind), [
      'groupMembers',
      'groupMembers',
    ]);
    expect(facade.pushes.map((item) => item.peerId), ['peer-a', 'peer-b']);
    expect(facade.pushes.map((item) => item.data?['type']), [
      'group_members_update',
      'group_members_update',
    ]);
  });

  test('message receipt payload is classified', () {
    final codec = ChatOutboundCodec(localPeerIdProvider: () => 'peer-b');
    final classifier = ChatInboundClassifier(
      decodeGroupInvitePayload: codec.decodeGroupInvitePayload,
      decodeGroupKeyPayload: codec.decodeGroupKeyPayload,
      decodeGroupDeletePayload: codec.decodeGroupDeletePayload,
      decodeGroupChatDeletePayload: codec.decodeGroupChatDeletePayload,
      decodeGroupMembersPayload: codec.decodeGroupMembersPayload,
      decodeGroupMessagePayload: codec.decodeGroupMessagePayload,
      decodeGroupSecurePayloadRaw: codec.decodeGroupSecurePayloadRaw,
      decodeGroupKeyRequestPayload: codec.decodeGroupKeyRequestPayload,
      decodeDirectBlobRefPayload: codec.decodeDirectBlobRefPayload,
      decodeGroupBlobRefPayload: codec.decodeGroupBlobRefPayload,
      decodeMessageReceiptPayload: codec.decodeMessageReceiptPayload,
      decodeAccountPairRequestPayload: (_) => null,
      decodeAccountPairApprovalPayload: (_) => null,
      decodeAccountPairRejectionPayload: (_) => null,
      decodeAccountMembershipUpdatePayload: (_) => null,
    );

    final payload = codec.encodeMessageReceiptPayload(
      chatId: 'group:1',
      isGroup: true,
      messageIds: const <String>['m1'],
      status: MessageReceiptStatus.read.name,
      atMs: 42,
    );

    final dispatch = classifier.classifyIncomingMessage(
      ChatMessage(id: 'r1', peerId: 'peer-a', text: payload, kind: 'receipt'),
    );

    expect(dispatch, isA<IncomingMessageReceiptDispatch>());
    dispatch as IncomingMessageReceiptDispatch;
    expect(dispatch.payload.chatId, 'group:1');
    expect(dispatch.payload.isGroup, isTrue);
    expect(dispatch.payload.messageIds, ['m1']);
    expect(dispatch.payload.status, MessageReceiptStatus.read.name);
    expect(dispatch.payload.senderPeerId, 'peer-b');
  });
}
