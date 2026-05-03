import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'call_models.dart';

class CallNegotiationController {
  final SignalingService _signaling;
  final TurnAllocator? _turnAllocator;
  final void Function(String message) _log;
  final void Function(String? codec) _onVideoCodecChanged;
  final String Function(String sdp, List<String> preferred) _rewriteVideoCodecs;
  final String? Function(String? sdp) _extractVideoCodec;
  final void Function(TurnCredentials? creds) _onTurnCredentialsAllocated;

  final RTCPeerConnection? Function() _getPeer;
  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final TransportMode? Function() _getMode;
  final CallMediaType Function() _getMediaType;
  final bool Function() _getConnected;
  final bool Function() _getRemoteDescriptionSet;
  final bool Function() _getIceRestartInProgress;
  final void Function(bool value) _setIceRestartInProgress;
  final bool Function() _getRenegotiationInProgress;
  final String? Function() _getPendingIceRestartReason;
  final void Function(String? value) _setPendingIceRestartReason;

  const CallNegotiationController({
    required SignalingService signaling,
    required TurnAllocator? turnAllocator,
    required void Function(String message) log,
    required void Function(String? codec) onVideoCodecChanged,
    required String Function(String sdp, List<String> preferred) rewriteVideoCodecs,
    required String? Function(String? sdp) extractVideoCodec,
    required void Function(TurnCredentials? creds) onTurnCredentialsAllocated,
    required RTCPeerConnection? Function() getPeer,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required TransportMode? Function() getMode,
    required CallMediaType Function() getMediaType,
    required bool Function() getConnected,
    required bool Function() getRemoteDescriptionSet,
    required bool Function() getIceRestartInProgress,
    required void Function(bool value) setIceRestartInProgress,
    required bool Function() getRenegotiationInProgress,
    required String? Function() getPendingIceRestartReason,
    required void Function(String? value) setPendingIceRestartReason,
  })  : _signaling = signaling,
        _turnAllocator = turnAllocator,
        _log = log,
        _onVideoCodecChanged = onVideoCodecChanged,
        _rewriteVideoCodecs = rewriteVideoCodecs,
        _extractVideoCodec = extractVideoCodec,
        _onTurnCredentialsAllocated = onTurnCredentialsAllocated,
        _getPeer = getPeer,
        _getPeerId = getPeerId,
        _getCallId = getCallId,
        _getMode = getMode,
        _getMediaType = getMediaType,
        _getConnected = getConnected,
        _getRemoteDescriptionSet = getRemoteDescriptionSet,
        _getIceRestartInProgress = getIceRestartInProgress,
        _setIceRestartInProgress = setIceRestartInProgress,
        _getRenegotiationInProgress = getRenegotiationInProgress,
        _getPendingIceRestartReason = getPendingIceRestartReason,
        _setPendingIceRestartReason = setPendingIceRestartReason;

  Future<void> runRenegotiation(String reason) async {
    final peer = _getPeer();
    final peerId = _getPeerId();
    final callId = _getCallId();
    final mode = _getMode();
    if (peer == null || peerId == null || callId == null || mode == null) {
      _log('renegotiation:skip unavailable reason="$reason"');
      return;
    }

    final signalingState = await peer.getSignalingState();
    if (signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      _log('renegotiation:skip pending-local-offer reason="$reason"');
      return;
    }

    _log(
      'renegotiation:start reason="$reason" mode=${mode.name} '
      'connected=${_getConnected()} remoteDescriptionSet=${_getRemoteDescriptionSet()}',
    );
    try {
      final offer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peer.setLocalDescription(offer);
      await _signaling.sendOffer(peerId, {
        ...offer.toMap(),
        'callId': callId,
        'signalScope': 'call',
        'transportMode': mode.name,
        'mediaType': _getMediaType().name,
      });
      _log('renegotiation:offer sent mode=${mode.name}');
    } catch (error) {
      _log('renegotiation:failed error=$error');
    }
  }

