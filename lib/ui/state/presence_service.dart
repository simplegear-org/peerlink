import 'dart:async';

import '../../core/node/node_facade.dart';
import '../../core/node/peer_presence.dart';

class PresenceService {
  final NodeFacade facade;
  final Map<String, bool> _peerOnline = {};
  final Map<String, DateTime> _peerLastSeen = {};
  final StreamController<String> _updatesController =
      StreamController<String>.broadcast();
  StreamSubscription<PeerPresenceUpdate>? _presenceSubscription;

  PresenceService({required this.facade}) {
    _presenceSubscription = facade.peerPresenceStream.listen((update) {
      _peerOnline[update.peerId] = update.isOnline;
      if (update.isOnline) {
        _peerLastSeen.remove(update.peerId);
      } else {
        _peerLastSeen[update.peerId] = update.lastSeenAt ?? update.observedAt;
      }
      _updatesController.add(update.peerId);
    });
  }

  Stream<String> get updatesStream => _updatesController.stream;

  bool isPeerOnline(String peerId) => _peerOnline[peerId] ?? false;

  DateTime? peerLastSeenAt(String peerId) => _peerLastSeen[peerId];

  Future<void> dispose() async {
    await _presenceSubscription?.cancel();
    await _updatesController.close();
  }
}
