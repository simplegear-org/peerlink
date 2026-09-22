// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class PeerLinkSourceMetadata {
  const PeerLinkSourceMetadata._();

  static const license = 'MPL-2.0';
  static const licenseName = 'Mozilla Public License 2.0';
  static const fallbackSourceUrl =
      'https://github.com/simplegear-org/peerlink/tree/source-v3.14.2-build-2026092201';
  static const sourceUrl = String.fromEnvironment(
    'PEERLINK_SOURCE_URL',
    defaultValue: fallbackSourceUrl,
  );
}
