import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/application/chat_reply_metadata_resolver.dart';
import 'package:test/test.dart';

void main() {
  late ChatReplyMetadataResolver resolver;

  setUp(() {
    resolver = ChatReplyMetadataResolver(
      contactNameFor: (peerId, {fallback}) =>
          peerId == 'known-peer' ? 'Known' : fallback ?? '',
    );
  });

  test('senderLabel resolves outgoing, contact and short peer labels', () {
    expect(resolver.senderLabel('chat', _message('m1', incoming: false)), 'Вы');
    expect(
      resolver.senderLabel(
        'chat',
        _message('m2', incoming: true, senderPeerId: 'known-peer'),
      ),
      'Known',
    );
    expect(
      resolver.senderLabel(
        'chat',
        _message('m3', incoming: true, senderPeerId: '1234567890abcdef'),
      ),
      '1234...cdef',
    );
  });

  test('textPreview resolves text and file previews', () {
    expect(resolver.textPreview(_message('m1', text: ' hello ')), 'hello');
    expect(resolver.textPreview(_message('m2', text: '')), 'Сообщение');
    expect(
      resolver.textPreview(
        _message(
          'm3',
          kind: MessageKind.file,
          fileName: 'voice.m4a',
          text: 'voice.m4a',
        ),
      ),
      'Голосовое сообщение',
    );
    expect(
      resolver.textPreview(
        _message(
          'm4',
          kind: MessageKind.file,
          fileName: 'photo.png',
          text: 'photo.png',
        ),
      ),
      'Фото',
    );
  });

  test('kind resolves persisted reply kind', () {
    expect(resolver.kind(_message('m1')), 'text');
    expect(resolver.kind(_message('m2', kind: MessageKind.file)), 'file');
    expect(resolver.kind(null), isNull);
  });
}

Message _message(
  String id, {
  String text = 'text',
  bool incoming = true,
  String? senderPeerId,
  MessageKind kind = MessageKind.text,
  String? fileName,
}) {
  return Message(
    id: id,
    peerId: 'peer',
    senderPeerId: senderPeerId,
    text: text,
    incoming: incoming,
    timestamp: DateTime(2026),
    kind: kind,
    fileName: fileName,
  );
}
