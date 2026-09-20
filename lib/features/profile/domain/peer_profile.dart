// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/profile/domain/profile.dart';

class PeerProfile {
  const PeerProfile({
    required this.peerId,
    required this.displayName,
    required this.about,
    required this.updatedAtMs,
  });

  final String peerId;
  final String displayName;
  final String about;
  final int updatedAtMs;

  factory PeerProfile.fromJson(String peerId, Map<String, dynamic> json) {
    return PeerProfile(
      peerId: peerId.trim(),
      displayName: Profile.normalizeDisplayName(json['displayName']),
      about: Profile.normalizeAbout(json['about']),
      updatedAtMs: json['updatedAtMs'] is int
          ? json['updatedAtMs'] as int
          : int.tryParse('${json['updatedAtMs']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'displayName': displayName,
    'about': about,
    'updatedAtMs': updatedAtMs,
  };
}
