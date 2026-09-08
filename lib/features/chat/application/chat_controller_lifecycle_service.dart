// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/application/chat_controller_models.dart';

class ChatControllerLifecycleService {
  ChatControllerLifecycleService({
    this.retryModerationReports,
    required ChatRuntimeApi facade,
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

  final ChatRuntimeApi _facade;
  final Future<void> Function()? retryModerationReports;

  Future<void> _retryReports() async {
    try {
      await retryModerationReports?.call();
    } catch (error) {
      _logQueue('moderation retry deferred: $error');
    }
  }

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
    unawaited(_retryReports());
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
      unawaited(_retryReports());
      unawaited(_facade.pollRelay());
      unawaited(_resumePendingOutgoingRelayMedia(reason: 'connectivity'));
      unawaited(_resumeInterruptedIncomingMediaQueue(reason: 'connectivity'));
    });
  }

  void handleAppResumed() {
    unawaited(_retryReports());
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
