import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_negotiation_controller.dart';
import 'package:peerlink/core/calls/call_recovery_coordinator.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/transport/transport_mode.dart';
import 'package:peerlink/core/turn/turn_allocator.dart';
import 'package:peerlink/core/turn/turn_credentials.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

class _DummyPeerConnection implements RTCPeerConnection {
  RTCSignalingState _signalingState;
  RTCSessionDescription? _localDescription;
  final List<Map<String, dynamic>> createOfferConstraints =
      <Map<String, dynamic>>[];
  RTCSessionDescription createdOffer;

  _DummyPeerConnection({
    RTCSignalingState signalingState =
        RTCSignalingState.RTCSignalingStateStable,
    RTCSessionDescription? localDescription,
    RTCSessionDescription? createdOffer,
  }) : _signalingState = signalingState,
       _localDescription = localDescription,
       createdOffer = createdOffer ?? RTCSessionDescription('v=0\r\n', 'offer');

  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic> constraints = const <String, dynamic>{},
  ]) async {
    createOfferConstraints.add(Map<String, dynamic>.from(constraints));
    return createdOffer;
  }

  @override
  Future<RTCSessionDescription?> getLocalDescription() async {
    return _localDescription;
  }

  @override
  Future<RTCSignalingState?> getSignalingState() async {
    return _signalingState;
  }

  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    _localDescription = description;
    _signalingState = RTCSignalingState.RTCSignalingStateHaveLocalOffer;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSignalingService implements SignalingService {
  final List<Map<String, dynamic>> sentOffers = <Map<String, dynamic>>[];

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
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) async {}

  @override
  Future<void> sendIce(String peerId, Map<String, dynamic> candidate) async {}

  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) async {
    sentOffers.add(<String, dynamic>{'peerId': peerId, 'offer': offer});
  }

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {}

  @override
  Future<void> setServer(String endpoint) async {}
}

CallNegotiationController _buildController({
  required _FakeSignalingService signaling,
  TurnAllocator? turnAllocator,
  required RTCPeerConnection? Function() getPeer,
  required CallMediaType Function() getMediaType,
  required List<String> logs,
  List<CallRecoveryObservation>? observations,
  void Function(TurnCredentials? creds)? onTurnCredentialsAllocated,
  String Function(String sdp, List<String> preferred)? rewriteVideoCodecs,
  void Function(String? sdp)? captureExpectedVideoMidsForLocalOffer,
}) {
  return CallNegotiationController(
    signaling: signaling,
    turnAllocator: turnAllocator,
    log: logs.add,
    onVideoCodecChanged: (_) {},
    rewriteVideoCodecs: rewriteVideoCodecs ?? (sdp, _) => sdp,
    extractVideoCodec: (_) => null,
    onTurnCredentialsAllocated: onTurnCredentialsAllocated ?? (_) {},
    captureExpectedVideoMidsForLocalOffer:
        captureExpectedVideoMidsForLocalOffer ?? (_) {},
    getPeer: getPeer,
    getPeerId: () => 'peer-a',
    getCallId: () => 'call-a',
    getMode: () => TransportMode.turn,
    getMediaType: getMediaType,
    getConnected: () => true,
    getRemoteDescriptionSet: () => true,
    observeRecovery: (observation) async {
      observations?.add(observation);
      return CallRecoveryDisposition.none;
    },
  );
}

