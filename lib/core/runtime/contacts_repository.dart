// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../../ui/models/contact.dart';
import 'contact_name_resolver.dart';
import 'storage_service.dart';

class ContactsRepository {
  final StorageService storage;

  ContactsRepository({required this.storage});

  List<Contact> loadAll() {
    final box = storage.getContacts();
    final result = <Contact>[];
    for (final entry in box.values) {
      if (entry is! Map) {
        continue;
      }
      result.add(Contact.fromJson(Map<String, dynamic>.from(entry)));
    }
    return result;
  }

  Future<void> save(Contact contact) {
    return storage.getContacts().put(contact.peerId, contact.toJson());
  }

  Future<void> delete(String peerId) {
    return storage.getContacts().delete(peerId);
  }

  bool contains(String peerId) {
    final normalized = peerId.trim();
    if (normalized.isEmpty) {
      return false;
    }
    return storage.getContacts().get(normalized) is Map;
  }

  String displayName(String? peerId, {String? fallback}) {
    if (peerId == null || peerId.isEmpty) {
      return fallback ?? 'Неизвестный контакт';
    }
    return ContactNameResolver.resolveFromEntry(
      storage.getContacts().get(peerId),
      peerId: peerId,
      fallback: fallback,
    );
  }

  int count() => storage.getContacts().values.length;
}
