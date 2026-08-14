// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class RelayServerStatus {
  final String url;
  final bool healthy;
  final String? lastError;
  final DateTime? lastSuccessAt;

  const RelayServerStatus({
    required this.url,
    required this.healthy,
    this.lastError,
    this.lastSuccessAt,
  });
}
