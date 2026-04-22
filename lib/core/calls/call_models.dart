import '../transport/transport_mode.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum CallDirection {
  incoming,
  outgoing,
}

enum CallMediaType {
  audio,
  video,
}

enum CallPhase {
  idle,
  outgoingRinging,
  incomingRinging,
  connecting,
  active,
  ended,
  failed,
}

class CallState {
  final CallPhase phase;
  final String? callId;
  final String? peerId;
  final CallDirection? direction;
  final CallMediaType mediaType;
  final bool isMuted;
  final bool speakerOn;
  final TransportMode? transportMode;
  final String? transportLabel;
  final String? debugStatus;
  final String? error;
  final DateTime? connectedAt;
  final int bytesSent;
  final int bytesReceived;
  final bool localVideoEnabled;
  final bool localVideoAvailable;
  final bool remoteVideoEnabled;
  final bool remoteVideoAvailable;
  final bool remoteVideoActive;
  final String? remoteVideoTrackId;
  final String? videoCodec;
  final bool videoToggleInProgress;
  final bool isFrontCamera;
  final MediaStream? localStream;
  final MediaStream? remoteStream;

  const CallState({
    required this.phase,
    this.callId,
    this.peerId,
    this.direction,
    this.mediaType = CallMediaType.audio,
    this.isMuted = false,
    this.speakerOn = false,
    this.transportMode,
    this.transportLabel,
    this.debugStatus,
    this.error,
    this.connectedAt,
    this.bytesSent = 0,
    this.bytesReceived = 0,
    this.localVideoEnabled = false,
    this.localVideoAvailable = false,
    this.remoteVideoEnabled = false,
    this.remoteVideoAvailable = false,
    this.remoteVideoActive = false,
    this.remoteVideoTrackId,
    this.videoCodec,
    this.videoToggleInProgress = false,
    this.isFrontCamera = true,
    this.localStream,
    this.remoteStream,
  });

  static const CallState idle = CallState(phase: CallPhase.idle);

  bool get isIdle => phase == CallPhase.idle;
  bool get isIncoming => phase == CallPhase.incomingRinging;
  bool get isOutgoing => phase == CallPhase.outgoingRinging;
  bool get isConnecting => phase == CallPhase.connecting;
  bool get isActive => phase == CallPhase.active;
  bool get isBusy => isIncoming || isOutgoing || isConnecting || isActive;

  CallState copyWith({
    CallPhase? phase,
    String? callId,
    String? peerId,
    CallDirection? direction,
    CallMediaType? mediaType,
    bool? isMuted,
    bool? speakerOn,
    TransportMode? transportMode,
    String? transportLabel,
    String? debugStatus,
    String? error,
    DateTime? connectedAt,
    int? bytesSent,
    int? bytesReceived,
    bool? localVideoEnabled,
    bool? localVideoAvailable,
    bool? remoteVideoEnabled,
    bool? remoteVideoAvailable,
    bool? remoteVideoActive,
    String? remoteVideoTrackId,
    String? videoCodec,
    bool? videoToggleInProgress,
    bool? isFrontCamera,
    MediaStream? localStream,
    MediaStream? remoteStream,
    bool clearCallId = false,
    bool clearPeerId = false,
    bool clearTransportMode = false,
    bool clearTransportLabel = false,
    bool clearDebugStatus = false,
    bool clearError = false,
    bool clearConnectedAt = false,
    bool clearRemoteVideoTrackId = false,
    bool clearVideoCodec = false,
    bool clearLocalStream = false,
    bool clearRemoteStream = false,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      callId: clearCallId ? null : (callId ?? this.callId),
      peerId: clearPeerId ? null : (peerId ?? this.peerId),
      direction: direction ?? this.direction,
      mediaType: mediaType ?? this.mediaType,
      isMuted: isMuted ?? this.isMuted,
      speakerOn: speakerOn ?? this.speakerOn,
      transportMode: clearTransportMode
          ? null
          : (transportMode ?? this.transportMode),
      transportLabel: clearTransportLabel
          ? null
          : (transportLabel ?? this.transportLabel),
      debugStatus: clearDebugStatus ? null : (debugStatus ?? this.debugStatus),
      error: clearError ? null : (error ?? this.error),
      connectedAt: clearConnectedAt ? null : (connectedAt ?? this.connectedAt),
      bytesSent: bytesSent ?? this.bytesSent,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      localVideoEnabled: localVideoEnabled ?? this.localVideoEnabled,
      localVideoAvailable: localVideoAvailable ?? this.localVideoAvailable,
      remoteVideoEnabled: remoteVideoEnabled ?? this.remoteVideoEnabled,
      remoteVideoAvailable: remoteVideoAvailable ?? this.remoteVideoAvailable,
      remoteVideoActive: remoteVideoActive ?? this.remoteVideoActive,
      remoteVideoTrackId: clearRemoteVideoTrackId
          ? null
          : (remoteVideoTrackId ?? this.remoteVideoTrackId),
      videoCodec: clearVideoCodec ? null : (videoCodec ?? this.videoCodec),
      videoToggleInProgress:
          videoToggleInProgress ?? this.videoToggleInProgress,
      isFrontCamera: isFrontCamera ?? this.isFrontCamera,
      localStream: clearLocalStream ? null : (localStream ?? this.localStream),
      remoteStream: clearRemoteStream ? null : (remoteStream ?? this.remoteStream),
    );
  }
}
