// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class Contact {
  final String peerId;
  final String name;

  Contact({required this.peerId, required this.name});

  factory Contact.fromJson(Map<String, dynamic> json) {
    return Contact(
      peerId: json['peerId'] as String,
      name: json['name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {'peerId': peerId, 'name': name};
  }

  String shortId() {
    if (peerId.length <= 8) return peerId;
    return "${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}";
  }
}
