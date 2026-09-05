// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../dht/rpc/rpc_types.dart';

class PeerStore {
  final Map<String, PeerRecord> _peers = {};

  void addPeer(NodeInfo node) {
    final rec = _peers.putIfAbsent(node.nodeId, () => PeerRecord(node.nodeId));

    rec.addresses.add(node.address);
  }

  List<String> getAddresses(String peerId) {
    return _peers[peerId]?.addresses.toList() ?? [];
  }

  void markProtocol(String peerId, String protocol) {
    final rec = _peers.putIfAbsent(peerId, () => PeerRecord(peerId));

    rec.protocols.add(protocol);
  }

  PeerRecord? get(String peerId) {
    return _peers[peerId];
  }

  List<PeerRecord> get allPeers => _peers.values.toList();
}

class PeerRecord {
  final String peerId;

  final Set<String> addresses = {};

  final Set<String> protocols = {};

  DateTime lastSeen = DateTime.now();

  int reputation = 0;

  PeerRecord(this.peerId);
}
