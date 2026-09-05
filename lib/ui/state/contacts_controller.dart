// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import '../../features/contacts/infrastructure/contacts_repository.dart';
import '../../core/runtime/peer_access_control_service.dart';
import '../models/contact.dart';

class ContactsController extends ChangeNotifier {
  final ContactsRepository repository;
  final PeerAccessControlService accessControl;
  final void Function(String reason)? onAccessPolicyChanged;
  final Future<void> Function(String reason)? onAccessPolicyChangedNow;

  final List<Contact> _contacts;

  ContactsController({
    required this.repository,
    required this.accessControl,
    this.onAccessPolicyChanged,
    this.onAccessPolicyChangedNow,
  }) : _contacts = [];

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
    onAccessPolicyChanged?.call('contact_save');
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
    onAccessPolicyChanged?.call('contact_remove');
    notifyListeners();
  }

  bool isPeerBlocked(String peerId) => accessControl.isBlocked(peerId);

  Future<void> blockPeer(String peerId, {String? reason}) async {
    await accessControl.blockPeer(peerId, reason: reason);
    await onAccessPolicyChangedNow?.call('contact_block_peer');
    notifyListeners();
  }

  Future<void> unblockPeer(String peerId) async {
    await accessControl.unblockPeer(peerId);
    await onAccessPolicyChangedNow?.call('contact_unblock_peer');
    notifyListeners();
  }
}
