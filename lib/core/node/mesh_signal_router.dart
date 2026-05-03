import '../calls/call_service.dart';
import '../signaling/signaling_message.dart';
import '../transport/transport_mode.dart';
import 'mesh_peer_transports.dart';

class MeshSignalRouter {
  final String selfPeerId;
  final CallService calls;
  final Future<void> Function(
    String peerId, {
    required bool initiateDial,
  })
  ensurePeerSession;
  final MeshPeerTransports? Function(String peerId) getPeerTransports;
  final void Function(String message) log;

  const MeshSignalRouter({
    required this.selfPeerId,
    required this.calls,
    required this.ensurePeerSession,
    required this.getPeerTransports,
    required this.log,
  });

  Future<void> handleSignalingMessage(SignalingMessage msg) async {
    if (msg.toPeerId != selfPeerId) {
      log('signal:drop to=${msg.toPeerId}');
      return;
    }

    final peerId = msg.fromPeerId;
    log('signal:recv type=${msg.type} from=$peerId');

    if (_isCallControlSignal(msg.type)) {
      await calls.handleControlSignal(msg);
      return;
    }

    if (_signalScope(msg) == 'call') {
      await calls.handleMediaSignal(msg);
      return;
    }

    if (calls.state.isBusy) {
      log('signal:drop non-call during active call type=${msg.type} from=$peerId');
      return;
    }

    await ensurePeerSession(peerId, initiateDial: false);
    final transports = getPeerTransports(peerId);
    if (transports == null) {
      log('signal:drop no transports for=$peerId');
      return;
    }

    final mode = _resolveTransportMode(msg);
    if (mode == null) {
      log('signal:drop unsupported transport mode type=${msg.type}');
      return;
    }
    final target = transports.byMode(mode);
    if (target == null) {
      log('signal:drop no target mode=$mode for=$peerId');
      return;
    }

    log('signal:dispatch mode=$mode to=$peerId');
    await target.handleSignal(msg);
  }

  bool _isCallControlSignal(String type) {
    return type == 'call_invite' ||
        type == 'call_accept' ||
        type == 'call_reject' ||
        type == 'call_end' ||
        type == 'call_busy' ||
        type == 'call_media_ready' ||
        type == 'call_video_state' ||
        type == 'call_video_state_ack' ||
        type == 'call_video_flow_ack';
  }

  String _signalScope(SignalingMessage msg) {
    final raw = msg.data['signalScope'];
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    return 'transport';
  }

  TransportMode? _resolveTransportMode(SignalingMessage msg) {
    final raw = msg.data['transportMode'];
    if (raw is String) {
      if (raw == TransportMode.direct.name) {
        log('signal:transportMode=$raw');
        return TransportMode.direct;
      }
      log('signal:transportMode unsupported=$raw');
      return null;
    }

    log('signal:transportMode=default direct');
    return TransportMode.direct;
  }
}
