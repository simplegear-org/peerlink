// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class CallControlPayload {
  const CallControlPayload({required this.fromPeerId, required this.text});

  final String fromPeerId;
  final String text;
}

typedef CallControlInboundHandler =
    Future<bool> Function(CallControlPayload payload);

abstract interface class CallControlTransport {
  Future<void> send(String peerId, String text);

  void setIncomingHandler(CallControlInboundHandler? handler);
}
