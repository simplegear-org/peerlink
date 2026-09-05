// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../routing_table.dart';
import '../record_store.dart';
import '../dht_transport.dart';
import 'rpc_types.dart';

class KademliaProtocol {
  final String selfId;
  final RoutingTable routingTable;
  final RecordStore recordStore;
  final DhtTransport transport;

  void Function(String peerId, RpcMessage msg)? onMessage;

  KademliaProtocol({
    required this.selfId,
    required this.routingTable,
    required this.recordStore,
    required this.transport,
  });

  Future<void> send(String peerId, RpcMessage msg) async {
    await transport.send(peerId, msg);
  }

  void handleIncoming(String fromPeer, RpcMessage msg) {
    onMessage?.call(fromPeer, msg);
  }
}
