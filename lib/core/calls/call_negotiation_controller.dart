import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'call_models.dart';
import 'call_recovery_coordinator.dart';
import 'call_sdp_utils.dart';

class CallNegotiationController {
  static const Duration _renegotiationCooldown = Duration(seconds: 3);

  final SignalingService _signaling;
  final TurnAllocator? _turnAllocator;
  final void Function(String message) _log;
  final void Function(String? codec) _onVideoCodecChanged;
  final String Function(String sdp, List<String> preferred) _rewriteVideoCodecs;
  final String? Function(String? sdp) _extractVideoCodec;
  final void Function(TurnCredentials? creds) _onTurnCredentialsAllocated;
  final void Function(String? sdp) _captureExpectedVideoMidsForLocalOffer;

  final RTCPeerConnection? Function() _getPeer;
  final String? Function() _getPeerId;
  final String? Function() _getCallId;
  final TransportMode? Function() _getMode;
  final CallMediaType Function() _getMediaType;
  final bool Function() _getConnected;
  final bool Function() _getRemoteDescriptionSet;
  final Future<CallRecoveryDisposition> Function(
    CallRecoveryObservation observation,
  )
  _observeRecovery;
  DateTime? _lastRenegotiationAt;

  bool _matchesNegotiationSnapshot({
    required RTCPeerConnection peer,
    required String peerId,
    required String callId,
    required TransportMode mode,
  }) {
    return identical(_getPeer(), peer) &&
        _getPeerId() == peerId &&
        _getCallId() == callId &&
        _getMode() == mode;
  }

  CallNegotiationController({
    required SignalingService signaling,
    required TurnAllocator? turnAllocator,
    required void Function(String message) log,
    required void Function(String? codec) onVideoCodecChanged,
    required String Function(String sdp, List<String> preferred)
    rewriteVideoCodecs,
    required String? Function(String? sdp) extractVideoCodec,
    required void Function(TurnCredentials? creds) onTurnCredentialsAllocated,
    required void Function(String? sdp) captureExpectedVideoMidsForLocalOffer,
    required RTCPeerConnection? Function() getPeer,
    required String? Function() getPeerId,
    required String? Function() getCallId,
    required TransportMode? Function() getMode,
    required CallMediaType Function() getMediaType,
    required bool Function() getConnected,
    required bool Function() getRemoteDescriptionSet,
    required Future<CallRecoveryDisposition> Function(
      CallRecoveryObservation observation,
    )
    observeRecovery,
  }) : _signaling = signaling,
       _turnAllocator = turnAllocator,
       _log = log,
       _onVideoCodecChanged = onVideoCodecChanged,
       _rewriteVideoCodecs = rewriteVideoCodecs,
       _extractVideoCodec = extractVideoCodec,
       _onTurnCredentialsAllocated = onTurnCredentialsAllocated,
       _captureExpectedVideoMidsForLocalOffer =
           captureExpectedVideoMidsForLocalOffer,
       _getPeer = getPeer,
       _getPeerId = getPeerId,
       _getCallId = getCallId,
       _getMode = getMode,
       _getMediaType = getMediaType,
       _getConnected = getConnected,
       _getRemoteDescriptionSet = getRemoteDescriptionSet,
       _observeRecovery = observeRecovery;

  void armIceDisconnectedTimer() {
    unawaited(
      _observeRecovery(
        const CallRecoveryObservation(
          kind: CallRecoveryObservationKind.iceDisconnected,
          reason: 'ICE connection disconnected',
        ),
      ),
    );
  }

  void armIceFailureState(String error) {
    unawaited(
      _observeRecovery(
        CallRecoveryObservation(
          kind: CallRecoveryObservationKind.iceFailed,
          reason: error,
        ),
      ),
    );
  }

  void cancelIceRecoveryTimers() {
    unawaited(
      _observeRecovery(
        const CallRecoveryObservation(
          kind: CallRecoveryObservationKind.iceConnected,
          reason: 'ICE recovery timers canceled',
        ),
      ),
    );
  }

  bool _shouldOfferVideo() => _getMediaType() == CallMediaType.video;

