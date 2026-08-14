// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'call_media_stats_utils.dart';

class CallRecoveryStatsTracker {
  int? _lastReceivedBytes;

  void reset() {
    _lastReceivedBytes = null;
  }

  bool recordInboundAdvanced(AudioTrafficStats stats) {
    if (stats.selectedCandidatePairId == null) {
      return false;
    }
    final receivedBytes = stats.receivedBytes;
    final previous = _lastReceivedBytes;
    _lastReceivedBytes = receivedBytes;
    if (receivedBytes <= 0) {
      return false;
    }
    if (previous != null && receivedBytes <= previous) {
      return false;
    }
    return true;
  }
}
