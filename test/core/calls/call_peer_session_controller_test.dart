import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_media_stream_controller.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_peer_session_controller.dart';
import 'package:peerlink/core/calls/call_video_state.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

class _DummyPeerConnection implements RTCPeerConnection {
  RTCSignalingState _signalingState;
  RTCSessionDescription? _localDescription;
  RTCSessionDescription? _remoteDescription;
  final List<Map<String, dynamic>> createOfferConstraints =
      <Map<String, dynamic>>[];
  bool throwOnGetLocalDescriptionWhenNull;

  _DummyPeerConnection({
    required RTCSignalingState signalingState,
    RTCSessionDescription? localDescription,
    this.throwOnGetLocalDescriptionWhenNull = false,
  }) : _signalingState = signalingState,
       _localDescription = localDescription;

  @override
  Future<RTCSessionDescription> createAnswer([
    Map<String, dynamic> constraints = const <String, dynamic>{},
  ]) async {
    return RTCSessionDescription('v=0\r\n', 'answer');
  }

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic> constraints = const <String, dynamic>{},
  ]) async {
    createOfferConstraints.add(Map<String, dynamic>.from(constraints));
    return RTCSessionDescription('v=0\r\n', 'offer');
  }

  @override
  Future<void> addCandidate(RTCIceCandidate candidate) async {}

  @override
  Future<RTCSessionDescription?> getLocalDescription() async {
    if (throwOnGetLocalDescriptionWhenNull && _localDescription == null) {
      throw Exception('local description is null');
    }
    return _localDescription;
  }

  @override
  Future<RTCSessionDescription?> getRemoteDescription() async {
    return _remoteDescription;
  }

  @override
  Future<RTCSignalingState?> getSignalingState() async {
    return _signalingState;
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    _localDescription = description;
    _signalingState = RTCSignalingState.RTCSignalingStateStable;
  }

  @override
  Future<void> setRemoteDescription(RTCSessionDescription description) async {
    _remoteDescription = description;
    if (description.type == 'offer') {
      _signalingState = RTCSignalingState.RTCSignalingStateHaveRemoteOffer;
    } else if (description.type == 'answer') {
      _signalingState = RTCSignalingState.RTCSignalingStateStable;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSignalingService implements SignalingService {
  final List<Map<String, dynamic>> sentAnswers = <Map<String, dynamic>>[];

  @override
  SignalingConnectionStatus get connectionStatus =>
      SignalingConnectionStatus.connected;

  @override
  String? get lastError => null;

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      const Stream<SignalingConnectionStatus>.empty();

  @override
  Stream<String?> get lastErrorStream => const Stream<String?>.empty();

  @override
  Stream<SignalingMessage> get messages =>
      const Stream<SignalingMessage>.empty();

  @override
  Stream<List<String>> get peersStream => const Stream<List<String>>.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> configureServers(List<String> endpoints) async {}

  @override
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) async {
    sentAnswers.add(<String, dynamic>{'peerId': peerId, 'answer': answer});
  }

  @override
  Future<void> sendIce(String peerId, Map<String, dynamic> candidate) async {}

  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) async {}

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {}

  @override
  Future<void> setServer(String endpoint) async {}
}

