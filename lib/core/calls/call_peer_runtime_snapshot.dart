import '../transport/transport_mode.dart';
import 'call_models.dart';

class CallPeerRuntimeSnapshot {
  const CallPeerRuntimeSnapshot({
    required bool Function() hasPeer,
    required bool Function() getConnected,
    required bool Function() getIceConnected,
    required CallMediaType Function() getMediaType,
    required bool Function() getMuted,
    required bool Function() getRemoteAudioTrackSeen,
    required bool Function() getRemoteAudioFlowSeen,
    required bool Function() getRemoteAudioMuted,
    required bool Function() getRemoteVideoTrackSeen,
    required bool Function() getRemoteVideoEnabled,
    required bool Function() getRemoteVideoFlowSeen,
    required bool Function() getRenegotiationInProgress,
    required String Function() getSignalingStateLabel,
    TransportMode? Function()? getTransportMode,
  }) : _hasPeer = hasPeer,
       _getConnected = getConnected,
       _getIceConnected = getIceConnected,
       _getMediaType = getMediaType,
       _getMuted = getMuted,
       _getRemoteAudioTrackSeen = getRemoteAudioTrackSeen,
       _getRemoteAudioFlowSeen = getRemoteAudioFlowSeen,
       _getRemoteAudioMuted = getRemoteAudioMuted,
       _getRemoteVideoTrackSeen = getRemoteVideoTrackSeen,
       _getRemoteVideoEnabled = getRemoteVideoEnabled,
       _getRemoteVideoFlowSeen = getRemoteVideoFlowSeen,
       _getRenegotiationInProgress = getRenegotiationInProgress,
       _getSignalingStateLabel = getSignalingStateLabel,
       _getTransportMode = getTransportMode;

  final bool Function() _hasPeer;
  final bool Function() _getConnected;
  final bool Function() _getIceConnected;
  final CallMediaType Function() _getMediaType;
  final bool Function() _getMuted;
  final bool Function() _getRemoteAudioTrackSeen;
  final bool Function() _getRemoteAudioFlowSeen;
  final bool Function() _getRemoteAudioMuted;
  final bool Function() _getRemoteVideoTrackSeen;
  final bool Function() _getRemoteVideoEnabled;
  final bool Function() _getRemoteVideoFlowSeen;
  final bool Function() _getRenegotiationInProgress;
  final String Function() _getSignalingStateLabel;
  final TransportMode? Function()? _getTransportMode;

  String format() {
    final mode = _getTransportMode?.call();
    final modePart = mode == null ? '' : ' mode=${mode.name}';
    return 'peer=${_hasPeer()} connected=${_getConnected()} '
        'iceConnected=${_getIceConnected()}$modePart '
        'media=${_getMediaType().name} muted=${_getMuted()} '
        'remoteAudioTrack=${_getRemoteAudioTrackSeen()} '
        'remoteAudioFlow=${_getRemoteAudioFlowSeen()} '
        'remoteAudioMuted=${_getRemoteAudioMuted()} '
        'remoteVideoTrack=${_getRemoteVideoTrackSeen()} '
        'remoteVideoEnabled=${_getRemoteVideoEnabled()} '
        'remoteVideoFlow=${_getRemoteVideoFlowSeen()} '
        'renegotiation=${_getRenegotiationInProgress()} '
        'signaling=${_getSignalingStateLabel()}';
  }
}
