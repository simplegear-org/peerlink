// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

/// Local profile metadata owned by the Profile feature.
class Profile {
  static const int maxDisplayNameLength = 64;
  static const int maxAboutLength = 160;

  const Profile({this.displayName = '', this.about = ''});

  final String displayName;
  final String about;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      displayName: normalizeDisplayName(json['displayName']),
      about: normalizeAbout(json['about']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'displayName': displayName,
    'about': about,
  };

  Profile copyWith({String? displayName, String? about}) => Profile(
    displayName: displayName ?? this.displayName,
    about: about ?? this.about,
  );

  static String normalizeDisplayName(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.length > maxDisplayNameLength ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const FormatException('Недопустимое имя в PeerLink');
    }
    return normalized;
  }

  static String normalizeAbout(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    if (normalized.runes.length > maxAboutLength) {
      throw const FormatException('Недопустимое описание профиля');
    }
    return normalized;
  }
}
