import 'dart:async';
import 'dart:developer' as developer;

import '../transport/transport_manager.dart';
import '../dht/routing_table.dart';
import '../relay/relay_router.dart';
import '../runtime/network_event_bus.dart';
import 'overlay_message.dart';
import 'message_cache.dart';

class OverlayRouter {
  final String selfId;

  final TransportManager transport;
  final RoutingTable routing;
  final RelayRouter relay;
  final NetworkEventBus events;

  final MessageCache _cache = MessageCache();

  final StreamController<OverlayMessage> _incoming =
      StreamController.broadcast();
  final _payloadController = StreamController<OverlayPayload>.broadcast();
  late final StreamSubscription<TransportMessage> _transportSubscription;
  int _logSeq = 0;

  Stream<OverlayMessage> get onMessage => _incoming.stream;
  Stream<OverlayPayload> get onPayload => _payloadController.stream;

  OverlayRouter({
    required this.selfId,
    required this.transport,
    required this.routing,
    required this.relay,
    required this.events,
  }) {
    _transportSubscription = transport.onMessage.listen(_handleTransportMessage);
  }

  /// ================================
  /// SEND MESSAGE
  /// ================================

  Future<void> send(OverlayMessage msg) async {
    if (msg.from != selfId) {
      throw Exception("OverlayRouter: sender mismatch");
    }

    final id = msg.messageId;
    _log('send messageId=$id to=${msg.to} ttl=${msg.ttl}');

    if (_cache.contains(id)) {
      return;
    }

    _cache.store(id);

    if (msg.to == selfId) {
      _deliver(msg);
      return;
    }

    final peers = _selectPeers(msg.to);
    _log('send:peers count=${peers.length} to=${msg.to}');

    Object? lastError;
    var successCount = 0;

    for (final peer in peers) {
      try {
        await transport.send(peer, msg.encode());
        successCount++;
      } catch (e) {
        lastError = e;
        _log('send:failed peer=$peer error=$e');
      }
    }

    if (successCount == 0 && lastError != null) {
      throw lastError;
    }
  }

  /// ================================
  /// HANDLE INCOMING
  /// ================================

  void _handleTransportMessage(TransportMessage transportMsg) {
    final msg = OverlayMessage.decode(transportMsg.data);
    _log('recv messageId=${msg.messageId} from=${transportMsg.from} to=${msg.to} ttl=${msg.ttl}');

    if (_cache.contains(msg.messageId)) {
      return;
    }

    _cache.store(msg.messageId);

    if (msg.to == selfId) {
      _log('recv:deliver local messageId=${msg.messageId}');
      _deliver(msg);
      return;
    }

    if (msg.ttl <= 0) {
      _log('recv:drop ttl expired messageId=${msg.messageId}');
      return;
    }

    _forward(msg);
  }

  /// ================================
  /// DELIVER LOCAL
  /// ================================

  void _deliver(OverlayMessage msg) {
    _log('deliver messageId=${msg.messageId} from=${msg.from}');
    _incoming.add(msg);
    _payloadController.add(
      OverlayPayload(
        fromPeerId: msg.from,
        bytes: msg.payload,
      ),
    );
  }

  /// ================================
  /// FORWARD
  /// ================================

  void _forward(OverlayMessage msg) async {
    final next = msg.copyWith(
      ttl: msg.ttl - 1,
    );

    final peers = _selectPeers(msg.to);
    _log('forward messageId=${msg.messageId} ttl=${next.ttl} peers=${peers.length}');

    if (peers.isEmpty) {
      final relays = relay.selectRelays(msg.to);
      _log('forward:relays count=${relays.length} to=${msg.to}');

      for (final r in relays) {
        try {
          await transport.send(r, next.encode());
        } catch (e) {
          _log('forward:relay failed peer=$r error=$e');
        }
      }

      return;
    }

    for (final peer in peers) {
      try {
        await transport.send(peer, next.encode());
      } catch (e) {
        _log('forward:failed peer=$peer error=$e');
      }
    }
  }

  /// ================================
  /// ROUTING
  /// ================================

  List<String> _selectPeers(String target) {
    final closest = routing.getClosest(target, 3);
    return closest.map((node) => node.nodeId).toList();
  }

  void _log(String message) {
    developer.log('[overlay][$selfId][${_logSeq++}] $message');
  }

  Future<void> dispose() async {
    await _transportSubscription.cancel();
    await _incoming.close();
    await _payloadController.close();
  }
}

class OverlayPayload {
  final String fromPeerId;
  final List<int> bytes;

  OverlayPayload({
    required this.fromPeerId,
    required this.bytes,
  });
}
