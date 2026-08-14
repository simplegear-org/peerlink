// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class PeerPresenceUpdate {
  final String peerId;
  final bool isOnline;
  final DateTime observedAt;
  final DateTime? lastSeenAt;

  const PeerPresenceUpdate({
    required this.peerId,
    required this.isOnline,
    required this.observedAt,
    this.lastSeenAt,
  });
}
