import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_media_stream_controller.dart';
import 'package:peerlink/core/calls/call_media_stats_utils.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_video_controller.dart';
import 'package:peerlink/core/calls/call_video_state.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';

class _RecordedSignal {
  const _RecordedSignal({
    required this.peerId,
    required this.type,
    required this.data,
  });

  final String peerId;
  final String type;
  final Map<String, dynamic> data;
}

class _FakeSignalingService implements SignalingService {
  final List<_RecordedSignal> sentSignals = <_RecordedSignal>[];

  @override
  SignalingConnectionStatus get connectionStatus =>
      SignalingConnectionStatus.connected;

  @override
  String? get lastError => null;

  @override
  Stream<SignalingMessage> get messages =>
      const Stream<SignalingMessage>.empty();

  @override
  Stream<List<String>> get peersStream => const Stream<List<String>>.empty();

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      const Stream<SignalingConnectionStatus>.empty();

  @override
  Stream<String?> get lastErrorStream => const Stream<String?>.empty();

  @override
  Future<void> close() async {}

  @override
  Future<void> configureServers(List<String> endpoints) async {}

  @override
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) async {}

  @override
  Future<void> sendIce(String peerId, Map<String, dynamic> candidate) async {}

  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) async {}

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {
    sentSignals.add(
      _RecordedSignal(
        peerId: peerId,
        type: type,
        data: Map<String, dynamic>.from(data),
      ),
    );
  }

  @override
  Future<void> setServer(String endpoint) async {}
}

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(String id) : super(id, 'test');

  final List<MediaStreamTrack> _tracks = <MediaStreamTrack>[];

  @override
  bool? get active => true;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    _tracks.add(track);
  }

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    _tracks.removeWhere((existing) => existing.id == track.id);
  }

  @override
  List<MediaStreamTrack> getTracks() => List<MediaStreamTrack>.from(_tracks);

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((track) => track.kind == 'audio').toList();

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((track) => track.kind == 'video').toList();

  @override
  Future<void> getMediaTracks() async {}
}

class _FakeMediaStreamTrack extends MediaStreamTrack {
  _FakeMediaStreamTrack({required this.trackId, required this.trackKind});

  final String trackId;
  final String trackKind;
  bool _enabled = true;

  @override
  String? get id => trackId;

  @override
  String? get kind => trackKind;

  @override
  String? get label => '$trackKind-$trackId';

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) {
    _enabled = b;
  }

  @override
  bool? get muted => false;

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeRtpSender implements RTCRtpSender {
  _FakeRtpSender({
    RTCRtpParameters? initialParameters,
    MediaStreamTrack? initialTrack,
  }) : _parameters = initialParameters ?? RTCRtpParameters(),
       _track = initialTrack;

  RTCRtpParameters _parameters;
  MediaStreamTrack? _track;
  final List<RTCRtpParameters> setParametersCalls = <RTCRtpParameters>[];

  @override
  RTCRtpParameters get parameters => _parameters;

  @override
  MediaStreamTrack? get track => _track;

  @override
  String get senderId => 'sender-1';

  @override
  bool get ownsTrack => false;

  @override
  RTCDTMFSender get dtmfSender => throw UnimplementedError();

  @override
  Future<void> dispose() async {}

  @override
  Future<List<StatsReport>> getStats() async => const <StatsReport>[];

  @override
  Future<void> replaceTrack(MediaStreamTrack? track) async {
    _track = track;
  }

  @override
  Future<bool> setParameters(RTCRtpParameters parameters) async {
    _parameters = parameters;
    setParametersCalls.add(parameters);
    return true;
  }

  @override
  Future<void> setStreams(List<MediaStream> streams) async {}

  @override
  Future<void> setTrack(
    MediaStreamTrack? track, {
    bool takeOwnership = true,
  }) async {
    _track = track;
  }
}

class _FakeRtpReceiver implements RTCRtpReceiver {
  _FakeRtpReceiver({MediaStreamTrack? track}) : _track = track;

  final MediaStreamTrack? _track;

  @override
  RTCRtpParameters get parameters => RTCRtpParameters();

  @override
  MediaStreamTrack? get track => _track;

  @override
  String get receiverId => 'receiver-1';

  @override
  Function(RTCRtpReceiver, RTCRtpMediaType)? onFirstPacketReceived;

