// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../transport/transport_mode.dart';
import '../transport/webrtc_transport.dart';

class MeshPeerTransports {
  final WebRtcTransport direct;

  MeshPeerTransports({required this.direct});

  WebRtcTransport? byMode(TransportMode mode) {
    if (mode == TransportMode.direct) {
      return direct;
    }

    return null;
  }
}
