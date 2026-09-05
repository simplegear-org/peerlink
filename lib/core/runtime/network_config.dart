// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class NetworkConfig {
  final bool enableRelay;
  final bool enableTurn;
  final bool enableDht;
  final Duration bucketRefreshInterval;

  const NetworkConfig({
    this.enableRelay = true,
    this.enableTurn = true,
    this.enableDht = true,
    this.bucketRefreshInterval = const Duration(minutes: 5),
  });
}
