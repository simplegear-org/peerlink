// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

/// Rejects delayed invites created with PeerLink's timestamp-based call ID.
///
/// Non-numeric and legacy IDs remain valid because their age cannot be proved.
class CallInviteFreshnessPolicy {
  const CallInviteFreshnessPolicy({
    required Duration maxAge,
    DateTime Function()? now,
  }) : _maxAge = maxAge,
       _now = now ?? DateTime.now;

  final Duration _maxAge;
  final DateTime Function() _now;

  bool isExpired(String callId) {
    final normalizedCallId = callId.trim();
    final timestampUs = int.tryParse(normalizedCallId);
    // PeerLink IDs use DateTime.microsecondsSinceEpoch (16 digits today).
    if (timestampUs == null || normalizedCallId.length < 14) {
      return false;
    }
    final createdAt = DateTime.fromMicrosecondsSinceEpoch(timestampUs);
    return _now().difference(createdAt) > _maxAge;
  }
}
