import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/contacts/domain/contact.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/moderation/application/peer_access_control_service.dart';
import 'package:peerlink/ui/state/contacts_controller.dart';

void main() {
  late Directory root;
  late StorageService storage;
  late ContactsRepository repository;
  late ContactsController controller;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peerlink-invite-contacts-');
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    repository = ContactsRepository(storage: storage);
    controller = ContactsController(
      repository: repository,
      accessControl: PeerAccessControlService(
        settingsBox: storage.getSettings(),
        contactsRepository: repository,
      ),
    );
    controller.loadIntoMemory();
    addTearDown(() async {
      await StorageService.resetForTesting();
      await root.delete(recursive: true);
    });
  });

  test(
    'uses Peer ID fallback, then upgrades it to invite username once',
    () async {
      expect(await controller.upsertInviteContact(peerId: 'peer-a'), isTrue);
      expect(controller.contacts, hasLength(1));
      expect(controller.contacts.single.name, 'peer-a');
      expect(
        controller.contacts.single.displayNameSource,
        ContactDisplayNameSource.peerIdFallback,
      );

      expect(
        await controller.upsertInviteContact(
          peerId: 'peer-a',
          username: 'Alice',
        ),
        isTrue,
      );
      expect(controller.contacts, hasLength(1));
      expect(controller.contacts.single.name, 'Alice');
      expect(
        controller.contacts.single.displayNameSource,
        ContactDisplayNameSource.inviteUsername,
      );
      expect(
        await controller.upsertInviteContact(
          peerId: 'peer-a',
          username: 'Alice',
        ),
        isFalse,
      );
    },
  );

  test(
    'updates invite-derived name but never overwrites manual name',
    () async {
      await controller.upsertInviteContact(peerId: 'peer-a', username: 'Alice');
      expect(
        await controller.upsertInviteContact(
          peerId: 'peer-a',
          username: 'Alice 2',
        ),
        isTrue,
      );
      expect(controller.contacts.single.name, 'Alice 2');

      await controller.renameContact('peer-a', 'My Alice');
      expect(
        await controller.upsertInviteContact(
          peerId: 'peer-a',
          username: 'Remote',
        ),
        isFalse,
      );
      expect(controller.contacts.single.name, 'My Alice');
      expect(
        controller.contacts.single.displayNameSource,
        ContactDisplayNameSource.manual,
      );
    },
  );

  test('persists invite name provenance across a restart', () async {
    await controller.upsertInviteContact(peerId: 'peer-a', username: 'Alice');

    final restored = ContactsController(
      repository: repository,
      accessControl: PeerAccessControlService(
        settingsBox: storage.getSettings(),
        contactsRepository: repository,
      ),
    )..loadIntoMemory();
    expect(restored.contacts.single.name, 'Alice');
    expect(
      restored.contacts.single.displayNameSource,
      ContactDisplayNameSource.inviteUsername,
    );
  });

  test('legacy Peer ID name can later receive a remote username', () async {
    await controller.addOrUpdateContact(
      Contact(
        peerId: 'peer-a',
        name: 'peer-a',
        displayNameSource: ContactDisplayNameSource.manual,
      ),
    );

    expect(
      await controller.applyRemoteUsername(peerId: 'peer-a', username: 'Alice'),
      isTrue,
    );
    expect(controller.contacts.single.name, 'Alice');
    expect(
      controller.contacts.single.displayNameSource,
      ContactDisplayNameSource.inviteUsername,
    );
  });
}