void main() {
  group('CallNegotiationController', () {
    test(
      'answerer does not send restart offer on disconnect or grace retry',
      () {
        fakeAsync((async) {
          final signaling = _FakeSignalingService();
          final logs = <String>[];
          final observations = <CallRecoveryObservation>[];

          final controller = _buildController(
            signaling: signaling,
            getPeer: () => null,
            getMediaType: () => CallMediaType.audio,
            logs: logs,
            observations: observations,
          );

          controller.armIceDisconnectedTimer();
          async.flushMicrotasks();
          async.elapse(const Duration(seconds: 7));
          async.flushMicrotasks();

          expect(signaling.sentOffers, isEmpty);
          expect(observations, hasLength(1));
          expect(
            observations.single.kind,
            CallRecoveryObservationKind.iceDisconnected,
          );
        });
      },
    );

    test('disconnect is reported to recovery coordinator', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final logs = <String>[];
        final observations = <CallRecoveryObservation>[];
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescription: RTCSessionDescription('v=0\r\n', 'answer'),
        );

        final controller = _buildController(
          signaling: signaling,
          getPeer: () => peer,
          getMediaType: () => CallMediaType.audio,
          logs: logs,
          observations: observations,
        );

        controller.armIceDisconnectedTimer();
        async.flushMicrotasks();
        expect(signaling.sentOffers, isEmpty);

        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();

        expect(signaling.sentOffers, isEmpty);
        expect(observations, hasLength(1));
        expect(
          observations.single.kind,
          CallRecoveryObservationKind.iceDisconnected,
        );
      });
    });

    test('non-owner also reports disconnect without local restart', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final logs = <String>[];
        final observations = <CallRecoveryObservation>[];
        final peer = _DummyPeerConnection(
          signalingState: RTCSignalingState.RTCSignalingStateStable,
          localDescription: RTCSessionDescription('v=0\r\n', 'answer'),
        );

        final controller = _buildController(
          signaling: signaling,
          getPeer: () => peer,
          getMediaType: () => CallMediaType.audio,
          logs: logs,
          observations: observations,
        );

        controller.armIceDisconnectedTimer();
        async.flushMicrotasks();
        expect(signaling.sentOffers, isEmpty);

        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();
        expect(signaling.sentOffers, isEmpty);

        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();

        expect(signaling.sentOffers, isEmpty);
        expect(observations, hasLength(1));
        expect(
          observations.single.kind,
          CallRecoveryObservationKind.iceDisconnected,
        );
      });
    });

    test('renegotiation keeps audio offers audio-only', () async {
      final signaling = _FakeSignalingService();
      final logs = <String>[];
      final peer = _DummyPeerConnection();

      final controller = _buildController(
        signaling: signaling,
        getPeer: () => peer,
        getMediaType: () => CallMediaType.audio,
        logs: logs,
      );

      await controller.runRenegotiation('test');

      expect(peer.createOfferConstraints, hasLength(1));
      expect(
        peer.createOfferConstraints.single['offerToReceiveVideo'],
        isFalse,
      );
      expect(signaling.sentOffers, hasLength(1));
    });

    test(
      'ice restart offer sets iceRestart constraint and signal flag',
      () async {
        final signaling = _FakeSignalingService();
        final logs = <String>[];
        final peer = _DummyPeerConnection();

        final controller = _buildController(
          signaling: signaling,
          getPeer: () => peer,
          getMediaType: () => CallMediaType.audio,
          logs: logs,
        );

        await controller.runIceRestart('network changed');

        expect(peer.createOfferConstraints, hasLength(1));
        expect(peer.createOfferConstraints.single['iceRestart'], isTrue);
        expect(signaling.sentOffers, hasLength(1));
        final sentOffer = signaling.sentOffers.single['offer'] as Map;
        expect(sentOffer['iceRestart'], isTrue);
      },
    );

    test(
      'renegotiation rewrites video codec order before sending offer',
      () async {
        final signaling = _FakeSignalingService();
        final logs = <String>[];
        final peer = _DummyPeerConnection(
          createdOffer: RTCSessionDescription(
            'm=video 9 UDP/TLS/RTP/SAVPF 102 96\r\n'
                'a=rtpmap:102 H264/90000\r\n'
                'a=rtpmap:96 VP8/90000\r\n',
            'offer',
          ),
        );
        String? capturedLocalOfferSdp;

        final controller = _buildController(
          signaling: signaling,
          getPeer: () => peer,
          getMediaType: () => CallMediaType.video,
          logs: logs,
          rewriteVideoCodecs: (sdp, preferred) {
            expect(preferred, const <String>['VP8', 'H264']);
            return sdp.replaceFirst(
              'm=video 9 UDP/TLS/RTP/SAVPF 102 96',
              'm=video 9 UDP/TLS/RTP/SAVPF 96 102',
            );
          },
          captureExpectedVideoMidsForLocalOffer: (sdp) {
            capturedLocalOfferSdp = sdp;
          },
        );

        await controller.runRenegotiation('test');

        expect(signaling.sentOffers, hasLength(1));
        final sentSdp = signaling.sentOffers.single['offer']['sdp'] as String;
        expect(sentSdp, contains('m=video 9 UDP/TLS/RTP/SAVPF 96 102'));
        expect((await peer.getLocalDescription())?.sdp, sentSdp);
        expect(capturedLocalOfferSdp, sentSdp);
      },
    );

    test('TURN config uses TCP only when TCP is available', () async {
      final signaling = _FakeSignalingService();
      final logs = <String>[];
      final allocator = TurnAllocator()
        ..configureServers(const <TurnServerConfig>[
          TurnServerConfig(
            url: 'turn:peerlink.club:3478?transport=udp',
            username: 'peerlink',
            password: 'secret',
          ),
          TurnServerConfig(
            url: 'turn:peerlink.club:3478?transport=tcp',
            username: 'peerlink',
            password: 'secret',
          ),
        ]);
      TurnCredentials? activeCredentials;

      final controller = _buildController(
        signaling: signaling,
        turnAllocator: allocator,
        getPeer: () => null,
        getMediaType: () => CallMediaType.audio,
        logs: logs,
        onTurnCredentialsAllocated: (creds) => activeCredentials = creds,
      );

      final config = await controller.buildRtcConfig(TransportMode.turn);
      final iceServers = config['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers, hasLength(1));
      final urls = iceServers
          .expand((server) => server['urls'] as List<String>)
          .toList(growable: false);

      expect(urls, const <String>['turn:peerlink.club:3478?transport=tcp']);
      expect(activeCredentials?.url, 'turn:peerlink.club:3478?transport=tcp');
      expect(activeCredentials?.username, 'peerlink');
      expect(activeCredentials?.password, 'secret');
      expect(logs.any((message) => message.contains('tcpOnly=true')), isTrue);
      expect(logs.any((message) => message.contains('udpDropped=1')), isTrue);
      expect(
        logs.any((message) => message.contains('credentialPresent=true')),
        isTrue,
      );
    });

    test('TURN config keeps UDP when TCP is unavailable', () async {
      final signaling = _FakeSignalingService();
      final logs = <String>[];
      final allocator = TurnAllocator()
        ..configureServers(const <TurnServerConfig>[
          TurnServerConfig(
            url: 'turn:peerlink.club:3478?transport=udp',
            username: 'peerlink',
            password: 'secret',
          ),
        ]);

      final controller = _buildController(
        signaling: signaling,
        turnAllocator: allocator,
        getPeer: () => null,
        getMediaType: () => CallMediaType.audio,
        logs: logs,
      );

      final config = await controller.buildRtcConfig(TransportMode.turn);
      final iceServers = config['iceServers'] as List<Map<String, dynamic>>;
      expect(iceServers, hasLength(1));
      final urls = iceServers
          .expand((server) => server['urls'] as List<String>)
          .toList(growable: false);

      expect(urls, const <String>['turn:peerlink.club:3478?transport=udp']);
      expect(logs.any((message) => message.contains('tcpOnly=false')), isTrue);
    });
  });
}
