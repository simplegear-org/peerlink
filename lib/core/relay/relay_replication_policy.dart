// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

/// Shared replication rules for relay-backed messages and blobs.
abstract final class RelayReplicationPolicy {
  static const int maxCandidates = 3;
  static const int desiredSuccessfulReplicas = 2;

  /// The quorum for a selected candidate set: 1/1, 2/2, or 2/3.
  static int requiredSuccessfulReplicas(int candidateCount) {
    if (candidateCount <= 0) {
      return 0;
    }
    return candidateCount < desiredSuccessfulReplicas
        ? candidateCount
        : desiredSuccessfulReplicas;
  }
}
