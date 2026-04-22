import '../transport/peer_session.dart';
import '../runtime/reconnect_scheduler.dart';
import 'peer_store.dart';

class ConnectionManager {
  final PeerStore peerStore;
  final ReconnectScheduler reconnect;
  final Future<PeerSession?> Function(String peerId, String address)? dialer;

  final Map<String, PeerSession> _connections = {};

  final int maxConnections;

  ConnectionManager({
    required this.peerStore,
    required this.reconnect,
    this.dialer,
    this.maxConnections = 100,
  });

  PeerSession? get(String peerId) {
    return _connections[peerId];
  }

  Future<PeerSession?> dial(String peerId) async {
    if (_connections.containsKey(peerId)) {
      return _connections[peerId];
    }

    final addrs = peerStore.getAddresses(peerId);

    if (addrs.isEmpty) return null;

    for (final addr in addrs) {
      try {
        final session = await dialer?.call(peerId, addr);
        if (session == null) {
          continue;
        }

        _connections[peerId] = session;

        reconnect.reset(peerId);

        _prune();

        return session;
      } catch (_) {
        // Try next known address.
      }
    }

    _scheduleReconnect(peerId);

    return null;
  }

  void register(String peerId, PeerSession s) {
    _connections[peerId] = s;
  }

  void onConnectionLost(String peerId) {
    _connections.remove(peerId);

    _scheduleReconnect(peerId);
  }

  void _scheduleReconnect(String peerId) async {
    final delay = reconnect.nextDelay(peerId);

    await Future.delayed(delay);

    dial(peerId);
  }

  void _prune() {
    if (_connections.length <= maxConnections) {
      return;
    }

    final peerId = _connections.keys.first;

    _connections[peerId]?.close();

    _connections.remove(peerId);
  }
}
