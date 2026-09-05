import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/ui/models/contact.dart';

void main() {
  late StorageService storage;
  late PeerAccessControlService service;

  setUp(() async {
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(
      rootDirectory: Directory.systemTemp.createTempSync(
        'peerlink-access-test-',
      ),
    );
    service = PeerAccessControlService.forStorage(storage);
  });

  test('contacts-only is enabled by default', () {
    expect(service.allowMessagesOnlyFromContacts, isTrue);
    expect(
      service.evaluateIncoming(
        peerId: 'unknown-peer',
        type: IncomingInteractionType.directMessage,
      ),
      IncomingInteractionDecision.contactsOnly,
    );
  });

  test('contact is allowed when contacts-only is enabled', () async {
    await ContactsRepository(
      storage: storage,
    ).save(Contact(peerId: 'known-peer', name: 'Known'));

    expect(
      service.evaluateIncoming(
        peerId: 'known-peer',
        type: IncomingInteractionType.directMessage,
      ),
      IncomingInteractionDecision.allow,
    );
  });

  test('blocked peer wins over contact allowlist', () async {
    await ContactsRepository(
      storage: storage,
    ).save(Contact(peerId: 'bad-peer', name: 'Bad'));
    await service.blockPeer('bad-peer', reason: 'spam');

    expect(service.isBlocked('bad-peer'), isTrue);
    expect(
      service.evaluateIncoming(
        peerId: 'bad-peer',
        type: IncomingInteractionType.call,
      ),
      IncomingInteractionDecision.blockedPeer,
    );

    await service.unblockPeer('bad-peer');
    expect(service.isBlocked('bad-peer'), isFalse);
  });

  test('unblock restores incoming and outgoing access', () async {
    await ContactsRepository(
      storage: storage,
    ).save(Contact(peerId: 'peer-a', name: 'Peer A'));
    await service.blockPeer('peer-a');

    await service.unblockPeer('peer-a');

    expect(
      service.evaluateIncoming(
        peerId: 'peer-a',
        type: IncomingInteractionType.directMessage,
      ),
      IncomingInteractionDecision.allow,
    );
    expect(
      service.evaluateOutgoing(
        peerId: 'peer-a',
        type: IncomingInteractionType.call,
      ),
      IncomingInteractionDecision.allow,
    );
  });

  test('restart keeps blacklist and contacts-only setting', () async {
    await service.setAllowMessagesOnlyFromContacts(false);
    await service.blockPeer('bad-peer', reason: 'spam');

    final reloaded = PeerAccessControlService.forStorage(storage);

    expect(reloaded.allowMessagesOnlyFromContacts, isFalse);
    expect(reloaded.isBlocked('bad-peer'), isTrue);
    expect(reloaded.blockedPeers().single.reason, 'spam');
    expect(
      reloaded.evaluateIncoming(
        peerId: 'bad-peer',
        type: IncomingInteractionType.directMessage,
      ),
      IncomingInteractionDecision.blockedPeer,
    );
  });

  test('outgoing access only blocks explicitly blocked peers', () async {
    expect(
      service.evaluateOutgoing(
        peerId: 'unknown-peer',
        type: IncomingInteractionType.call,
      ),
      IncomingInteractionDecision.allow,
    );

    await service.blockPeer('bad-peer');

    expect(
      service.evaluateOutgoing(
        peerId: 'bad-peer',
        type: IncomingInteractionType.call,
      ),
      IncomingInteractionDecision.blockedPeer,
    );
  });
}
