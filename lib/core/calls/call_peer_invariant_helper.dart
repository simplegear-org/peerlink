// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'call_models.dart';

class CallPeerInvariantHelper {
  const CallPeerInvariantHelper();

  bool matchesCurrentCall({
    required CallState currentState,
    required String peerId,
    required String callId,
  }) {
    return !currentState.isIdle &&
        currentState.peerId == peerId &&
        currentState.callId == callId;
  }

  bool hasForeignPeerForActiveCallId({
    required CallState currentState,
    required String peerId,
    required String callId,
  }) {
    return !currentState.isIdle &&
        currentState.callId == callId &&
        currentState.peerId != null &&
        currentState.peerId != peerId;
  }
}
