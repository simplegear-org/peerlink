// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/profile/domain/peer_profile.dart';

abstract interface class PeerProfileStore {
  PeerProfile? profileForPeer(String peerId);

  Future<void> save(PeerProfile profile);
}
