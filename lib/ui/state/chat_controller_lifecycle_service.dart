import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/node/node_facade.dart';
import 'chat_controller_models.dart';

class ChatControllerLifecycleService {
  ChatControllerLifecycleService({
    required NodeFacade facade,
    required void Function(String peerId, ChatConnectionStatus status)
    setPeerStatus,
    required void Function() syncBadgeCount,
    required void Function(String message) logQueue,
    required void Function() resumeRecoverableFileQueue,
    required Future<void> Function({required String reason})
    resumePendingOutgoingRelayMedia,
    required Future<void> Function({required String reason})
    resumeInterruptedIncomingMediaQueue,
  }) : _facade = facade,
       _setPeerStatus = setPeerStatus,
       _syncBadgeCount = syncBadgeCount,
       _logQueue = logQueue,
       _resumeRecoverableFileQueue = resumeRecoverableFileQueue,
       _resumePendingOutgoingRelayMedia = resumePendingOutgoingRelayMedia,
       _resumeInterruptedIncomingMediaQueue =
           resumeInterruptedIncomingMediaQueue;

  final NodeFacade _facade;
  final void Function(String peerId, ChatConnectionStatus status)
  _setPeerStatus;
  final void Function() _syncBadgeCount;
  final void Function(String message) _logQueue;
  final void Function() _resumeRecoverableFileQueue;
  final Future<void> Function({required String reason})
  _resumePendingOutgoingRelayMedia;
  final Future<void> Function({required String reason})
  _resumeInterruptedIncomingMediaQueue;

  StreamSubscription<String>? _peerConnectedSub;
  StreamSubscription<String>? _peerDisconnectedSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void start() {
    _peerConnectedSub = _facade.peerConnectedStream.listen((peerId) {
      _setPeerStatus(peerId, ChatConnectionStatus.connected);
    });
    _peerDisconnectedSub = _facade.peerDisconnectedStream.listen((peerId) {
      _setPeerStatus(peerId, ChatConnectionStatus.disconnected);
    });
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (!_hasNetworkConnectivity(results)) {
        return;
      }
      unawaited(_facade.pollRelay());
      unawaited(_resumePendingOutgoingRelayMedia(reason: 'connectivity'));
      unawaited(_resumeInterruptedIncomingMediaQueue(reason: 'connectivity'));
    });
  }

  void handleAppResumed() {
    _syncBadgeCount();
    _logQueue('resume app lifecycle');
    _resumeRecoverableFileQueue();
    unawaited(_facade.pollRelay());
    unawaited(_resumePendingOutgoingRelayMedia(reason: 'app-resume'));
    unawaited(_resumeInterruptedIncomingMediaQueue(reason: 'app-resume'));
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    await _peerConnectedSub?.cancel();
    await _peerDisconnectedSub?.cancel();
  }

  bool _hasNetworkConnectivity(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn ||
          result == ConnectivityResult.other,
    );
  }
}
