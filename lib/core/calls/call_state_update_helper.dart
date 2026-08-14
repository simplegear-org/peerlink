// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_models.dart';

class CallStatsUpdateResult {
  const CallStatsUpdateResult({
    required this.state,
    required this.statsOffsetSent,
    required this.statsOffsetReceived,
    required this.lastPeerSentBytes,
    required this.lastPeerReceivedBytes,
  });

  final CallState state;
  final int statsOffsetSent;
  final int statsOffsetReceived;
  final int lastPeerSentBytes;
  final int lastPeerReceivedBytes;
}

class CallStateUpdateHelper {
  const CallStateUpdateHelper();

  CallStatsUpdateResult applyPeerStats({
    required CallState currentState,
    required int sentBytes,
    required int receivedBytes,
    required int statsOffsetSent,
    required int statsOffsetReceived,
    required int lastPeerSentBytes,
    required int lastPeerReceivedBytes,
  }) {
    var nextStatsOffsetSent = statsOffsetSent;
    var nextStatsOffsetReceived = statsOffsetReceived;

    if (sentBytes < lastPeerSentBytes) {
      nextStatsOffsetSent += lastPeerSentBytes;
    }
    if (receivedBytes < lastPeerReceivedBytes) {
      nextStatsOffsetReceived += lastPeerReceivedBytes;
    }

    final totalSent = nextStatsOffsetSent + sentBytes;
    final totalReceived = nextStatsOffsetReceived + receivedBytes;
    return CallStatsUpdateResult(
      state: currentState.copyWith(
        bytesSent: totalSent,
        bytesReceived: totalReceived,
      ),
      statsOffsetSent: nextStatsOffsetSent,
      statsOffsetReceived: nextStatsOffsetReceived,
      lastPeerSentBytes: sentBytes,
      lastPeerReceivedBytes: receivedBytes,
    );
  }

  CallState applyRemoteVideoState({
    required CallState currentState,
    required bool enabled,
    required bool Function(MediaStream? stream) streamHasVideo,
  }) {
    return currentState.copyWith(
      remoteVideoEnabled: enabled,
      remoteVideoAvailable: enabled
          ? streamHasVideo(currentState.remoteStream)
          : false,
      remoteVideoActive: enabled ? currentState.remoteVideoActive : false,
      debugStatus: enabled
          ? 'Собеседник включает видео'
          : 'Собеседник выключил видео',
    );
  }
}
