import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/contacts/domain/contact.dart';

class _FakeContactsRepository implements ChatContactsRepository {
  final Map<String, Contact> contacts = <String, Contact>{};

  @override
  List<Contact> loadAll() => contacts.values.toList(growable: false);

  @override
  Future<void> save(Contact contact) async {
    contacts[contact.peerId] = contact;
  }

  @override
  String displayName(String? peerId, {String? fallback}) {
    final normalized = peerId?.trim() ?? '';
    if (normalized.isEmpty) {
      return fallback ?? 'Неизвестный контакт';
    }
    return contacts[normalized]?.name ?? fallback ?? normalized;
  }
}

void main() {
  test(
    'addOrUpdateContact refreshes chat name and schedules persistence',
    () async {
      const peerId = 'peer-a';
      final repository = _FakeContactsRepository();
      final service = ChatContactsService(repository: repository);
      final chat = Chat(peerId: peerId, name: peerId);
      final persistedPeerIds = <String>[];
      var notified = false;

      await service.addOrUpdateContact(
        peerId: peerId,
        name: 'Alice',
        chats: <String, Chat>{peerId: chat},
        schedulePersistChatSummary: persistedPeerIds.add,
        notifyContactsUpdated: () {
          notified = true;
        },
      );

      expect(repository.contacts[peerId]?.name, 'Alice');
      expect(chat.name, 'Alice');
      expect(persistedPeerIds, <String>[peerId]);
      expect(notified, isTrue);
    },
  );
}