  List<MediaStream> get streams => const <MediaStream>[];

  Future<void> dispose() async {}

  @override
  Future<List<StatsReport>> getStats() async => const <StatsReport>[];
}

class _FakeRtpTransceiver implements RTCRtpTransceiver {
  _FakeRtpTransceiver({
    required this.transceiverMid,
    required this.senderValue,
    required this.receiverValue,
    required TransceiverDirection initialDirection,
  }) : _direction = initialDirection;

  final String transceiverMid;
  final RTCRtpSender senderValue;
  final RTCRtpReceiver receiverValue;
  TransceiverDirection _direction;
  final List<TransceiverDirection> setDirectionCalls = <TransceiverDirection>[];

  @override
  String get mid => transceiverMid;

  @override
  RTCRtpSender get sender => senderValue;

  @override
  RTCRtpReceiver get receiver => receiverValue;

  @override
  TransceiverDirection get currentDirection => _direction;

  @override
  bool get stoped => false;

  @override
  String get transceiverId => 'transceiver-$transceiverMid';

  Future<void> dispose() async {}

  @override
  Future<TransceiverDirection> getCurrentDirection() async => _direction;

  @override
  Future<TransceiverDirection> getDirection() async => _direction;

  @override
  Future<void> setDirection(TransceiverDirection direction) async {
    _direction = direction;
    setDirectionCalls.add(direction);
  }

  @override
  Future<void> setCodecPreferences(List<RTCRtpCodecCapability> codecs) async {}

  @override
  Future<void> stop() async {}
}

AudioTrafficStats _trafficStats({
  double availableOutgoingBitrateKbps = 1200,
  double currentRoundTripTimeMs = 80,
  double videoJitterMs = 5,
  int audioPacketsLost = 0,
  int videoPacketsLost = 0,
  String? selectedCandidatePairId = 'pair-1',
}) {
  return AudioTrafficStats(
    sentBytes: 0,
    audioSentBytes: 0,
    receivedBytes: 0,
    packetsReceived: 0,
    audioLevel: 0,
    totalAudioEnergy: 0,
    totalSamplesDuration: 0,
    videoBytesReceived: 0,
    videoFramesDecoded: 0,
    selectedCandidatePairId: selectedCandidatePairId,
    localCandidateType: 'relay',
    remoteCandidateType: 'relay',
    candidateProtocol: 'udp',
    localCandidateAddress: '127.0.0.1:5000',
    remoteCandidateAddress: '127.0.0.1:6000',
    currentRoundTripTimeMs: currentRoundTripTimeMs,
    availableOutgoingBitrateKbps: availableOutgoingBitrateKbps,
    availableIncomingBitrateKbps: 1200,
    audioJitterMs: 5,
    videoJitterMs: videoJitterMs,
    audioPacketsLost: audioPacketsLost,
    videoPacketsLost: videoPacketsLost,
  );
}

CallVideoController _buildController({
  required _FakeSignalingService signaling,
  required CallVideoState state,
  required CallMediaType Function() getMediaType,
  required bool Function() getLocalVideoTrackAttached,
  required int Function() getSessionEpoch,
  required Future<void> Function(String reason) onRemoteVideoFlowStalled,
  required void Function(bool active) onRemoteVideoFlowChanged,
  String? Function()? getPeerId,
  String? Function()? getCallId,
  List<String> Function(String? sdp)? extractVideoMids,
}) {
  return CallVideoController(
    signaling: signaling,
    mediaStreamController: CallMediaStreamController(
      log: (_) {},
      onLocalStream: (_) {},
      onRemoteStream: (_) {},
      createRemoteRenderStream: (_) async => _FakeMediaStream('remote'),
    ),
    state: state,
    log: (_) {},
    extractVideoMids: extractVideoMids ?? (_) => const <String>[],
    onRemoteVideoFlowChanged: onRemoteVideoFlowChanged,
    onRemoteVideoFlowStalled: onRemoteVideoFlowStalled,
    getPeerId: getPeerId ?? () => 'peer-b',
    getCallId: getCallId ?? () => 'call-1',
    getStartedAsOfferer: () => true,
    getMediaType: getMediaType,
    getLocalVideoTrackAttached: getLocalVideoTrackAttached,
    getPeer: () => null,
    getSessionEpoch: getSessionEpoch,
  );
}

