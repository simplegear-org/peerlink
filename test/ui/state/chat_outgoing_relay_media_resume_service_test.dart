import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_outgoing_relay_media_resume_service.dart';

class _FakeStorageBox extends Fake implements SecureStorageBox {
  final Map<String, dynamic> _values = <String, dynamic>{};

  @override
  dynamic get(String key) => _values[key];

  @override
  Future<void> put(String key, dynamic value) async {
    _values[key] = value;
  }
}

class _FakeNodeFacade extends Fake implements NodeFacade {
  ChatSendReceipt receipt = ChatSendReceipt.empty;
  final List<String> groupPushMessageIds = <String>[];

  @override
  String get peerId => 'owner-peer';

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
    return receipt;
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
}

void main() {
  late _FakeNodeFacade facade;
  late _FakeStorageBox storage;
  late ChatOutgoingRelayMediaResumeService service;
  late Chat chat;
  late Message message;

  setUp(() async {
    facade = _FakeNodeFacade();
    storage = _FakeStorageBox();
    service = ChatOutgoingRelayMediaResumeService(
      facade: facade,
      settingsBox: storage,
      outboundCodec: ChatOutboundCodec(
        localPeerIdProvider: () => facade.peerId,
      ),
    );
    message = Message(
      id: 'msg-1',
      peerId: 'group:1',
      text: 'photo.jpg',
      incoming: false,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1),
      kind: MessageKind.file,
      fileName: 'photo.jpg',
      mimeType: 'image/jpeg',
      status: MessageStatus.failed,
    );
    chat = Chat(
      peerId: 'group:1',
      name: 'Group',
      isGroup: true,
      memberPeerIds: const <String>['owner-peer', 'peer-a'],
      ownerPeerId: 'owner-peer',
      messagesLoaded: true,
    );
    chat.messages = <Message>[message];
    await service.remember(
      const OutgoingRelayMediaState(
        peerId: 'group:1',
        messageId: 'msg-1',
        targetKind: OutgoingRelayMediaTargetKind.group,
        blobId: 'blob:msg-1',
        payloadText: 'payload',
        recipients: <String>['peer-a'],
        localFilePath: null,
        replyToMessageId: null,
        replyToSenderPeerId: null,
        replyToSenderLabel: null,
        replyToTextPreview: null,
        replyToKind: null,
      ),
    );
  });

  test(
    'does not mark resumed group media sent when relay store is not confirmed',
    () async {
      await service.resumePending(
        reason: 'test',
        ensureChatLoaded: (_) async {},
        findChat: (_) => chat,
        updateFileProgress:
            (
              _,
              _, {
              required sentBytes,
              required totalBytes,
              required statusText,
            }) async {},
        replaceMessage: (_, _, transform) async {
          message = transform(message);
          chat.messages[0] = message;
        },
        clearProgressUpdate: (_, _) {},
        setStatus: (_, _, {error}) {},
        notifyMessageUpdated: (_) {},
        logQueue: (_) {},
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(message.status, MessageStatus.failed);
      expect(
        storage.get(ChatOutgoingRelayMediaResumeService.storageKey),
        isNotEmpty,
      );
      expect(facade.groupPushMessageIds, isEmpty);
    },
  );

  test('sends group push after confirmed resumed group media store', () async {
    facade.receipt = const ChatSendReceipt(
      sent: true,
      relayServers: <String>['https://relay.test'],
    );

    await service.resumePending(
      reason: 'test',
      ensureChatLoaded: (_) async {},
      findChat: (_) => chat,
      updateFileProgress:
          (
            _,
            _, {
            required sentBytes,
            required totalBytes,
            required statusText,
          }) async {},
      replaceMessage: (_, _, transform) async {
        message = transform(message);
        chat.messages[0] = message;
      },
      clearProgressUpdate: (_, _) {},
      setStatus: (_, _, {error}) {},
      notifyMessageUpdated: (_) {},
      logQueue: (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(message.status, MessageStatus.sent);
    expect(
      storage.get(ChatOutgoingRelayMediaResumeService.storageKey),
      isEmpty,
    );
    expect(facade.groupPushMessageIds, <String>['msg-1']);
  });
}
