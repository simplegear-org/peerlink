// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

enum IncomingInteractionType {
  directMessage,
  directMedia,
  messageReceipt,
  profile,
  accountPairing,
  groupInvite,
  groupControl,
  groupContent,
  call,
  push,
  invite,
}

enum IncomingInteractionDecision { allow, blockedPeer, contactsOnly }

class BlockedPeer {
  final String peerId;
  final DateTime blockedAt;
  final String? reason;

  const BlockedPeer({
    required this.peerId,
    required this.blockedAt,
    this.reason,
  });

  factory BlockedPeer.fromJson(Map<String, dynamic> json) {
    final peerId = (json['peerId'] as String? ?? '').trim();
    final blockedAtRaw = (json['blockedAt'] as String? ?? '').trim();
    return BlockedPeer(
      peerId: peerId,
      blockedAt: DateTime.tryParse(blockedAtRaw) ?? DateTime.now(),
      reason: (json['reason'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'peerId': peerId,
    'blockedAt': blockedAt.toIso8601String(),
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
  };
}
