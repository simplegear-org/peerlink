import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallLocalAudioOutboundRefresher {
  const CallLocalAudioOutboundRefresher({
    required void Function(String message) log,
    required bool Function() getMuted,
    required RTCPeerConnection? Function() getPeer,
    required String Function() runtimeSnapshot,
    required Future<void> Function({
      required RTCPeerConnection peer,
      required bool muted,
      required String reason,
    })
    refreshLocalAudioSender,
  }) : _log = log,
       _getMuted = getMuted,
       _getPeer = getPeer,
       _runtimeSnapshot = runtimeSnapshot,
       _refreshLocalAudioSender = refreshLocalAudioSender;

  final void Function(String message) _log;
  final bool Function() _getMuted;
  final RTCPeerConnection? Function() _getPeer;
  final String Function() _runtimeSnapshot;
  final Future<void> Function({
    required RTCPeerConnection peer,
    required bool muted,
    required String reason,
  })
  _refreshLocalAudioSender;

  Future<void> refresh(String reason) async {
    final muted = _getMuted();
    if (muted) {
      _log(
        'diagnostic:warning audio-sender refresh skipped reason="$reason" '
        'muted=true snapshot=${_runtimeSnapshot()}',
      );
      return;
    }
    final peer = _getPeer();
    if (peer == null) {
      _log(
        'diagnostic:warning audio-sender refresh skipped reason="$reason" '
        'peer=false snapshot=${_runtimeSnapshot()}',
      );
      return;
    }
    _log(
      'diagnostic:warning audio-sender refresh start reason="$reason" '
      'snapshot=${_runtimeSnapshot()}',
    );
    await _refreshLocalAudioSender(peer: peer, muted: muted, reason: reason);
    _log(
      'diagnostic:warning audio-sender refresh finish reason="$reason" '
      'snapshot=${_runtimeSnapshot()}',
    );
  }
}
