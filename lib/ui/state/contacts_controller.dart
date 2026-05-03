import 'dart:developer' as developer;

import '../../core/runtime/contacts_repository.dart';
import '../models/contact.dart';

class ContactsController {
  final ContactsRepository repository;

  final List<Contact> contacts;

  ContactsController({required this.repository}) : contacts = [];

  List<Contact> loadContacts() {
    try {
      return repository.loadAll();
    } catch (error, stackTrace) {
      developer.log(
        '[contacts] load failed error=$error',
        stackTrace: stackTrace,
      );
      return <Contact>[];
    }
  }

  Future<void> saveContact(Contact c) async {
    await repository.save(c);
  }

  Future<void> addContact(Contact contact) async {
    contacts.add(contact);
    await saveContact(contact);
  }

  Future<bool> addOrUpdateContact(Contact contact) async {
    final peerId = contact.peerId.trim();
    if (peerId.isEmpty) {
      return false;
    }
    final incomingName = contact.name.trim();
    final normalized = Contact(
      peerId: peerId,
      name: incomingName.isEmpty ? peerId : incomingName,
    );
    final index = contacts.indexWhere((c) => c.peerId == peerId);
    if (index == -1) {
      contacts.add(normalized);
      await saveContact(normalized);
      return true;
    }

    final existing = contacts[index];
    final existingName = existing.name.trim();
    final incomingHasDisplayName =
        incomingName.isNotEmpty && incomingName != peerId;
    final existingIsFallback =
        existingName.isEmpty || existingName == existing.peerId;
    if (!incomingHasDisplayName || !existingIsFallback) {
      return false;
    }

    contacts[index] = normalized;
    await saveContact(normalized);
    return true;
  }

  Future<bool> renameContact(String peerId, String name) async {
    final normalizedPeerId = peerId.trim();
    final normalizedName = name.trim();
    if (normalizedPeerId.isEmpty || normalizedName.isEmpty) {
      return false;
    }

    final renamed = Contact(peerId: normalizedPeerId, name: normalizedName);
    final index = contacts.indexWhere((c) => c.peerId == normalizedPeerId);
    if (index == -1) {
      contacts.add(renamed);
    } else {
      contacts[index] = renamed;
    }
    await saveContact(renamed);
    return true;
  }

  Future<bool> addDiscoveredPeer(String peerId) async {
    final existing = contacts.any((c) => c.peerId == peerId);
    if (existing) {
      return false;
    }

    final contact = Contact(peerId: peerId, name: peerId);
    contacts.add(contact);
    await saveContact(contact);
    return true;
  }

  Future<void> removeContact(String peerId) async {
    contacts.removeWhere((c) => c.peerId == peerId);
    await repository.delete(peerId);
  }
}
