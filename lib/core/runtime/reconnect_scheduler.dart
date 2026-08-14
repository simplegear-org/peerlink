// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class ReconnectScheduler {
  final Map<String, int> attempts = {};

  Duration nextDelay(String peerId) {
    final a = attempts.putIfAbsent(peerId, () => 0);

    attempts[peerId] = a + 1;

    final seconds = (1 << a).clamp(1, 60);

    return Duration(seconds: seconds);
  }

  void reset(String peerId) {
    attempts.remove(peerId);
  }
}
