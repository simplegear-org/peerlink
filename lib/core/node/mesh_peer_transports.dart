import '../transport/transport_mode.dart';
import '../transport/webrtc_transport.dart';

class MeshPeerTransports {
  final WebRtcTransport direct;

  MeshPeerTransports({
    required this.direct,
  });

  WebRtcTransport? byMode(TransportMode mode) {
    if (mode == TransportMode.direct) {
      return direct;
    }

    return null;
  }
}