void main() {
  group('CallVideoController', () {
    test('remote offer maps local video mids by SDP direction', () {
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
          'a=sendonly\r\n';
      final signaling = _FakeSignalingService();
      final state = CallVideoState();
      final controller = _buildController(
        signaling: signaling,
        state: state,
        getMediaType: () => CallMediaType.video,
        getLocalVideoTrackAttached: () => true,
        getSessionEpoch: () => 1,
        onRemoteVideoFlowStalled: (_) async {},
        onRemoteVideoFlowChanged: (_) {},
        extractVideoMids: (_) => const <String>['1', '2'],
      );

      controller.captureExpectedVideoMidsForRemoteOffer(sdp);

      expect(state.expectedVideoSendMid, '1');
      expect(state.expectedVideoReceiveMid, '2');
    });

    test('local offer maps local video mids by SDP direction', () {
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
          'a=sendonly\r\n';
      final signaling = _FakeSignalingService();
      final state = CallVideoState();
      final controller = _buildController(
        signaling: signaling,
        state: state,
        getMediaType: () => CallMediaType.video,
        getLocalVideoTrackAttached: () => true,
        getSessionEpoch: () => 1,
        onRemoteVideoFlowStalled: (_) async {},
        onRemoteVideoFlowChanged: (_) {},
        extractVideoMids: (_) => const <String>['1', '2'],
      );

      controller.captureExpectedVideoMidsForLocalOffer(sdp);

      expect(state.expectedVideoSendMid, '2');
      expect(state.expectedVideoReceiveMid, '1');
    });

    test('single video mid is shared for local send and receive', () {
      const sdp =
          'v=0\r\n'
          'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
          'a=mid:0\r\n'
          'a=sendrecv\r\n'
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
          'a=mid:1\r\n'
          'a=sendrecv\r\n';
      final signaling = _FakeSignalingService();
      final state = CallVideoState();
      final controller = _buildController(
        signaling: signaling,
        state: state,
        getMediaType: () => CallMediaType.video,
        getLocalVideoTrackAttached: () => true,
        getSessionEpoch: () => 1,
        onRemoteVideoFlowStalled: (_) async {},
        onRemoteVideoFlowChanged: (_) {},
        extractVideoMids: (_) => const <String>['1'],
      );

      controller.captureExpectedVideoMidsForLocalOffer(sdp);
      expect(state.expectedVideoSendMid, '1');
      expect(state.expectedVideoReceiveMid, '1');

      controller.captureExpectedVideoMidsForRemoteOffer(sdp);
      expect(state.expectedVideoSendMid, '1');
      expect(state.expectedVideoReceiveMid, '1');

      controller.captureExpectedVideoMidsForRemoteAnswer(sdp);
      expect(state.expectedVideoSendMid, '1');
      expect(state.expectedVideoReceiveMid, '1');
    });

    test('sendVideoState retries until ack and stops after matching ack', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.video,
          getLocalVideoTrackAttached: () => true,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        controller.sendVideoState(
          enabled: true,
          peerId: 'peer-b',
          callId: 'call-1',
        );
        async.flushMicrotasks();

        expect(signaling.sentSignals, hasLength(2));
        expect(signaling.sentSignals[0].type, 'call_video_state');
        expect(signaling.sentSignals[1].type, 'call_video_mute_state');
        expect(signaling.sentSignals[1].data['muted'], isFalse);
        async.elapse(const Duration(milliseconds: 1200));
        async.flushMicrotasks();

        expect(signaling.sentSignals, hasLength(4));
        controller.handleVideoStateAck(enabled: true, version: 1);

        async.elapse(const Duration(milliseconds: 2400));
        async.flushMicrotasks();

        expect(signaling.sentSignals, hasLength(4));
        expect(state.pendingVideoStateVersion, isNull);
        expect(state.pendingVideoStateAttempts, 0);
      });
    });

    test('sendVideoState disabled sends video mute control signal', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.audio,
          getLocalVideoTrackAttached: () => false,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        controller.sendVideoState(
          enabled: false,
          peerId: 'peer-b',
          callId: 'call-1',
        );
        async.flushMicrotasks();

        expect(signaling.sentSignals, hasLength(2));
        expect(signaling.sentSignals[0].type, 'call_video_state');
        expect(signaling.sentSignals[0].data['enabled'], isFalse);
        expect(signaling.sentSignals[1].type, 'call_video_mute_state');
        expect(signaling.sentSignals[1].data['muted'], isTrue);
      });
    });

    test(
      'handleRemoteVideoState enabled arms recovery timeout and notifies stall',
      () {
        fakeAsync((async) {
          final signaling = _FakeSignalingService();
          final state = CallVideoState();
          final flowChanges = <bool>[];
          final stalledReasons = <String>[];
          final controller = _buildController(
            signaling: signaling,
            state: state,
            getMediaType: () => CallMediaType.video,
            getLocalVideoTrackAttached: () => true,
            getSessionEpoch: () => 1,
            onRemoteVideoFlowStalled: (reason) async {
              stalledReasons.add(reason);
            },
            onRemoteVideoFlowChanged: flowChanges.add,
          );

          controller.handleRemoteVideoState(
            enabled: true,
            version: 7,
            peerId: 'peer-b',
            callId: 'call-1',
          );
          async.flushMicrotasks();

          expect(signaling.sentSignals.single.type, 'call_video_state_ack');
          expect(flowChanges, equals(<bool>[false]));

          async.elapse(const Duration(seconds: 4));
          async.flushMicrotasks();

          expect(
            stalledReasons,
            equals(<String>['Remote video flow timeout version=7']),
          );
        });
      },
    );

    test('handleVideoFlowAck schedules delayed quality upgrade', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final sender = _FakeRtpSender(
          initialParameters: RTCRtpParameters(
            encodings: <RTCRtpEncoding>[RTCRtpEncoding()],
          ),
          initialTrack: _FakeMediaStreamTrack(
            trackId: 'video-1',
            trackKind: 'video',
          ),
        );
        state.videoSendSender = sender;
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.video,
          getLocalVideoTrackAttached: () => true,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        controller.applyInitialVideoQualityProfile();
        async.flushMicrotasks();
        controller.sendVideoState(
          enabled: true,
          peerId: 'peer-b',
          callId: 'call-1',
        );
        async.flushMicrotasks();
        controller.handleVideoFlowAck(version: 1);

        expect(state.pendingVideoFlowVersion, isNull);
        expect(state.videoQualityUpgradeTimer, isNotNull);
        expect(state.localVideoQualityProfile, 'safe');

        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(state.localVideoQualityProfile, 'safe');

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        final encoding = sender.parameters.encodings!.first;
        expect(state.videoQualityUpgradeTimer, isNull);
        expect(state.localVideoQualityProfile, 'balanced');
        expect(encoding.maxBitrate, 750000);
        expect(encoding.maxFramerate, 24);
        expect(encoding.scaleResolutionDownBy, 1.0);
      });
    });

    test(
      'applyInitialVideoQualityProfile starts in safe adaptive profile',
      () async {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final sender = _FakeRtpSender(
          initialParameters: RTCRtpParameters(
            encodings: <RTCRtpEncoding>[RTCRtpEncoding()],
          ),
          initialTrack: _FakeMediaStreamTrack(
            trackId: 'video-1',
            trackKind: 'video',
          ),
        );
        state.videoSendSender = sender;
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.video,
          getLocalVideoTrackAttached: () => true,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        await controller.applyInitialVideoQualityProfile();

        final encoding = sender.parameters.encodings!.first;
        expect(state.localVideoQualityProfile, 'safe');
        expect(encoding.maxBitrate, 450000);
        expect(encoding.minBitrate, isNull);
        expect(encoding.maxFramerate, 20);
        expect(encoding.scaleResolutionDownBy, 1.0);
      },
    );

    test(
      'handleNetworkStats downgrades when actual outbound overshoots',
      () async {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final sender = _FakeRtpSender(
          initialParameters: RTCRtpParameters(
            encodings: <RTCRtpEncoding>[RTCRtpEncoding()],
          ),
          initialTrack: _FakeMediaStreamTrack(
            trackId: 'video-1',
            trackKind: 'video',
          ),
        );
        state.videoSendSender = sender;
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.video,
          getLocalVideoTrackAttached: () => true,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        await controller.applyInitialVideoQualityProfile();
        await controller.handleNetworkStats(
          stats: _trafficStats(),
          outboundKbps: 900,
        );
        await controller.handleNetworkStats(
          stats: _trafficStats(),
          outboundKbps: 900,
        );

        final encoding = sender.parameters.encodings!.first;
        expect(state.localVideoQualityProfile, 'floor');
        expect(encoding.maxBitrate, 220000);
        expect(encoding.maxFramerate, 12);
        expect(encoding.scaleResolutionDownBy, 2.0);
      },
    );

    test('handleNetworkStats upgrades after stable headroom', () async {
      final signaling = _FakeSignalingService();
      final state = CallVideoState();
      final sender = _FakeRtpSender(
        initialParameters: RTCRtpParameters(
          encodings: <RTCRtpEncoding>[RTCRtpEncoding()],
        ),
        initialTrack: _FakeMediaStreamTrack(
          trackId: 'video-1',
          trackKind: 'video',
        ),
      );
      state.videoSendSender = sender;
      final controller = _buildController(
        signaling: signaling,
        state: state,
        getMediaType: () => CallMediaType.video,
        getLocalVideoTrackAttached: () => true,
        getSessionEpoch: () => 1,
        onRemoteVideoFlowStalled: (_) async {},
        onRemoteVideoFlowChanged: (_) {},
      );

      await controller.applyInitialVideoQualityProfile();
      for (var i = 0; i < 10; i += 1) {
        await controller.handleNetworkStats(
          stats: _trafficStats(availableOutgoingBitrateKbps: 1800),
          outboundKbps: 300,
        );
      }

      final encoding = sender.parameters.encodings!.first;
      expect(state.localVideoQualityProfile, 'balanced');
      expect(encoding.maxBitrate, 750000);
      expect(encoding.maxFramerate, 24);
      expect(encoding.scaleResolutionDownBy, 1.0);
    });

    test(
      'handleNetworkStats does not upgrade without selected route',
      () async {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final sender = _FakeRtpSender(
          initialParameters: RTCRtpParameters(
            encodings: <RTCRtpEncoding>[RTCRtpEncoding()],
          ),
          initialTrack: _FakeMediaStreamTrack(
            trackId: 'video-1',
            trackKind: 'video',
          ),
        );
        state.videoSendSender = sender;
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.video,
          getLocalVideoTrackAttached: () => true,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        await controller.applyInitialVideoQualityProfile();
        for (var i = 0; i < 10; i += 1) {
          await controller.handleNetworkStats(
            stats: _trafficStats(
              availableOutgoingBitrateKbps: 0,
              selectedCandidatePairId: null,
            ),
            outboundKbps: 10,
          );
        }

        final encoding = sender.parameters.encodings!.first;
        expect(state.localVideoQualityProfile, 'safe');
        expect(encoding.maxBitrate, 450000);
        expect(encoding.maxFramerate, 20);
        expect(encoding.scaleResolutionDownBy, 1.0);
      },
    );

    test(
      'ensureVideoTransceiverDirectionsForRole keeps shared transceiver sendrecv',
      () async {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final sender = _FakeRtpSender(
          initialTrack: _FakeMediaStreamTrack(
            trackId: 'video-local',
            trackKind: 'video',
          ),
        );
        final receiver = _FakeRtpReceiver(
          track: _FakeMediaStreamTrack(
            trackId: 'video-remote',
            trackKind: 'video',
          ),
        );
        final transceiver = _FakeRtpTransceiver(
          transceiverMid: '1',
          senderValue: sender,
          receiverValue: receiver,
          initialDirection: TransceiverDirection.SendRecv,
        );
        state.videoSendTransceiver = transceiver;
        state.videoReceiveTransceiver = transceiver;
        final controller = _buildController(
          signaling: signaling,
          state: state,
          getMediaType: () => CallMediaType.video,
          getLocalVideoTrackAttached: () => true,
          getSessionEpoch: () => 1,
          onRemoteVideoFlowStalled: (_) async {},
          onRemoteVideoFlowChanged: (_) {},
        );

        await controller.ensureVideoTransceiverDirectionsForRole();

        expect(
          transceiver.setDirectionCalls,
          equals(<TransceiverDirection>[TransceiverDirection.SendRecv]),
        );
      },
    );
  });
}
