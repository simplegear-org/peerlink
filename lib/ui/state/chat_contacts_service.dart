import '../../core/runtime/contact_name_resolver.dart';
import '../../core/runtime/storage_service.dart';
import '../models/chat.dart';
import '../models/contact.dart';

class ChatContactsService {
  final SecureStorageBox contactsBox;

  const ChatContactsService({required this.contactsBox});

  String resolveChatName(String peerId, {String? fallback}) {
    return ContactNameResolver.resolveFromEntry(
      contactsBox.get(peerId),
      peerId: peerId,
      fallback: fallback,
    );
  }

  String? contactNameForPeer(String peerId) {
    final raw = contactsBox.get(peerId);
    if (raw is Map) {
      final name = raw['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return null;
  }

  List<Contact> getContacts() {
    final contacts = <Contact>[];
    final keys = contactsBox.keys
        .map((key) => key.toString())
        .toList(growable: false);
    for (final key in keys) {
      final value = contactsBox.get(key);
      if (value is Map<String, dynamic>) {
        try {
          contacts.add(Contact.fromJson(value));
        } catch (_) {}
        continue;
      }
      if (value is Map) {
        try {
          contacts.add(Contact.fromJson(Map<String, dynamic>.from(value)));
        } catch (_) {}
      }
    }
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
    await contactsBox.put(
      normalizedPeerId,
      Contact(peerId: normalizedPeerId, name: normalizedName).toJson(),
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
