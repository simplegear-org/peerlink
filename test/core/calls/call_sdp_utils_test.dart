import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_sdp_utils.dart';

void main() {
  group('preferVideoCodecsInSdp', () {
    test('moves VP8 ahead of H264 when both are present', () {
      const sdp =
          'v=0\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 102 96 97\r\n'
          'a=rtpmap:96 H264/90000\r\n'
          'a=rtpmap:97 rtx/90000\r\n'
          'a=rtpmap:102 VP8/90000\r\n';

      final rewritten = preferVideoCodecsInSdp(sdp, const <String>[
        'VP8',
        'H264',
      ]);

      expect(rewritten, contains('m=video 9 UDP/TLS/RTP/SAVPF 102 96 97'));
    });
  });

  group('sdpMediaSummary', () {
    test('summarizes media sections without logging full sdp', () {
      const sdp =
          'v=0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:1\r\n'
          'a=recvonly\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:2\r\n'
          'a=inactive\r\n';

      expect(
        sdpMediaSummary(sdp),
        'audioM=1 videoM=2 sections=[audio:mid=0:sendrecv,video:mid=1:recvonly,video:mid=2:inactive]',
      );
    });
  });
}
