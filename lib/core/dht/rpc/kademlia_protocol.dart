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