// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'network_state.dart';

enum NetworkEventType {
  messageReceived,
  messageStatusChanged,
  peerConnected,
  peerDisconnected,
  networkStateChanged,
}

class NetworkEvent {
  final NetworkEventType type;
  final dynamic payload;

  NetworkEvent({
    required this.type,
    this.payload,
  });
}

class PeerConnected extends NetworkEvent {
  final String peerId;
  PeerConnected(this.peerId)
    : super(type: NetworkEventType.peerConnected, payload: peerId);
}

class PeerDisconnected extends NetworkEvent {
  final String peerId;
  PeerDisconnected(this.peerId)
    : super(type: NetworkEventType.peerDisconnected, payload: peerId);
}

class MessageReceived extends NetworkEvent {
  final String from;
  final List<int> data;
  MessageReceived(this.from, this.data)
    : super(type: NetworkEventType.messageReceived, payload: data);
}

class MessageStatusChanged extends NetworkEvent {
  final dynamic status;
  MessageStatusChanged(this.status)
    : super(type: NetworkEventType.messageStatusChanged, payload: status);
}

class NetworkStateChanged extends NetworkEvent {
  final NetworkState state;
  NetworkStateChanged(this.state)
    : super(type: NetworkEventType.networkStateChanged, payload: state);
}
