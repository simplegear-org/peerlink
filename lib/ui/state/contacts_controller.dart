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
