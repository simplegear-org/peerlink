import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'rpc/rpc_types.dart';

const int kBucketSize = 20;
const int idBits = 256;

class RoutingTable {
  final String localId;

  final List<KBucket> _buckets = List.generate(idBits, (_) => KBucket());

  RoutingTable(this.localId);

  void update(NodeInfo node) {
    if (node.nodeId == localId) return;

    final bucketIndex = _bucketIndex(node.nodeId);

    _buckets[bucketIndex].update(node);
  }

  List<NodeInfo> getClosest(String targetId, int count) {
    final all = <NodeInfo>[];

    for (final b in _buckets) {
      all.addAll(b.nodes);
    }

    all.sort((a, b) {
      final da = distance(a.nodeId, targetId);
      final db = distance(b.nodeId, targetId);
      return da.compareTo(db);
    });

    return all.take(count).toList();
  }

  int _bucketIndex(String nodeId) {
    final dist = distance(localId, nodeId);

    if (dist == BigInt.zero) return 0;

    return dist.bitLength - 1;
  }

  static BigInt distance(String a, String b) {
    final ai = _normalizeNodeId(a);
    final bi = _normalizeNodeId(b);

    return ai ^ bi;
  }

  static BigInt _normalizeNodeId(String nodeId) {
    final hexPattern = RegExp(r'^[0-9a-fA-F]+$');
    if (hexPattern.hasMatch(nodeId)) {
      return BigInt.parse(nodeId, radix: 16);
    }

    final digest = sha256.convert(utf8.encode(nodeId)).bytes;
    final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return BigInt.parse(hex, radix: 16);
  }
}

class KBucket {
  final LinkedList<_BucketNode> _list = LinkedList();

  Iterable<NodeInfo> get nodes => _list.map((e) => e.node);

  void update(NodeInfo node) {
    for (final entry in _list) {
      if (entry.node.nodeId == node.nodeId) {
        entry.unlink();
        _list.add(entry);
        return;
      }
    }

    if (_list.length < kBucketSize) {
      _list.add(_BucketNode(node));
    } else {
      _list.first.unlink();
      _list.add(_BucketNode(node));
    }
  }
}

final class _BucketNode extends LinkedListEntry<_BucketNode> {
  final NodeInfo node;

  _BucketNode(this.node);
}
