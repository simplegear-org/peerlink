import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_control_reliable_payload.dart';
import 'package:peerlink/core/calls/call_control_transport.dart';
import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/node/reliable_call_control_adapter.dart';
import 'package:peerlink/core/relay/relay_models.dart';

class _FakeChatService implements ChatService {
  ChatServiceControlHandler? controlHandler;
  final sentControlMessages = <({String peerId, String kind, String text})>[];

  @override
  void setControlHandler(ChatServiceControlHandler? handler) {
    controlHandler = handler;
  }

  @override
  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
    bool forcePlain = false,
  }) async {
    sentControlMessages.add((peerId: peerId, kind: kind, text: text));
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
    bool forcePlain = false,
    bool emitStatusEvent = true,
  }) async => ChatSendReceipt.empty;

  @override
  Future<Uint8List> encryptDirectBytes(String peerId, Uint8List plainBytes) =>
      Future<Uint8List>.value(plainBytes);

  @override
  Future<Uint8List> decryptDirectBytes(
    String peerId,
    Uint8List encryptedBytes,
  ) => Future<Uint8List>.value(encryptedBytes);

  @override
  Future<void> discardPendingPayload({
    required ChatPayloadTargetKind targetKind,
    required String targetId,
    required String messageId,
  }) async {}

  @override
  Future<void> updateGroupMembers({
    required String groupId,
    required String ownerPeerId,
    required List<String> memberPeerIds,
  }) async {}

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
  }) async => blobId ?? 'blob';

  @override
  Future<RelayBlobDownload> downloadBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) async => RelayBlobDownload.notFound(blobId);

  @override
  Future<void> sendFile(
    String peerId, {
    required String messageId,
    required String fileName,
    Uint8List? fileBytes,
    String? filePath,
    required int totalBytes,
    String? mimeType,
    String? replyToMessageId,
    String? replyToSenderPeerId,
    String? replyToSenderLabel,
    String? replyToTextPreview,
    String? replyToKind,
    required bool Function() isCancelled,
    required void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })
    onProgress,
  }) async {}

  @override
  void setServerMetadataProvider(
    Map<String, dynamic>? Function()? serverMetadataProvider,
  ) {}

  @override
  Future<void> dispose() async {}
}

void main() {
  test(
    'ReliableCallControlAdapter sends call control via chat control path',
    () async {
      final chat = _FakeChatService();
      final adapter = ReliableCallControlAdapter(
        selfPeerId: 'self',
        chat: chat,
      );

      await adapter.send('peer-a', 'payload');

      expect(chat.sentControlMessages, hasLength(1));
      expect(chat.sentControlMessages.single.peerId, 'peer-a');
      expect(chat.sentControlMessages.single.kind, 'callControl');
      expect(chat.sentControlMessages.single.text, 'payload');
    },
  );

  test(
    'ReliableCallControlAdapter dispatches only valid call-control payloads',
    () async {
      final chat = _FakeChatService();
      final adapter = ReliableCallControlAdapter(
        selfPeerId: 'self',
        chat: chat,
      );
      final received = <CallControlPayload>[];
      adapter.setIncomingHandler((payload) async {
        received.add(payload);
        return true;
      });

      final codec = CallControlReliablePayload();
      final handled = await chat.controlHandler!(
        ChatMessage(
          id: 'm1',
          peerId: 'peer-a',
          text: codec.encode(
            controlType: 'call_end',
            callId: 'call-a',
            data: codec.terminalData(callId: 'call-a'),
          ),
        ),
      );
      final ignored = await chat.controlHandler!(
        ChatMessage(id: 'm2', peerId: 'peer-a', text: 'not-call-control'),
      );

      expect(handled, isTrue);
      expect(ignored, isFalse);
      expect(received, hasLength(1));
      expect(received.single.fromPeerId, 'peer-a');
    },
  );
}
