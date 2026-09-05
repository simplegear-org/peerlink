import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_media_flow_controller.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';

class _DummyPeerConnection implements RTCPeerConnection {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StatsPeerConnection extends _DummyPeerConnection {
  _StatsPeerConnection(this._statsSequence);

  final List<List<StatsReport>> _statsSequence;
  int _statsCallCount = 0;

  int get statsCallCount => _statsCallCount;

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async {
    final index = _statsCallCount < _statsSequence.length
        ? _statsCallCount
        : _statsSequence.length - 1;
    _statsCallCount += 1;
    return _statsSequence[index];
  }
}

List<StatsReport> _audioStats({
  required int bytesReceived,
  required int packetsReceived,
  int bytesSent = 0,
  int videoBytesReceived = 0,
  int videoFramesDecoded = 0,
}) {
  return <StatsReport>[
    StatsReport('audio-out', 'outbound-rtp', 0, {
      'kind': 'audio',
      'bytesSent': bytesSent,
    }),
    StatsReport('audio-in', 'inbound-rtp', 0, {
      'kind': 'audio',
      'bytesReceived': bytesReceived,
      'packetsReceived': packetsReceived,
      'audioLevel': 0.2,
      'totalAudioEnergy': bytesReceived / 1000,
      'totalSamplesDuration': packetsReceived / 50,
    }),
    if (videoBytesReceived > 0 || videoFramesDecoded > 0)
      StatsReport('video-in', 'inbound-rtp', 0, {
        'kind': 'video',
        'bytesReceived': videoBytesReceived,
        'framesDecoded': videoFramesDecoded,
      }),
  ];
}

class _NoopSignalingService implements SignalingService {
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

void main() {
  group('CallMediaFlowController ICE recovery', () {
    test('beginIceRecoveryFlowWatch resets tracked media flow state', () {
      var remoteAudioFlowSeen = true;
      var remoteVideoFlowSeen = true;
      var remoteVideoIndicator = true;

      final controller = CallMediaFlowController(
        signaling: _NoopSignalingService(),
        log: (_) {},
        getPeer: () => _DummyPeerConnection(),
        getPeerId: () => 'peer',
        getCallId: () => 'call',
        getIceConnected: () => false,
        getIceRecoveryInProgress: () => true,
        getRemoteAudioTrackSeen: () => true,
        getRemoteVideoTrackSeen: () => true,
        getRemoteAudioFlowSeen: () => remoteAudioFlowSeen,
        setRemoteAudioFlowSeen: (value) => remoteAudioFlowSeen = value,
        getRemoteVideoEnabled: () => true,
        getRemoteVideoFlowSeen: () => remoteVideoFlowSeen,
        setRemoteVideoFlowSeen: (value) => remoteVideoFlowSeen = value,
        markRemoteVideoFlowDetected: () {},
        getPendingRemoteVideoFlowAckVersion: () => null,
        setPendingRemoteVideoFlowAckVersion: (_) {},
        getMediaFlowNotified: () => true,
        setMediaFlowNotified: (_) {},
        notifyConnected: () {},
        onMediaFlow: () async {},
        onRemoteVideoFlowChanged: (active) => remoteVideoIndicator = active,
        onIceMediaRecoveryCompleted: () {},
        onIceReconnectStalled: (_) async {},
        onPostIceRecoveryFlowStalled: (_) async {},
        onLiveMediaFlowStalled: (_) async {},
        onStats: ({required sentBytes, required receivedBytes}) {},
        getSessionEpoch: () => 1,
      );

      controller.beginIceRecoveryFlowWatch();

      expect(remoteAudioFlowSeen, isFalse);
      expect(remoteVideoFlowSeen, isFalse);
      expect(remoteVideoIndicator, isFalse);
    });

    test(
      'armPostIceRecoveryFlowWatch escalates when flow does not return',
      () async {
        var stalledReason = '';

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: (_) {},
          getPeer: () => _DummyPeerConnection(),
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => true,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => false,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (reason) async {
            stalledReason = reason;
          },
          onLiveMediaFlowStalled: (_) async {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.beginIceRecoveryFlowWatch();
        controller.armPostIceRecoveryFlowWatch();
        await Future<void>.delayed(const Duration(milliseconds: 4100));

        expect(
          stalledReason,
          'Media flow did not recover after ICE reconnection',
        );
      },
    );

    test('armPostIceRecoveryFlowWatch waits while ice recovery is active', () {
      fakeAsync((async) {
        var reconnectReason = '';

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: (_) {},
          getPeer: () => _DummyPeerConnection(),
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => false,
          getIceRecoveryInProgress: () => true,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => false,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (reason) async {
            reconnectReason = reason;
          },
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (_) async {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.beginIceRecoveryFlowWatch();
        controller.armPostIceRecoveryFlowWatch();
        async.elapse(const Duration(milliseconds: 4100));
        async.flushMicrotasks();

        expect(reconnectReason, isEmpty);
      });
    });

    test(
      'armPostIceRecoveryFlowWatch escalates when no ice recovery is active',
      () {
        fakeAsync((async) {
          var reconnectReason = '';

          final controller = CallMediaFlowController(
            signaling: _NoopSignalingService(),
            log: (_) {},
            getPeer: () => _DummyPeerConnection(),
            getPeerId: () => 'peer',
            getCallId: () => 'call',
            getIceConnected: () => false,
            getIceRecoveryInProgress: () => false,
            getRemoteAudioTrackSeen: () => true,
            getRemoteVideoTrackSeen: () => false,
            getRemoteAudioFlowSeen: () => false,
            setRemoteAudioFlowSeen: (_) {},
            getRemoteVideoEnabled: () => false,
            getRemoteVideoFlowSeen: () => false,
            setRemoteVideoFlowSeen: (_) {},
            markRemoteVideoFlowDetected: () {},
            getPendingRemoteVideoFlowAckVersion: () => null,
            setPendingRemoteVideoFlowAckVersion: (_) {},
            getMediaFlowNotified: () => true,
            setMediaFlowNotified: (_) {},
            notifyConnected: () {},
            onMediaFlow: () async {},
            onRemoteVideoFlowChanged: (_) {},
            onIceMediaRecoveryCompleted: () {},
            onIceReconnectStalled: (reason) async {
              reconnectReason = reason;
            },
            onPostIceRecoveryFlowStalled: (_) async {},
            onLiveMediaFlowStalled: (_) async {},
            onStats: ({required sentBytes, required receivedBytes}) {},
            getSessionEpoch: () => 1,
          );

          controller.beginIceRecoveryFlowWatch();
          controller.armPostIceRecoveryFlowWatch();
          async.elapse(const Duration(milliseconds: 4100));
          async.flushMicrotasks();

          expect(
            reconnectReason,
            'ICE did not reconnect after recovery signaling',
          );
        });
      },
    );

    test('resetPostIceRecoveryFlowWatch invalidates the old timer', () {
      fakeAsync((async) {
        var reconnectCount = 0;

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: (_) {},
          getPeer: () => _DummyPeerConnection(),
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => false,
          getIceRecoveryInProgress: () => false,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => false,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {
            reconnectCount++;
          },
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (_) async {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.beginIceRecoveryFlowWatch();
        controller.armPostIceRecoveryFlowWatch();
        async.elapse(const Duration(seconds: 2));
        controller.resetPostIceRecoveryFlowWatch(reason: 'remote offer');
        controller.armPostIceRecoveryFlowWatch();
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();

        expect(reconnectCount, 0);

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(reconnectCount, 1);
      });
    });

    test(
      'armPostIceRecoveryFlowWatch does not escalate after audio flow recovery',
      () {
        fakeAsync((async) {
          var stalledReason = '';
          var remoteAudioFlowSeen = false;

          final controller = CallMediaFlowController(
            signaling: _NoopSignalingService(),
            log: (_) {},
            getPeer: () => _DummyPeerConnection(),
            getPeerId: () => 'peer',
            getCallId: () => 'call',
            getIceConnected: () => true,
            getIceRecoveryInProgress: () => true,
            getRemoteAudioTrackSeen: () => true,
            getRemoteVideoTrackSeen: () => false,
            getRemoteAudioFlowSeen: () => remoteAudioFlowSeen,
            setRemoteAudioFlowSeen: (value) => remoteAudioFlowSeen = value,
            getRemoteVideoEnabled: () => false,
            getRemoteVideoFlowSeen: () => false,
            setRemoteVideoFlowSeen: (_) {},
            markRemoteVideoFlowDetected: () {},
            getPendingRemoteVideoFlowAckVersion: () => null,
            setPendingRemoteVideoFlowAckVersion: (_) {},
            getMediaFlowNotified: () => true,
            setMediaFlowNotified: (_) {},
            notifyConnected: () {},
            onMediaFlow: () async {},
            onRemoteVideoFlowChanged: (_) {},
            onIceMediaRecoveryCompleted: () {},
            onIceReconnectStalled: (_) async {},
            onPostIceRecoveryFlowStalled: (reason) async {
              stalledReason = reason;
            },
            onLiveMediaFlowStalled: (_) async {},
            onStats: ({required sentBytes, required receivedBytes}) {},
            getSessionEpoch: () => 1,
          );

          controller.beginIceRecoveryFlowWatch();
          controller.armPostIceRecoveryFlowWatch();

          async.elapse(const Duration(seconds: 2));
          remoteAudioFlowSeen = true;
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();

          expect(stalledReason, isEmpty);
        });
      },
    );

    test(
      'armPostIceRecoveryFlowWatch handles video-only loss without full stall',
      () {
        fakeAsync((async) {
          var stalledReason = '';
          var videoOnlyReason = '';
          var mediaRecoveryCompleted = false;
          var remoteAudioFlowSeen = false;
          var remoteVideoFlowSeen = true;
          var remoteVideoIndicator = true;

          final controller = CallMediaFlowController(
            signaling: _NoopSignalingService(),
            log: (_) {},
            getPeer: () => _DummyPeerConnection(),
            getPeerId: () => 'peer',
            getCallId: () => 'call',
            getIceConnected: () => true,
            getIceRecoveryInProgress: () => true,
            getRemoteAudioTrackSeen: () => true,
            getRemoteVideoTrackSeen: () => true,
            getRemoteAudioFlowSeen: () => remoteAudioFlowSeen,
            setRemoteAudioFlowSeen: (value) => remoteAudioFlowSeen = value,
            getRemoteVideoEnabled: () => true,
            getRemoteVideoFlowSeen: () => remoteVideoFlowSeen,
            setRemoteVideoFlowSeen: (value) => remoteVideoFlowSeen = value,
            markRemoteVideoFlowDetected: () {},
            getPendingRemoteVideoFlowAckVersion: () => null,
            setPendingRemoteVideoFlowAckVersion: (_) {},
            getMediaFlowNotified: () => true,
            setMediaFlowNotified: (_) {},
            notifyConnected: () {},
            onMediaFlow: () async {},
            onRemoteVideoFlowChanged: (active) => remoteVideoIndicator = active,
            onIceMediaRecoveryCompleted: () {
              mediaRecoveryCompleted = true;
            },
            onIceReconnectStalled: (_) async {},
            onPostIceRecoveryFlowStalled: (reason) async {
              stalledReason = reason;
            },
            onPostIceRecoveryVideoOnlyStalled: (reason) async {
              videoOnlyReason = reason;
            },
            onLiveMediaFlowStalled: (_) async {},
            onStats: ({required sentBytes, required receivedBytes}) {},
            getSessionEpoch: () => 1,
          );

          controller.beginIceRecoveryFlowWatch();
          controller.armPostIceRecoveryFlowWatch();

          async.elapse(const Duration(seconds: 2));
          remoteAudioFlowSeen = true;
          async.elapse(const Duration(seconds: 3));
          async.flushMicrotasks();

          expect(stalledReason, isEmpty);
          expect(
            videoOnlyReason,
            'Remote video flow did not recover after ICE reconnection',
          );
          expect(remoteVideoIndicator, isFalse);
          expect(mediaRecoveryCompleted, isTrue);
        });
      },
    );

    test('live media stall uses a moving stats baseline', () {
      fakeAsync((async) {
        var stalledReason = '';
        final logs = <String>[];
        final peer = _StatsPeerConnection(<List<StatsReport>>[
          _audioStats(bytesReceived: 100, packetsReceived: 10),
          _audioStats(bytesReceived: 200, packetsReceived: 20),
          _audioStats(bytesReceived: 300, packetsReceived: 30),
          _audioStats(bytesReceived: 400, packetsReceived: 40),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
          _audioStats(bytesReceived: 500, packetsReceived: 50),
        ]);

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: logs.add,
          getPeer: () => peer,
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => false,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => true,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (reason) async {
            stalledReason = reason;
          },
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.ensureAudioStatsPolling();
        async.flushMicrotasks();

        for (var i = 0; i < 4; i += 1) {
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }
        expect(stalledReason, isEmpty);

        for (var i = 0; i < 13; i += 1) {
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }
        async.flushMicrotasks();
        expect(peer.statsCallCount, greaterThanOrEqualTo(17));
        expect(
          stalledReason,
          'Live media stalled while ICE remained connected',
        );
      });
    });

    test(
      'inbound-only stall triggers media recovery while outbound advances',
      () {
        fakeAsync((async) {
          var stalledReason = '';
          var localOutboundReason = '';
          final peer = _StatsPeerConnection(<List<StatsReport>>[
            _audioStats(
              bytesReceived: 100,
              packetsReceived: 10,
              bytesSent: 100,
            ),
            _audioStats(
              bytesReceived: 200,
              packetsReceived: 20,
              bytesSent: 200,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 300,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 400,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 500,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 600,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 700,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 800,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 900,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 1000,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 1100,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 1200,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 1300,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 1400,
            ),
            _audioStats(
              bytesReceived: 300,
              packetsReceived: 30,
              bytesSent: 1500,
            ),
          ]);

          final controller = CallMediaFlowController(
            signaling: _NoopSignalingService(),
            log: (_) {},
            getPeer: () => peer,
            getPeerId: () => 'peer',
            getCallId: () => 'call',
            getIceConnected: () => true,
            getIceRecoveryInProgress: () => false,
            getRemoteAudioTrackSeen: () => true,
            getRemoteVideoTrackSeen: () => false,
            getRemoteAudioFlowSeen: () => true,
            setRemoteAudioFlowSeen: (_) {},
            getRemoteVideoEnabled: () => false,
            getRemoteVideoFlowSeen: () => false,
            setRemoteVideoFlowSeen: (_) {},
            markRemoteVideoFlowDetected: () {},
            getPendingRemoteVideoFlowAckVersion: () => null,
            setPendingRemoteVideoFlowAckVersion: (_) {},
            getMediaFlowNotified: () => true,
            setMediaFlowNotified: (_) {},
            notifyConnected: () {},
            onMediaFlow: () async {},
            onRemoteVideoFlowChanged: (_) {},
            onIceMediaRecoveryCompleted: () {},
            onIceReconnectStalled: (_) async {},
            onPostIceRecoveryFlowStalled: (_) async {},
            onLiveMediaFlowStalled: (reason) async {
              stalledReason = reason;
            },
            onLocalAudioOutboundStalled: (reason) async {
              localOutboundReason = reason;
            },
            onStats: ({required sentBytes, required receivedBytes}) {},
            getSessionEpoch: () => 1,
          );

          controller.ensureAudioStatsPolling();
          async.flushMicrotasks();
          for (var i = 0; i < 14; i += 1) {
            async.elapse(const Duration(seconds: 1));
            async.flushMicrotasks();
          }

          expect(
            stalledReason,
            'Inbound media stalled while local outbound continued',
          );
          expect(localOutboundReason, isEmpty);
        });
      },
    );

    test('local outbound stall requests sender refresh', () {
      fakeAsync((async) {
        var stalledReason = '';
        var localOutboundReason = '';
        final peer = _StatsPeerConnection(<List<StatsReport>>[
          _audioStats(bytesReceived: 100, packetsReceived: 10, bytesSent: 100),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 200),
          _audioStats(bytesReceived: 300, packetsReceived: 30, bytesSent: 300),
          _audioStats(bytesReceived: 400, packetsReceived: 40, bytesSent: 300),
          _audioStats(bytesReceived: 500, packetsReceived: 50, bytesSent: 300),
          _audioStats(bytesReceived: 600, packetsReceived: 60, bytesSent: 300),
          _audioStats(bytesReceived: 700, packetsReceived: 70, bytesSent: 300),
          _audioStats(bytesReceived: 800, packetsReceived: 80, bytesSent: 300),
        ]);

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: (_) {},
          getPeer: () => peer,
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => false,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => true,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (reason) async {
            stalledReason = reason;
          },
          onLocalAudioOutboundStalled: (reason) async {
            localOutboundReason = reason;
          },
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.ensureAudioStatsPolling();
        async.flushMicrotasks();
        for (var i = 0; i < 7; i += 1) {
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }

        expect(stalledReason, isEmpty);
        expect(
          localOutboundReason,
          'Local audio outbound stalled while inbound media continued',
        );
      });
    });

    test('local muted audio does not request sender refresh', () {
      fakeAsync((async) {
        var localOutboundReason = '';
        final logs = <String>[];
        final peer = _StatsPeerConnection(<List<StatsReport>>[
          _audioStats(bytesReceived: 100, packetsReceived: 10, bytesSent: 100),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 200),
          _audioStats(bytesReceived: 300, packetsReceived: 30, bytesSent: 200),
          _audioStats(bytesReceived: 400, packetsReceived: 40, bytesSent: 200),
          _audioStats(bytesReceived: 500, packetsReceived: 50, bytesSent: 200),
          _audioStats(bytesReceived: 600, packetsReceived: 60, bytesSent: 200),
          _audioStats(bytesReceived: 700, packetsReceived: 70, bytesSent: 200),
          _audioStats(bytesReceived: 800, packetsReceived: 80, bytesSent: 200),
        ]);

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: logs.add,
          getPeer: () => peer,
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => false,
          getLocalAudioMuted: () => true,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => true,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (_) async {},
          onLocalAudioOutboundStalled: (reason) async {
            localOutboundReason = reason;
          },
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.ensureAudioStatsPolling();
        async.flushMicrotasks();
        for (var i = 0; i < 7; i += 1) {
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }

        expect(localOutboundReason, isEmpty);
        expect(
          logs.any(
            (line) => line.contains(
              'diagnostic:audio expected-silence source=local-muted',
            ),
          ),
          isTrue,
        );
      });
    });

    test('remote muted audio does not escalate inbound silence', () {
      fakeAsync((async) {
        var stalledReason = '';
        final logs = <String>[];
        final peer = _StatsPeerConnection(<List<StatsReport>>[
          _audioStats(bytesReceived: 100, packetsReceived: 10, bytesSent: 100),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 200),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 300),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 400),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 500),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 600),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 700),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 800),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 900),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 1000),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 1100),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 1200),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 1300),
          _audioStats(bytesReceived: 200, packetsReceived: 20, bytesSent: 1400),
        ]);

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: logs.add,
          getPeer: () => peer,
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => false,
          getRemoteAudioMuted: () => true,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => true,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (reason) async {
            stalledReason = reason;
          },
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.ensureAudioStatsPolling();
        async.flushMicrotasks();
        for (var i = 0; i < 13; i += 1) {
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }

        expect(stalledReason, isEmpty);
        expect(
          logs.any(
            (line) => line.contains(
              'diagnostic:audio expected-silence source=remote-muted',
            ),
          ),
          isTrue,
        );
      });
    });

    test('remote disabled video does not report video inbound stall', () {
      fakeAsync((async) {
        final logs = <String>[];
        final peer = _StatsPeerConnection(<List<StatsReport>>[
          _audioStats(
            bytesReceived: 100,
            packetsReceived: 10,
            bytesSent: 100,
            videoBytesReceived: 1000,
            videoFramesDecoded: 10,
          ),
          _audioStats(
            bytesReceived: 200,
            packetsReceived: 20,
            bytesSent: 200,
            videoBytesReceived: 1000,
            videoFramesDecoded: 10,
          ),
          _audioStats(
            bytesReceived: 300,
            packetsReceived: 30,
            bytesSent: 300,
            videoBytesReceived: 1000,
            videoFramesDecoded: 10,
          ),
          _audioStats(
            bytesReceived: 400,
            packetsReceived: 40,
            bytesSent: 400,
            videoBytesReceived: 1000,
            videoFramesDecoded: 10,
          ),
        ]);

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: logs.add,
          getPeer: () => peer,
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => false,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => true,
          getRemoteAudioFlowSeen: () => true,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (_) async {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
        );

        controller.ensureAudioStatsPolling();
        async.flushMicrotasks();
        for (var i = 0; i < 3; i += 1) {
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        }

        expect(
          logs.any((line) => line.contains('cause=video-inbound-stall')),
          isFalse,
        );
        expect(
          logs.any(
            (line) => line.contains(
              'diagnostic:video expected-silence source=remote-disabled',
            ),
          ),
          isTrue,
        );
      });
    });

    test('reports actual outbound bitrate from sent byte deltas', () {
      fakeAsync((async) {
        final measuredOutboundKbps = <double>[];
        final peer = _StatsPeerConnection(<List<StatsReport>>[
          _audioStats(bytesReceived: 100, packetsReceived: 10, bytesSent: 1000),
          _audioStats(
            bytesReceived: 200,
            packetsReceived: 20,
            bytesSent: 16000,
          ),
        ]);

        final controller = CallMediaFlowController(
          signaling: _NoopSignalingService(),
          log: (_) {},
          getPeer: () => peer,
          getPeerId: () => 'peer',
          getCallId: () => 'call',
          getIceConnected: () => true,
          getIceRecoveryInProgress: () => false,
          getRemoteAudioTrackSeen: () => true,
          getRemoteVideoTrackSeen: () => false,
          getRemoteAudioFlowSeen: () => true,
          setRemoteAudioFlowSeen: (_) {},
          getRemoteVideoEnabled: () => false,
          getRemoteVideoFlowSeen: () => false,
          setRemoteVideoFlowSeen: (_) {},
          markRemoteVideoFlowDetected: () {},
          getPendingRemoteVideoFlowAckVersion: () => null,
          setPendingRemoteVideoFlowAckVersion: (_) {},
          getMediaFlowNotified: () => true,
          setMediaFlowNotified: (_) {},
          notifyConnected: () {},
          onMediaFlow: () async {},
          onRemoteVideoFlowChanged: (_) {},
          onIceMediaRecoveryCompleted: () {},
          onIceReconnectStalled: (_) async {},
          onPostIceRecoveryFlowStalled: (_) async {},
          onLiveMediaFlowStalled: (_) async {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          getSessionEpoch: () => 1,
          onVideoNetworkStats: ({required stats, required outboundKbps}) async {
            measuredOutboundKbps.add(outboundKbps);
          },
        );

        controller.ensureAudioStatsPolling();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(measuredOutboundKbps.single, closeTo(120, 0.001));
      });
    });
  });
}
