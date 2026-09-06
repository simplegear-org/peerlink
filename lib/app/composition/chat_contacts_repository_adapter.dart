// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/contacts/domain/contact.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';

class ChatContactsRepositoryAdapter implements ChatContactsRepository {
  const ChatContactsRepositoryAdapter(this._repository);

  final ContactsRepository _repository;

  @override
  String displayName(String? peerId, {String? fallback}) {
    return _repository.displayName(peerId, fallback: fallback);
  }

  @override
  List<Contact> loadAll() {
    return _repository.loadAll();
  }

  @override
  Future<void> save(Contact contact) {
    return _repository.save(contact);
  }
}
