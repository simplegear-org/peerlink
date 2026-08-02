import '../../core/runtime/contacts_repository.dart';
import '../models/chat.dart';
import '../models/contact.dart';

class ChatContactsService {
  final ContactsRepository repository;

  const ChatContactsService({required this.repository});

  String resolveChatName(String peerId, {String? fallback}) {
    return repository.displayName(peerId, fallback: fallback);
  }

  String? contactNameForPeer(String peerId) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      return null;
    }
    for (final contact in repository.loadAll()) {
      if (contact.peerId == normalizedPeerId &&
          contact.name.trim().isNotEmpty) {
        return contact.name.trim();
      }
    }
    return null;
  }

  List<Contact> getContacts() {
    final contacts = repository.loadAll();
    contacts.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return contacts;
  }

  Future<void> addOrUpdateContact({
    required String peerId,
    required String name,
    required Map<String, Chat> chats,
    required void Function(String peerId) schedulePersistChatSummary,
    required void Function() notifyContactsUpdated,
  }) async {
    final normalizedPeerId = peerId.trim();
    final normalizedName = name.trim();
    if (normalizedPeerId.isEmpty || normalizedName.isEmpty) {
      throw ArgumentError('peerId and name are required');
    }
    await repository.save(
      Contact(peerId: normalizedPeerId, name: normalizedName),
    );

    final chatList = List<Chat>.from(chats.values);
    for (final chat in chatList) {
      final updatedName = resolveChatName(chat.peerId, fallback: chat.name);
      if (updatedName != chat.name) {
        chat.name = updatedName;
        schedulePersistChatSummary(chat.peerId);
      }
    }
    notifyContactsUpdated();
  }
}
