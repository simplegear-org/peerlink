import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_media_stats_utils.dart';

void main() {
  group('extractAudioTrafficStats', () {
    test('extracts selected ICE route and media diagnostics', () {
      final reports = <StatsReport>[
        StatsReport('transport-1', 'transport', 0, {
          'selectedCandidatePairId': 'pair-1',
        }),
        StatsReport('pair-1', 'candidate-pair', 0, {
          'state': 'succeeded',
          'localCandidateId': 'local-1',
          'remoteCandidateId': 'remote-1',
          'currentRoundTripTime': 0.184,
          'availableOutgoingBitrate': 2500000,
          'availableIncomingBitrate': 1700000,
        }),
        StatsReport('local-1', 'local-candidate', 0, {
          'candidateType': 'relay',
          'protocol': 'udp',
          'address': '10.0.0.2',
          'port': 50000,
        }),
        StatsReport('remote-1', 'remote-candidate', 0, {
          'candidateType': 'relay',
          'address': '93.184.216.34',
          'port': 3478,
        }),
        StatsReport('audio-in', 'inbound-rtp', 0, {
          'kind': 'audio',
          'bytesReceived': 12000,
          'packetsReceived': 120,
          'packetsLost': 4,
          'audioLevel': 0.34,
          'totalAudioEnergy': 3.5,
          'totalSamplesDuration': 5.5,
          'jitter': 0.012,
        }),
        StatsReport('video-in', 'inbound-rtp', 0, {
          'kind': 'video',
          'bytesReceived': 98000,
          'framesDecoded': 144,
          'packetsLost': 7,
          'jitter': 0.025,
        }),
        StatsReport('audio-out', 'outbound-rtp', 0, {
          'kind': 'audio',
          'bytesSent': 64000,
        }),
        StatsReport('video-out', 'outbound-rtp', 0, {
          'kind': 'video',
          'bytesSent': 36000,
        }),
      ];

      final stats = extractAudioTrafficStats(reports);

      expect(stats.selectedCandidatePairId, 'pair-1');
      expect(stats.localCandidateType, 'relay');
      expect(stats.remoteCandidateType, 'relay');
      expect(stats.candidateProtocol, 'udp');
      expect(stats.localCandidateAddress, '10.0.0.2:50000');
      expect(stats.remoteCandidateAddress, '93.184.216.34:3478');
      expect(stats.currentRoundTripTimeMs, closeTo(184, 0.001));
      expect(stats.availableOutgoingBitrateKbps, closeTo(2500, 0.001));
      expect(stats.availableIncomingBitrateKbps, closeTo(1700, 0.001));
      expect(stats.audioJitterMs, closeTo(12, 0.001));
      expect(stats.videoJitterMs, closeTo(25, 0.001));
      expect(stats.audioPacketsLost, 4);
      expect(stats.videoPacketsLost, 7);
      expect(stats.receivedBytes, 110000);
      expect(stats.sentBytes, 100000);
      expect(stats.audioSentBytes, 64000);
      expect(stats.videoFramesDecoded, 144);
    });
  });
}
