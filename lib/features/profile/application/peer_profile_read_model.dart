// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/contacts/application/contact_profile_api.dart';
import 'package:peerlink/features/moderation/application/access_policy_api.dart';
import 'package:peerlink/features/profile/application/peer_profile_api.dart';
import 'package:peerlink/features/profile/application/profile_metadata_api.dart';

class PeerProfileReadModel {
  const PeerProfileReadModel({
    required this.peerId,
    required this.displayName,
    required this.contactDisplayName,
    required this.about,
    required this.isContact,
    required this.isBlocked,
    required this.isLocalPeer,
  });

  final String peerId;
  final String displayName;
  final String? contactDisplayName;
  final String about;
  final bool isContact;
  final bool isBlocked;
  final bool isLocalPeer;

  bool get hasAbout => about.isNotEmpty;

  /// Prefers a local contact name over remote profile data.
  String get preferredDisplayName => contactDisplayName ?? displayName;
}

/// Provides a presentation-ready snapshot of a remote peer profile.
abstract interface class PeerProfileReadApi {
  PeerProfileReadModel readForPeer(String peerId);
}

class PeerProfileReadService implements PeerProfileReadApi {
  PeerProfileReadService({
    required PeerProfileApi profiles,
    required ContactProfileApi contacts,
    required AccessPolicyApi accessPolicy,
    required ProfileMetadataApi localProfile,
    required String localPeerId,
  }) : _profiles = profiles,
       _contacts = contacts,
       _accessPolicy = accessPolicy,
       _localProfile = localProfile,
       _localPeerId = localPeerId.trim();

  final PeerProfileApi _profiles;
  final ContactProfileApi _contacts;
  final AccessPolicyApi _accessPolicy;
  final ProfileMetadataApi _localProfile;
  final String _localPeerId;

  @override
  PeerProfileReadModel readForPeer(String peerId) {
    final normalizedPeerId = peerId.trim();
    final isLocalPeer =
        normalizedPeerId.isNotEmpty && normalizedPeerId == _localPeerId;
    if (isLocalPeer) {
      final localName = _localProfile.displayName.trim();
      return PeerProfileReadModel(
        peerId: normalizedPeerId,
        displayName: localName.isEmpty
            ? _shortPeerId(normalizedPeerId)
            : localName,
        contactDisplayName: null,
        about: _localProfile.about.trim(),
        isContact: false,
        isBlocked: false,
        isLocalPeer: true,
      );
    }
    final remoteProfile = _profiles.profileForPeer(normalizedPeerId);
    final remoteName = remoteProfile?.displayName.trim() ?? '';
    return PeerProfileReadModel(
      peerId: normalizedPeerId,
      displayName: remoteName.isEmpty
          ? _shortPeerId(normalizedPeerId)
          : remoteName,
      contactDisplayName: _contacts.contactDisplayNameFor(normalizedPeerId),
      about: remoteProfile?.about.trim() ?? '',
      isContact: _contacts.hasContact(normalizedPeerId),
      isBlocked: _accessPolicy.isBlocked(normalizedPeerId),
      isLocalPeer: false,
    );
  }

  String _shortPeerId(String peerId) {
    if (peerId.length <= 8) {
      return peerId.isEmpty ? '?' : peerId;
    }
    return '${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}';
  }
}
