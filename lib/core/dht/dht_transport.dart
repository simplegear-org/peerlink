import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'dart:developer' as developer;

import '../overlay/overlay_router.dart';
import '../overlay/overlay_message.dart';
import 'rpc/rpc_types.dart';

class DhtTransport {
  final String selfId;
  final OverlayRouter router;

  final void Function(String fromPeer, RpcMessage msg) onMessage;
  int _logSeq = 0;

  DhtTransport({
    required this.selfId,
    required this.router,
    required this.onMessage,
  }) {
    router.onMessage.listen(_handleOverlayMessage);
  }

  String _randomId() {
      final r = Random();
      return List.generate(16, (_) => r.nextInt(255)).join();
    }

  Future<void> send(String peerId, RpcMessage msg) async {
    final payload = utf8.encode(jsonEncode(msg.toJson()));
    _log('send peer=$peerId type=${msg.type}');

    final overlay = OverlayMessage(
      messageId: _randomId(),
      from: selfId,
      to: peerId,
      payload: Uint8List.fromList(payload),
    );

    try {
      await router.send(overlay);
    } catch (e) {
      _log('send failed peer=$peerId error=$e');
    }
  }

  void _handleOverlayMessage(OverlayMessage msg) {
    if (msg.to != selfId) return;

    final decoded = jsonDecode(utf8.decode(msg.payload));
    if (decoded is! Map<String, dynamic>) {
      _log('recv:drop invalid payload type=${decoded.runtimeType}');
      return;
    }
    if (decoded['type'] is! String) {
      _log('recv:drop missing type');
      return;
    }
    if (decoded['payload'] is! Map<String, dynamic>) {
      _log('recv:drop non-rpc payload');
      return;
    }

    final rpc = RpcMessage.fromJson(decoded);
    _log('recv peer=${msg.from} type=${rpc.type}');

    onMessage(msg.from, rpc);
  }

  void _log(String message) {
    developer.log('[dht][$selfId][${_logSeq++}] $message');
  }
}