CallPeerSessionController _buildController({
  required SignalingService signaling,
  required RTCPeerConnection peer,
  required void Function() armPostIceRecoveryFlowWatch,
  void Function(String reason)? resetPostIceRecoveryFlowWatch,
  CallMediaType initialMediaType = CallMediaType.audio,
  void Function()? cancelIceRecoveryTimers,
  Future<void> Function()? syncLocalMediaTracks,
  Future<void> Function()? refreshVideoChannelHandles,
  Future<void> Function()? ensureVideoTransceiverDirectionsForRole,
}) {
  final videoState = CallVideoState();
  TransportMode? mode = TransportMode.turn;
  var mediaType = initialMediaType;
  var remoteDescriptionSet = true;
  final pendingIce = <RTCIceCandidate>[];

  return CallPeerSessionController(
    signaling: signaling,
    videoState: videoState,
    log: (_) {},
    onError: (_) {},
    onRemoteVideoTrackChanged: (_) {},
    onVideoCodecChanged: (_) {},
    getPeer: () => peer,
    setPeer: (_) {},
    setPeerId: (_) {},
    setCallId: (_) {},
    getMode: () => mode,
    setMode: (value) => mode = value,
    getMediaType: () => mediaType,
    setMediaType: (value) => mediaType = value,
    setStartedAsOfferer: (_) {},
    getRemoteDescriptionSet: () => remoteDescriptionSet,
    setRemoteDescriptionSet: (value) => remoteDescriptionSet = value,
    setIceConnected: (_) {},
    setRemoteTrackSeen: (_) {},
    setRemoteAudioTrackSeen: (_) {},
    setRemoteAudioFlowSeen: (_) {},
    setRemoteVideoTrackSeen: (_) {},
    setConnected: (_) {},
    setMediaFlowNotified: (_) {},
    setRenegotiationInProgress: (_) {},
    setPendingRenegotiationReason: (_) {},
    getPendingIce: () => pendingIce,
    setPendingRemoteVideoFlowAckVersion: (_) {},
    setRemoteVideoEnabled: (_) {},
    setRemoteVideoFlowSeen: (_) {},
    mediaStreamController: CallMediaStreamController(
      log: (_) {},
      onLocalStream: (_) {},
      onRemoteStream: (_) {},
    ),
    buildRtcConfig: (_) async => <String, dynamic>{},
    bindPeerEvents: (_) {},
    getMuted: () => false,
    getSpeakerOn: () => false,
    getStartedAsOfferer: () => false,
    applySpeakerOn: (_) async {},
    syncLocalMediaTracks: syncLocalMediaTracks ?? () async {},
    refreshVideoChannelHandles: refreshVideoChannelHandles ?? () async {},
    ensureVideoTransceiverDirectionsForRole:
        ensureVideoTransceiverDirectionsForRole ?? () async {},
    withPreferredVideoCodecs: (description) => description,
    captureExpectedVideoMidsForLocalOffer: (_) {},
    captureExpectedVideoMidsForRemoteOffer: (_) {},
    captureExpectedVideoMidsForRemoteAnswer: (_) {},
    updateNegotiatedVideoCodec: (_) {},
    armPostIceRecoveryFlowWatch: armPostIceRecoveryFlowWatch,
    resetPostIceRecoveryFlowWatch: resetPostIceRecoveryFlowWatch ?? (_) {},
    stopAudioStatsPolling: () {},
    cancelMediaFlowFallback: () {},
    cancelIceRecoveryTimers: cancelIceRecoveryTimers ?? () {},
    cancelVideoUplinkFallback: () {},
    cancelRemoteVideoFlowRecovery: () {},
    cancelPendingVideoStateAck: () {},
    cancelVideoQualityUpgrade: () {},
    disposeRemoteStream: () async {},
    clearRemoteRenderStreamTracks: () async {},
    resetLocalVideoAttachment: () {},
    closePeer: () async {},
    clearVideoTransports: () {},
    parseMode: (_) => TransportMode.turn,
    bumpSessionEpoch: () {},
  );
}

