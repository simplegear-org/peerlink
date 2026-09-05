import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/ui/models/contact.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/ui/state/chat_forward_service.dart';

void main() {
  group('ChatForwardService', () {
    const service = ChatForwardService();

    test('targets merge chats and contacts sorted by latest message', () {
      final older = DateTime(2026, 1, 1, 10);
      final newer = DateTime(2026, 1, 2, 10);
      final chats = [
        Chat(peerId: 'peer-old', name: 'Old')
          ..messages.add(
            Message(
              id: 'm1',
              peerId: 'peer-old',
              text: 'old',
              incoming: true,
              timestamp: older,
            ),
          ),
        Chat(peerId: 'group:1', name: 'Group', isGroup: true)
          ..messages.add(
            Message(
              id: 'm2',
              peerId: 'group:1',
              text: 'new',
              incoming: true,
              timestamp: newer,
            ),
          ),
      ];
      final contacts = [
        Contact(peerId: 'peer-old', name: 'Old Contact'),
        Contact(peerId: 'peer-z', name: 'Zulu'),
        Contact(peerId: 'peer-a', name: 'Alpha'),
      ];

      final targets = service.targets(chats: chats, contacts: contacts);

      expect(targets.map((target) => target.peerId), [
        'group:1',
        'peer-old',
        'peer-a',
        'peer-z',
      ]);
      expect(targets.first.isGroup, isTrue);
      expect(targets[1].name, 'Old');
    });

    test('forward sends text copy to selected target', () async {
      String? sentPeerId;
      String? sentText;

      await service.forward(
        message: Message(
          id: 'm1',
          peerId: 'source',
          text: 'hello',
          incoming: true,
          timestamp: DateTime(2026),
        ),
        target: const ChatForwardTarget(
          peerId: 'target',
          name: 'Target',
          isGroup: false,
          lastMessageAt: null,
        ),
        sendMessage: (peerId, text) async {
          sentPeerId = peerId;
          sentText = text;
        },
        sendFile: _unexpectedSendFile,
        ensureLocalMedia: (_) async => null,
      );

      expect(sentPeerId, 'target');
      expect(sentText, 'hello');
    });

    test('forward sends file from restored local path', () async {
      final dir = await Directory.systemTemp.createTemp('peerlink_forward_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });
      final file = File('${dir.path}/photo.jpg');
      await file.writeAsBytes([1, 2, 3]);

      Uint8List? sentBytes;
      String? sentPath;
      String? sentFileName;
      int? sentFileSizeBytes;

      await service.forward(
        message: Message(
          id: 'm1',
          peerId: 'source',
          text: 'photo.jpg',
          incoming: true,
          timestamp: DateTime(2026),
          kind: MessageKind.file,
          fileName: 'photo.jpg',
          mimeType: 'image/jpeg',
        ),
        target: const ChatForwardTarget(
          peerId: 'target',
          name: 'Target',
          isGroup: false,
          lastMessageAt: null,
        ),
        sendMessage: _unexpectedSendMessage,
        sendFile:
            (
              peerId, {
              required fileName,
              fileBytes,
              filePath,
              fileSizeBytes,
              mimeType,
            }) async {
              sentBytes = fileBytes;
              sentPath = filePath;
              sentFileName = fileName;
              sentFileSizeBytes = fileSizeBytes;
            },
        ensureLocalMedia: (_) async => file.path,
      );

      expect(sentBytes, [1, 2, 3]);
      expect(sentPath, isNull);
      expect(sentFileName, 'photo.jpg');
      expect(sentFileSizeBytes, 3);
    });
  });
}

Future<void> _unexpectedSendMessage(String peerId, String text) async {
  fail('sendMessage should not be called');
}

Future<void> _unexpectedSendFile(
  String peerId, {
  required String fileName,
  Uint8List? fileBytes,
  String? filePath,
  int? fileSizeBytes,
  String? mimeType,
}) async {
  fail('sendFile should not be called');
}
