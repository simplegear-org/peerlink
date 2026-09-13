// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class Contact {
  final String peerId;
  final String name;
  final ContactDisplayNameSource displayNameSource;

  Contact({
    required this.peerId,
    required this.name,
    this.displayNameSource = ContactDisplayNameSource.manual,
  });

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      peerId: json['peerId'] as String,
      name: json['name'] as String,
      displayNameSource: ContactDisplayNameSource.fromStorage(
        json['displayNameSource']?.toString(),
        name: json['name'] as String,
        peerId: json['peerId'] as String,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'peerId': peerId,
      'name': name,
      'displayNameSource': displayNameSource.storageValue,
    };
  }

  String shortId() {
    if (peerId.length <= 8) return peerId;
    return "${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}";
  }
}

enum ContactDisplayNameSource {
  manual('manual'),
  inviteUsername('inviteUsername'),
  peerIdFallback('peerIdFallback');

  const ContactDisplayNameSource(this.storageValue);

  final String storageValue;

  static ContactDisplayNameSource fromStorage(
    String? value, {
    required String name,
    required String peerId,
  }) {
    for (final source in values) {
      if (source.storageValue == value) {
        return source;
      }
    }
    // Legacy persisted contacts were explicitly created or renamed by a user,
    // except for the old Peer-ID fallback created by discovery/invites.
    return name.trim().isEmpty || name.trim() == peerId
        ? ContactDisplayNameSource.peerIdFallback
        : ContactDisplayNameSource.manual;
  }
}
