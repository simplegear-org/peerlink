import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/reliable_messaging_service.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';
import 'package:peerlink/features/contacts/domain/contact.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/moderation/application/peer_access_control_service.dart';
import 'package:peerlink/features/profile/application/avatar_service.dart';
import 'package:peerlink/features/profile/application/profile_avatar_transport.dart';
import 'package:peerlink/ui/state/contacts_controller.dart';

class _Transport implements ProfileAvatarTransport {
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

class _EmptySummaries implements ChatSummaryStore {
  @override
  Future<void> delete(String peerId) async {}
  @override
  Future<Map<String, dynamic>?> get(String peerId) async => null;
  @override
  Future<List<Map<String, dynamic>>> loadAll() async => const [];
  @override
  Future<int> unreadMessagesCount() async => 0;
  @override
  Future<void> save(String peerId, Map<String, dynamic> json) async {}
}

void main() {
  late Directory root;
  late StorageService storage;
  late ContactsController contacts;
  late _Transport transport;
  late AvatarService service;

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
    service = AvatarService(
      transport: transport,
      storage: storage,
      chatSummaryStore: _EmptySummaries(),
      contacts: contacts,
    );
    addTearDown(() async {
      await service.dispose();
      await StorageService.resetForTesting();
      await root.delete(recursive: true);
    });
  });

  test(
    'broadcasts username to known peers through profile transport',
    () async {
      await contacts.upsertInviteContact(peerId: 'peer-a', username: 'Old');

      await service.broadcastLocalUsername('Alice');

      expect(transport.sent, hasLength(1));
      expect(transport.sent.single.peerId, 'peer-a');
      expect(transport.sent.single.kind, 'profileUsername');
      expect(jsonDecode(transport.sent.single.text)['username'], 'Alice');
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

  test('creates a contact for the first QR profile update', () async {
    await service.handleIncomingUsernameUpdate(
      'peer-new',
      jsonEncode(<String, dynamic>{
        'type': 'username_update',
        'v': 1,
        'username': 'New peer',
        'updatedAtMs': 200,
      }),
    );

    expect(contacts.contacts.single.name, 'New peer');
    expect(
      contacts.contacts.single.displayNameSource,
      ContactDisplayNameSource.inviteUsername,
    );
  });
}
