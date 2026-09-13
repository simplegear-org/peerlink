// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

abstract interface class ProfileAvatarInboundHandler {
  Future<void> handleIncomingAvatarAnnouncement(
    String senderPeerId,
    String payloadRaw,
  );

  Future<void> handleIncomingAvatarRemoval(
    String senderPeerId,
    String payloadRaw,
  );

  Future<void> handleIncomingAvatarQuery(
    String senderPeerId,
    String payloadRaw,
  );

  Future<void> handleIncomingUsernameUpdate(
    String senderPeerId,
    String payloadRaw,
  );
}
