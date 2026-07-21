import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../core/runtime/contacts_repository.dart';
import '../models/contact.dart';

class ContactsController extends ChangeNotifier {
  final ContactsRepository repository;

  final List<Contact> _contacts;

  ContactsController({required this.repository}) : _contacts = [];

  UnmodifiableListView<Contact> get contacts =>
      UnmodifiableListView<Contact>(_contacts);

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

  void loadIntoMemory() {
    _contacts
      ..clear()
      ..addAll(loadContacts());
    notifyListeners();
  }

  Future<void> saveContact(Contact c) async {
    await repository.save(c);
  }

  Future<void> addContact(Contact contact) async {
    _contacts.add(contact);
    await saveContact(contact);
    notifyListeners();
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
    final index = _contacts.indexWhere((c) => c.peerId == peerId);
    if (index == -1) {
      _contacts.add(normalized);
      await saveContact(normalized);
      notifyListeners();
      return true;
    }

    final existing = _contacts[index];
    final existingName = existing.name.trim();
    final incomingHasDisplayName =
        incomingName.isNotEmpty && incomingName != peerId;
    final existingIsFallback =
        existingName.isEmpty || existingName == existing.peerId;
    if (!incomingHasDisplayName || !existingIsFallback) {
      return false;
    }

    _contacts[index] = normalized;
    await saveContact(normalized);
    notifyListeners();
    return true;
  }

  Future<bool> renameContact(String peerId, String name) async {
    final normalizedPeerId = peerId.trim();
    final normalizedName = name.trim();
    if (normalizedPeerId.isEmpty || normalizedName.isEmpty) {
      return false;
    }

    final renamed = Contact(peerId: normalizedPeerId, name: normalizedName);
    final index = _contacts.indexWhere((c) => c.peerId == normalizedPeerId);
    if (index == -1) {
      _contacts.add(renamed);
    } else {
      _contacts[index] = renamed;
    }
    await saveContact(renamed);
    notifyListeners();
    return true;
  }

  Future<bool> addDiscoveredPeer(String peerId) async {
    final existing = _contacts.any((c) => c.peerId == peerId);
    if (existing) {
      return false;
    }

    final contact = Contact(peerId: peerId, name: peerId);
    _contacts.add(contact);
    await saveContact(contact);
    notifyListeners();
    return true;
  }

  Future<void> removeContact(String peerId) async {
    _contacts.removeWhere((c) => c.peerId == peerId);
    await repository.delete(peerId);
    notifyListeners();
  }
}
