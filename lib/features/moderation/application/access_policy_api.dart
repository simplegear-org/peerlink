// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'access_policy_models.dart';

abstract interface class AccessPolicyApi {
  bool get allowMessagesOnlyFromContacts;

  Future<void> setAllowMessagesOnlyFromContacts(bool enabled);

  List<BlockedPeer> blockedPeers();

  bool isBlocked(String peerId);

  Future<void> blockPeer(String peerId, {String? reason});

  Future<void> unblockPeer(String peerId);

  IncomingInteractionDecision evaluateIncoming({
    required String peerId,
    required IncomingInteractionType type,
  });

  IncomingInteractionDecision evaluateOutgoing({
    required String peerId,
    required IncomingInteractionType type,
  });
}