  Future<Map<String, dynamic>> buildRtcConfig(TransportMode mode) async {
    final iceServers = <Map<String, dynamic>>[];

    if (mode == TransportMode.turn) {
      await _turnAllocator?.refreshSelectionIfNeeded();
      final turnCredentials = _turnAllocator?.allocateAll() ?? const <TurnCredentials>[];
      if (turnCredentials.isEmpty) {
        throw Exception('TURN mode selected but no TURN available');
      }
      _onTurnCredentialsAllocated(turnCredentials.first);
      final configuredUrls = <String>[];
      for (final creds in turnCredentials) {
        final urls = creds.url
            .split(';')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        configuredUrls.addAll(urls);
        iceServers.add({
          'urls': urls,
          'username': creds.username,
          'credential': creds.password,
          'tlsCertPolicy': 'insecureNoCheck',
          'skpStrictTlsChecking': true,
        });
      }
      _log(
        'rtcConfig turn urls=${configuredUrls.join(',')} '
        'servers=${turnCredentials.length} username=${turnCredentials.first.username}',
      );
    } else {
      _onTurnCredentialsAllocated(null);
      // Direct mode: use STUN only
      iceServers.add({'urls': ['stun:stun.l.google.com:19302']});
    }

    final config = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };
    if (mode == TransportMode.turn) {
      config['iceTransportPolicy'] = 'relay';
    }
    _log(
      'rtcConfig mode=${mode.name} policy=${config['iceTransportPolicy'] ?? 'all'} servers=${iceServers.length}',
    );
    return config;
  }

  RTCSessionDescription withPreferredVideoCodecs(RTCSessionDescription description) {
    final sdp = description.sdp;
    if (sdp == null || sdp.isEmpty) {
      return description;
    }
    final rewritten = _rewriteVideoCodecs(sdp, const <String>['H264', 'VP8']);
    return RTCSessionDescription(rewritten, description.type);
  }

  void updateNegotiatedVideoCodec(String? sdp) {
    final codec = _extractVideoCodec(sdp);
    _onVideoCodecChanged(codec);
    if (codec != null) {
      _log('video:codec selected=$codec');
    }
  }

  Future<void> triggerIceRestart(String reason) async {
    if (_getIceRestartInProgress()) {
      _log('ice:restart skip already in progress reason="$reason"');
      return;
    }
    if (_getRenegotiationInProgress()) {
      _setPendingIceRestartReason(reason);
      _log('ice:restart queued renegotiation-in-progress reason="$reason"');
      return;
    }

    final peer = _getPeer();
    final peerId = _getPeerId();
    final callId = _getCallId();
    final mode = _getMode();
    if (!_getConnected() ||
        peer == null ||
        peerId == null ||
        callId == null ||
        mode == null) {
      _log('ice:restart skip unavailable reason="$reason"');
      return;
    }

    final signalingState = await peer.getSignalingState();
    final localDescriptionType = (await peer.getLocalDescription())?.type;
    if (signalingState != RTCSignalingState.RTCSignalingStateStable ||
        localDescriptionType == 'offer') {
      _setPendingIceRestartReason(reason);
      _log(
        'ice:restart queued pending-signaling '
        'signalingState=$signalingState localDescriptionType=$localDescriptionType '
        'reason="$reason"',
      );
      return;
    }

    _setIceRestartInProgress(true);
    _log('ice:restart start reason="$reason" mode=${mode.name}');
    try {
      final offer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
        'iceRestart': true,
      });
      await peer.setLocalDescription(offer);
      await _signaling.sendOffer(peerId, {
        ...offer.toMap(),
        'callId': callId,
        'signalScope': 'call',
        'transportMode': mode.name,
        'mediaType': _getMediaType().name,
      });
      _log('ice:restart offer sent mode=${mode.name}');
    } catch (error) {
      _setIceRestartInProgress(false);
      _log('ice:restart failed error=$error');
    }
  }

  Future<void> drainQueuedIceRestartIfReady() async {
    final pendingReason = _getPendingIceRestartReason();
    final peer = _getPeer();
    if (pendingReason == null || _getIceRestartInProgress() || peer == null) {
      return;
    }
    final signalingState = await peer.getSignalingState();
    final localDescriptionType = (await peer.getLocalDescription())?.type;
    if (signalingState != RTCSignalingState.RTCSignalingStateStable ||
        localDescriptionType == 'offer') {
      return;
    }
    _setPendingIceRestartReason(null);
    await triggerIceRestart(pendingReason);
  }

  TransportMode? parseMode(dynamic raw) {
    if (raw is! String) {
      return null;
    }
    if (raw == TransportMode.turn.name) {
      return TransportMode.turn;
    }
    return TransportMode.direct;
  }
}
