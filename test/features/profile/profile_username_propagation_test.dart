import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/contacts/domain/contact.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/moderation/application/peer_access_control_service.dart';
import 'package:peerlink/features/profile/application/profile_metadata_service.dart';
import 'package:peerlink/features/profile/application/profile_transport.dart';
import 'package:peerlink/features/profile/infrastructure/settings_profile_peer_metadata_store.dart';
import 'package:peerlink/features/profile/infrastructure/settings_peer_profile_store.dart';
import 'package:peerlink/features/profile/infrastructure/settings_profile_store.dart';
import 'package:peerlink/ui/state/contacts_controller.dart';

class _Transport implements ProfileTransport {
  _Transport(this.peerId);

  @override
  final String peerId;
  final sent = <({String peerId, String kind, String text})>[];

  @override
  Future<RelayBlobDownload> downloadBlob(String blobId) =>
      Future<RelayBlobDownload>.error(UnimplementedError());

  @override
  Future<void> sendControlMessage(
    String peerId, {
    required String kind,
    required String text,
  }) async {
    sent.add((peerId: peerId, kind: kind, text: text));
  }

  @override
  Future<String> uploadBlob({
    required RelayBlobScopeKind scopeKind,
    required String targetId,
    required String fileName,
    required String? mimeType,
    required Uint8List bytes,
    String? blobId,
  }) => Future<String>.error(UnimplementedError());
}

void main() {
  late Directory root;
  late StorageService storage;
  late ContactsController contacts;
  late _Transport transport;
  late ProfileMetadataService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peerlink-profile-name-');
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    final repository = ContactsRepository(storage: storage);
    contacts = ContactsController(
      repository: repository,
      accessControl: PeerAccessControlService(
        settingsBox: storage.getSettings(),
        contactsRepository: repository,
      ),
    )..loadIntoMemory();
    transport = _Transport('local-peer');
    service = ProfileMetadataService(
      store: SettingsProfileStore(storage: storage),
      peerMetadataStore: SettingsProfilePeerMetadataStore(storage: storage),
      peerProfiles: SettingsPeerProfileStore(storage: storage),
      transport: transport,
      contacts: contacts,
    );
    addTearDown(() async {
      await StorageService.resetForTesting();
      await root.delete(recursive: true);
    });
  });

  test(
    'broadcasts username to known peers through profile transport',
    () async {
      await contacts.upsertInviteContact(peerId: 'peer-a', username: 'Old');

      await service.updateDisplayName('Alice');

      await Future<void>.delayed(Duration.zero);

      expect(transport.sent, hasLength(1));
      expect(transport.sent.single.peerId, 'peer-a');
      expect(transport.sent.single.kind, 'profileUsername');
      expect(jsonDecode(transport.sent.single.text)['username'], 'Alice');
    },
  );

  test(
    'broadcasts trimmed local about without changing contact names',
    () async {
      await contacts.upsertInviteContact(peerId: 'peer-a', username: 'Alice');

      await service.updateAbout('  Local profile  ');

      expect(service.about, 'Local profile');
      expect(contacts.contacts.single.name, 'Alice');
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(transport.sent.single.text)['about'], 'Local profile');
    },
  );

  test(
    'updates remote invite name but preserves manual and stale state',
    () async {
      await contacts.upsertInviteContact(peerId: 'peer-a', username: 'Old');
      await service.handleIncomingUsernameUpdate(
        'peer-a',
        jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': 'Alice',
          'updatedAtMs': 200,
        }),
      );
      expect(contacts.contacts.single.name, 'Alice');
      expect(
        contacts.contacts.single.displayNameSource,
        ContactDisplayNameSource.inviteUsername,
      );

      await service.handleIncomingUsernameUpdate(
        'peer-a',
        jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': 'Stale',
          'updatedAtMs': 200,
        }),
      );
      expect(contacts.contacts.single.name, 'Alice');

      await contacts.renameContact('peer-a', 'My Alice');
      await service.handleIncomingUsernameUpdate(
        'peer-a',
        jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': 'Remote',
          'updatedAtMs': 300,
        }),
      );
      expect(contacts.contacts.single.name, 'My Alice');
    },
  );

  test(
    'stores profile update for non-contact without creating a contact',
    () async {
      await service.handleIncomingUsernameUpdate(
        'peer-new',
        jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': 'New peer',
          'updatedAtMs': 200,
        }),
      );

      expect(contacts.contacts, isEmpty);
      expect(service.profileForPeer('peer-new')?.displayName, 'New peer');
      expect(
        SettingsPeerProfileStore(
          storage: storage,
        ).profileForPeer('peer-new')?.displayName,
        'New peer',
      );
    },
  );

  test(
    'preserves remote about when a legacy username update omits it',
    () async {
      await service.handleIncomingUsernameUpdate(
        'peer-a',
        jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': 'Alice',
          'about': 'About Alice',
          'updatedAtMs': 200,
        }),
      );
      await service.handleIncomingUsernameUpdate(
        'peer-a',
        jsonEncode(<String, dynamic>{
          'type': 'username_update',
          'v': 1,
          'username': 'Alice Two',
          'updatedAtMs': 300,
        }),
      );

      final profile = service.profileForPeer('peer-a');
      expect(profile?.displayName, 'Alice Two');
      expect(profile?.about, 'About Alice');
    },
  );
}