void main() {
  group('CallPeerSessionController', () {
    test(
      'arms transport watch after incoming recovery offer is answered',
      () async {
        final signaling = _FakeSignalingService();
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescription: RTCSessionDescription('v=0\r\n', 'answer'),
        );
        var armCount = 0;
        final controller = _buildController(
          signaling: signaling,
          peer: peer,
          armPostIceRecoveryFlowWatch: () {
            armCount++;
          },
        );

        await controller.handleSignal(
          SignalingMessage(
            type: 'offer',
            fromPeerId: 'peer-b',
            toPeerId: 'peer-a',
            data: <String, dynamic>{
              'callId': 'call-1',
              'type': 'offer',
              'sdp': 'v=0\r\n',
              'transportMode': 'turn',
              'mediaType': 'audio',
            },
          ),
        );

        expect(signaling.sentAnswers, hasLength(1));
        expect(armCount, 1);
      },
    );

    test(
      'incoming same-session recovery offer keeps ice recovery and skips queued restart drain',
      () async {
        final signaling = _FakeSignalingService();
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescription: RTCSessionDescription('v=0\r\n', 'answer'),
        );
        var cancelCount = 0;
        var resetCount = 0;
        final controller = _buildController(
          signaling: signaling,
          peer: peer,
          armPostIceRecoveryFlowWatch: () {},
          cancelIceRecoveryTimers: () {
            cancelCount++;
          },
          resetPostIceRecoveryFlowWatch: (_) {
            resetCount++;
          },
        );

        await controller.handleSignal(
          SignalingMessage(
            type: 'offer',
            fromPeerId: 'peer-b',
            toPeerId: 'peer-a',
            data: <String, dynamic>{
              'callId': 'call-1',
              'type': 'offer',
              'sdp': 'v=0\r\n',
              'transportMode': 'turn',
              'mediaType': 'audio',
            },
          ),
        );

        expect(signaling.sentAnswers, hasLength(1));
        expect(cancelCount, 0);
        expect(resetCount, 1);
      },
    );

    test(
      'video answer reapplies transceiver directions after local media sync',
      () async {
        final signaling = _FakeSignalingService();
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescription: RTCSessionDescription('v=0\r\n', 'answer'),
        );
        final order = <String>[];
        final controller = _buildController(
          signaling: signaling,
          peer: peer,
          initialMediaType: CallMediaType.video,
          armPostIceRecoveryFlowWatch: () {},
          syncLocalMediaTracks: () async {
            order.add('sync');
          },
          refreshVideoChannelHandles: () async {
            order.add('refresh');
          },
          ensureVideoTransceiverDirectionsForRole: () async {
            order.add('directions');
          },
        );

        await controller.handleSignal(
          SignalingMessage(
            type: 'offer',
            fromPeerId: 'peer-b',
            toPeerId: 'peer-a',
            data: <String, dynamic>{
              'callId': 'call-1',
              'type': 'offer',
              'sdp': 'v=0\r\n',
              'transportMode': 'turn',
              'mediaType': 'video',
            },
          ),
        );

        expect(signaling.sentAnswers, hasLength(1));
        expect(
          order,
          containsAllInOrder(<String>[
            'directions',
            'sync',
            'refresh',
            'directions',
          ]),
        );
      },
    );

    test(
      'incoming offer still sends answer when local description read throws before answer',
      () async {
        final signaling = _FakeSignalingService();
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          throwOnGetLocalDescriptionWhenNull: true,
        );
        final controller = _buildController(
          signaling: signaling,
          peer: peer,
          armPostIceRecoveryFlowWatch: () {},
        );

        await controller.handleSignal(
          SignalingMessage(
            type: 'offer',
            fromPeerId: 'peer-b',
            toPeerId: 'peer-a',
            data: <String, dynamic>{
              'callId': 'call-1',
              'type': 'offer',
              'sdp': 'v=0\r\n',
              'transportMode': 'turn',
              'mediaType': 'audio',
            },
          ),
        );

        expect(signaling.sentAnswers, hasLength(1));
      },
    );

    test('arms transport watch after answer is applied', () async {
      final peer = _DummyPeerConnection(
        signalingState: RTCSignalingState.RTCSignalingStateHaveLocalOffer,
        localDescription: RTCSessionDescription('v=0\r\n', 'offer'),
      );
      var armCount = 0;
      var resetCount = 0;
      final controller = _buildController(
        signaling: _FakeSignalingService(),
        peer: peer,
        armPostIceRecoveryFlowWatch: () {
          armCount++;
        },
        resetPostIceRecoveryFlowWatch: (_) {
          resetCount++;
        },
      );

      await controller.handleSignal(
        SignalingMessage(
          type: 'answer',
          fromPeerId: 'peer-b',
          toPeerId: 'peer-a',
          data: <String, dynamic>{
            'callId': 'call-1',
            'type': 'answer',
            'sdp': 'v=0\r\n',
            'transportMode': 'turn',
            'mediaType': 'audio',
          },
        ),
      );

      expect(armCount, 1);
      expect(resetCount, 0);
    });

    test(
      'startOutgoing keeps audio offer without video receive flag',
      () async {
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
        );
        final controller = _buildController(
          signaling: _FakeSignalingService(),
          peer: peer,
          armPostIceRecoveryFlowWatch: () {},
        );

        await controller.startOutgoing(
          peerId: 'peer-b',
          callId: 'call-1',
          mode: TransportMode.turn,
          mediaType: CallMediaType.audio,
        );

        expect(peer.createOfferConstraints, hasLength(1));
        expect(
          peer.createOfferConstraints.single['offerToReceiveVideo'],
          isFalse,
        );
      },
    );
  });
}
