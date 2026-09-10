import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';

void main() {
  const relayServers = <String>[
    'https://sender-one.example',
    'https://sender-two.example',
  ];
  final codec = ChatOutboundCodec(localPeerIdProvider: () => 'local-peer');

  test('direct blob transfer route preserves targeted relay servers', () {
    final route = codec.parseDirectBlobTransferId(
      codec.directBlobTransferId(
        peerId: 'peer-a',
        messageId: 'message-a',
        blobId: 'blob-a',
        blobRelayServers: relayServers,
      ),
    );

    expect(route, isNotNull);
    expect(route!.blobRelayServers, relayServers);
  });

  test('group blob transfer route preserves targeted relay servers', () {
    final route = codec.parseGroupBlobTransferId(
      codec.groupBlobTransferId(
        groupId: 'group-a',
        messageId: 'message-a',
        blobId: 'blob-a',
        blobRelayServers: relayServers,
      ),
    );

    expect(route, isNotNull);
    expect(route!.blobRelayServers, relayServers);
  });

  test('legacy blob transfer routes retain an empty relay list', () {
    final route = codec.parseDirectBlobTransferId(
      'dirblob:peer-a|message-a|blob-a',
    );

    expect(route, isNotNull);
    expect(route!.blobRelayServers, isEmpty);
  });
}
