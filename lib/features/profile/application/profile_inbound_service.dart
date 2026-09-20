// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/profile/application/profile_avatar_inbound_handler.dart';
import 'package:peerlink/features/profile/application/profile_inbound_handler.dart';
import 'package:peerlink/features/profile/application/profile_metadata_inbound_handler.dart';

class ProfileInboundService implements ProfileInboundHandler {
  const ProfileInboundService({
    required ProfileAvatarInboundHandler avatar,
    required ProfileMetadataInboundHandler metadata,
  }) : _avatar = avatar,
       _metadata = metadata;

  final ProfileAvatarInboundHandler _avatar;
  final ProfileMetadataInboundHandler _metadata;

  @override
  Future<void> handleIncomingAvatarAnnouncement(
    String senderPeerId,
    String payloadRaw,
  ) => _avatar.handleIncomingAvatarAnnouncement(senderPeerId, payloadRaw);

  @override
  Future<void> handleIncomingAvatarRemoval(
    String senderPeerId,
    String payloadRaw,
  ) => _avatar.handleIncomingAvatarRemoval(senderPeerId, payloadRaw);

  @override
  Future<void> handleIncomingAvatarQuery(
    String senderPeerId,
    String payloadRaw,
  ) => _avatar.handleIncomingAvatarQuery(senderPeerId, payloadRaw);

  @override
  Future<void> handleIncomingUsernameUpdate(
    String senderPeerId,
    String payloadRaw,
  ) => _metadata.handleIncomingUsernameUpdate(senderPeerId, payloadRaw);
}
