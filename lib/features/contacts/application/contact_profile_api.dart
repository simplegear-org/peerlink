// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

/// Applies profile metadata received from a remote peer to its contact.
abstract interface class ContactProfileApi {
  Future<bool> applyRemoteUsername({
    required String peerId,
    required String username,
  });
}
