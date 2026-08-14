// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'call_media_stats_utils.dart';

class CallMediaDiagnosticsFormatter {
  const CallMediaDiagnosticsFormatter._();

  static String format(AudioTrafficStats stats) {
    return 'pair=${stats.selectedCandidatePairId ?? "none"} '
        'route=${stats.candidateProtocol ?? "na"} '
        '${stats.localCandidateType ?? "na"}:${stats.localCandidateAddress ?? "na"} '
        '-> ${stats.remoteCandidateType ?? "na"}:${stats.remoteCandidateAddress ?? "na"} '
        'rttMs=${stats.currentRoundTripTimeMs.toStringAsFixed(0)} '
        'outKbps=${stats.availableOutgoingBitrateKbps.toStringAsFixed(0)} '
        'inKbps=${stats.availableIncomingBitrateKbps.toStringAsFixed(0)} '
        'audioLoss=${stats.audioPacketsLost} '
        'videoLoss=${stats.videoPacketsLost} '
        'audioJitterMs=${stats.audioJitterMs.toStringAsFixed(0)} '
        'videoJitterMs=${stats.videoJitterMs.toStringAsFixed(0)} '
        'bytesIn=${stats.receivedBytes} bytesOut=${stats.sentBytes} '
        'audioBytesOut=${stats.audioSentBytes} '
        'videoBytes=${stats.videoBytesReceived} '
        'videoFrames=${stats.videoFramesDecoded}';
  }

  static int delta(int current, int previous) {
    if (previous < 0) {
      return 0;
    }
    return current - previous;
  }
}