  Future<void> runRenegotiation(String reason) async {
    final now = DateTime.now();
    final lastRenegotiationAt = _lastRenegotiationAt;
    if (lastRenegotiationAt != null &&
        now.difference(lastRenegotiationAt) < _renegotiationCooldown) {
      _log('renegotiation:cooldown reason="$reason"');
      return;
    }
    final peer = _getPeer();
    final peerId = _getPeerId();
    final callId = _getCallId();
    final mode = _getMode();
    if (peer == null || peerId == null || callId == null || mode == null) {
      _log('renegotiation:skip unavailable reason="$reason"');
      return;
    }

    final signalingState = await peer.getSignalingState();
    final localDescriptionType = (await peer.getLocalDescription())?.type;
    if (signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      _log(
        'renegotiation:skip pending-local-offer '
        'signalingState=$signalingState localDescriptionType=$localDescriptionType '
        'reason="$reason"',
      );
      return;
    }

    _log(
      'renegotiation:start reason="$reason" mode=${mode.name} '
      'connected=${_getConnected()} remoteDescriptionSet=${_getRemoteDescriptionSet()} '
      'media=${_getMediaType().name} signalingState=$signalingState '
      'localDescriptionType=$localDescriptionType',
    );
    try {
      _lastRenegotiationAt = now;
      final rawOffer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': _shouldOfferVideo(),
      });
      final rawSdp = rawOffer.sdp;
      final offer = rawSdp == null || rawSdp.isEmpty
          ? rawOffer
          : RTCSessionDescription(
              _rewriteVideoCodecs(rawSdp, const <String>['VP8', 'H264']),
              rawOffer.type,
            );
      _log('sdp:renegotiation-offer ${sdpMediaSummary(offer.sdp)}');
      if (!_matchesNegotiationSnapshot(
        peer: peer,
        peerId: peerId,
        callId: callId,
        mode: mode,
      )) {
        _log('renegotiation:abort stale-session after createOffer');
        return;
      }
      await peer.setLocalDescription(offer);
      _captureExpectedVideoMidsForLocalOffer(offer.sdp);
      if (!_matchesNegotiationSnapshot(
        peer: peer,
        peerId: peerId,
        callId: callId,
        mode: mode,
      )) {
        _log('renegotiation:abort stale-session after setLocalDescription');
        return;
      }
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
      final turnCredentials =
          _turnAllocator?.allocateAll() ?? const <TurnCredentials>[];
      if (turnCredentials.isEmpty) {
        throw Exception('TURN mode selected but no TURN available');
      }
      final rawUrls = turnCredentials
          .expand(
            (creds) => creds.url
                .split(';')
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty),
          )
          .toList(growable: false);
      final useTcpOnly = rawUrls.any(_isTcpTurnUrl);
      final droppedUdpUrls = useTcpOnly
          ? rawUrls.where((url) => !_isTcpTurnUrl(url)).length
          : 0;
      final configuredUrls = <String>[];
      final grouped = <String, ({TurnCredentials creds, List<String> urls})>{};
      for (final creds in turnCredentials) {
        final key = '${creds.username}\u0000${creds.password}';
        final entry = grouped.putIfAbsent(
          key,
          () => (creds: creds, urls: <String>[]),
        );
        entry.urls.addAll(
          creds.url
              .split(';')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .where((item) => !useTcpOnly || _isTcpTurnUrl(item)),
        );
      }
      for (final entry in grouped.values) {
        final urls = entry.urls.toSet().toList(growable: false)
          ..sort(_compareTurnUrls);
        if (urls.isEmpty) continue;
        configuredUrls.addAll(urls);
        final server = <String, dynamic>{
          'urls': urls,
          'tlsCertPolicy': 'insecureNoCheck',
          'skpStrictTlsChecking': true,
        };
        final creds = entry.creds;
        if (creds.username.trim().isNotEmpty) {
          server['username'] = creds.username;
        }
        if (creds.password.isNotEmpty) {
          server['credential'] = creds.password;
        }
        iceServers.add(server);
      }
      if (iceServers.isEmpty) {
        throw Exception('TURN mode selected but no TURN URLs available');
      }
      _onTurnCredentialsAllocated(
        TurnCredentials(
          url: configuredUrls.first,
          username: turnCredentials.first.username,
          password: turnCredentials.first.password,
        ),
      );
      _log(
        'rtcConfig turn urls=${configuredUrls.join(',')} tcpOnly=$useTcpOnly '
        'udpDropped=$droppedUdpUrls '
        'servers=${iceServers.length} username=${turnCredentials.first.username} '
        'credentialPresent=${turnCredentials.first.password.isNotEmpty}',
      );
    } else {
      _onTurnCredentialsAllocated(null);
      // Direct mode: use STUN only
      iceServers.add({
        'urls': ['stun:stun.l.google.com:19302'],
      });
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

  RTCSessionDescription withPreferredVideoCodecs(
    RTCSessionDescription description,
  ) {
    final sdp = description.sdp;
    if (sdp == null || sdp.isEmpty) {
      return description;
    }
    final rewritten = _rewriteVideoCodecs(sdp, const <String>['VP8', 'H264']);
    return RTCSessionDescription(rewritten, description.type);
  }

  void updateNegotiatedVideoCodec(String? sdp) {
    final codec = _extractVideoCodec(sdp);
    _onVideoCodecChanged(codec);
    if (codec != null) {
      _log('video:codec selected=$codec');
    }
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

  int _compareTurnUrls(String left, String right) {
    final leftRank = _turnUrlRank(left);
    final rightRank = _turnUrlRank(right);
    if (leftRank != rightRank) {
      return leftRank.compareTo(rightRank);
    }
    return left.compareTo(right);
  }

  int _turnUrlRank(String url) {
    final normalized = url.toLowerCase();
    if (normalized.startsWith('turn:') &&
        normalized.contains('transport=tcp')) {
      return 0;
    }
    if (normalized.startsWith('turns:')) {
      return 1;
    }
    if (normalized.startsWith('turn:') &&
        normalized.contains('transport=udp')) {
      return 2;
    }
    return 3;
  }

  bool _isTcpTurnUrl(String url) {
    final normalized = url.toLowerCase();
    return normalized.startsWith('turns:') ||
        (normalized.startsWith('turn:') &&
            normalized.contains('transport=tcp'));
  }
}
