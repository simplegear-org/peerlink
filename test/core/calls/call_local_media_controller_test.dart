import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:peerlink/core/calls/call_local_media_controller.dart';
import 'package:peerlink/core/calls/call_media_stream_controller.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_video_controller.dart';
import 'package:peerlink/core/calls/call_video_state.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(String id) : super(id, 'test');

  @override
  bool? get active => true;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {}

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {}

  @override
  List<MediaStreamTrack> getTracks() => const <MediaStreamTrack>[];

  @override
  List<MediaStreamTrack> getAudioTracks() => const <MediaStreamTrack>[];

  @override
  List<MediaStreamTrack> getVideoTracks() => const <MediaStreamTrack>[];

  @override
  Future<void> getMediaTracks() async {}
}

class _FakeMediaStreamController extends CallMediaStreamController {
  _FakeMediaStreamController({
    this.exposedLocalStream,
    this.videoTrackCount = 0,
  }) : super(
         log: (_) {},
         onLocalStream: (_) {},
         onRemoteStream: (_) {},
         createRemoteRenderStream: (_) async => _FakeMediaStream('remote'),
       );

  final MediaStream? exposedLocalStream;
  final int videoTrackCount;
  var setMutedCalls = 0;
  var flipCameraCalls = 0;

  @override
  MediaStream? get localStream => exposedLocalStream;

  @override
  int get localVideoTrackCount => videoTrackCount;

  @override
  Future<void> setMuted(bool muted) async {
    setMutedCalls++;
  }

  @override
  Future<void> flipCamera() async {
    flipCameraCalls++;
  }
}

class _FakeVideoController extends CallVideoController {
  _FakeVideoController({this.ensureVideoTransceiversReadyResult = false})
    : super(
        signaling: _NoopSignalingService(),
        mediaStreamController: CallMediaStreamController(
          log: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: (_) {},
          createRemoteRenderStream: (_) async => _FakeMediaStream('remote'),
        ),
        state: CallVideoState(),
        log: (_) {},
        extractVideoMids: (_) => const <String>[],
        onRemoteVideoFlowChanged: (_) {},
        onRemoteVideoFlowStalled: (_) async {},
        getPeerId: () => null,
        getCallId: () => null,
        getStartedAsOfferer: () => true,
        getMediaType: () => CallMediaType.audio,
        getLocalVideoTrackAttached: () => false,
        getPeer: () => null,
        getSessionEpoch: () => 1,
      );

  final bool ensureVideoTransceiversReadyResult;
  var syncLocalMediaTracksCalls = 0;
  var refreshVideoChannelHandlesCalls = 0;
  var cancelVideoQualityUpgradeCalls = 0;
  var ensureVideoTransceiversReadyCalls = 0;

  @override
  Future<bool> ensureVideoTransceiversReady() async {
    ensureVideoTransceiversReadyCalls++;
    return ensureVideoTransceiversReadyResult;
  }

  @override
  Future<void> syncLocalMediaTracks() async {
    syncLocalMediaTracksCalls++;
  }

  @override
  Future<void> refreshVideoChannelHandles() async {
    refreshVideoChannelHandlesCalls++;
  }

  @override
  void cancelVideoQualityUpgrade() {
    cancelVideoQualityUpgradeCalls++;
  }
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
  group('CallLocalMediaController', () {
    test('setMuted delegates to media stream controller', () async {
      final mediaStreamController = _FakeMediaStreamController();
      final controller = CallLocalMediaController(
        mediaStreamController: mediaStreamController,
        log: (_) {},
        onMediaTypeChanged: (_) {},
        getPeer: () => null,
        getPeerId: () => null,
        getCallId: () => null,
        getMediaType: () => CallMediaType.audio,
        setMediaType: (_) {},
        getLocalVideoTrackAttached: () => false,
        getVideoSendSender: () => null,
        getVideoSendTransceiver: () => null,
        getVideoReceiveTransceiver: () => null,
        ensureVideoTransceiversReady: () async => false,
        requestRenegotiation: (_) async {},
        sendVideoState:
            ({required enabled, required peerId, required callId}) async {},
        cancelVideoUplinkFallback: () {},
        videoController: _FakeVideoController(),
      );

      await controller.setMuted(true);

      expect(mediaStreamController.setMutedCalls, 1);
    });

    test(
      'setLocalVideoEnabled updates state locally when peer or stream is unavailable',
      () async {
        final mediaTypeChanges = <CallMediaType>[];
        var currentMediaType = CallMediaType.audio;
        final controller = CallLocalMediaController(
          mediaStreamController: _FakeMediaStreamController(),
          log: (_) {},
          onMediaTypeChanged: mediaTypeChanges.add,
          getPeer: () => null,
          getPeerId: () => 'peer-b',
          getCallId: () => 'call-1',
          getMediaType: () => currentMediaType,
          setMediaType: (value) => currentMediaType = value,
          getLocalVideoTrackAttached: () => false,
          getVideoSendSender: () => null,
          getVideoSendTransceiver: () => null,
          getVideoReceiveTransceiver: () => null,
          ensureVideoTransceiversReady: () async => false,
          requestRenegotiation: (_) async {},
          sendVideoState:
              ({required enabled, required peerId, required callId}) async {},
          cancelVideoUplinkFallback: () {},
          videoController: _FakeVideoController(),
        );

        await controller.setLocalVideoEnabled(true);
        await controller.setLocalVideoEnabled(false);

        expect(mediaTypeChanges, <CallMediaType>[
          CallMediaType.video,
          CallMediaType.audio,
        ]);
      },
    );

    test(
      'setLocalVideoEnabled with active peer syncs tracks and sends state',
      () async {
        final mediaTypeChanges = <CallMediaType>[];
        var currentMediaType = CallMediaType.audio;
        final mediaStreamController = _FakeMediaStreamController(
          exposedLocalStream: _FakeMediaStream('local'),
          videoTrackCount: 1,
        );
        final videoController = _FakeVideoController();
        final sentVideoStates = <bool>[];
        final renegotiationReasons = <String>[];
        var cancelVideoUplinkFallbackCalls = 0;
        final controller = CallLocalMediaController(
          mediaStreamController: mediaStreamController,
          log: (_) {},
          onMediaTypeChanged: mediaTypeChanges.add,
          getPeer: () => _DummyPeerConnection(),
          getPeerId: () => 'peer-b',
          getCallId: () => 'call-1',
          getMediaType: () => currentMediaType,
          setMediaType: (value) => currentMediaType = value,
          getLocalVideoTrackAttached: () => true,
          getVideoSendSender: () => null,
          getVideoSendTransceiver: () => null,
          getVideoReceiveTransceiver: () => null,
          ensureVideoTransceiversReady: () async => false,
          requestRenegotiation: (reason) async {
            renegotiationReasons.add(reason);
          },
          sendVideoState:
              ({required enabled, required peerId, required callId}) async {
                sentVideoStates.add(enabled);
              },
          cancelVideoUplinkFallback: () => cancelVideoUplinkFallbackCalls++,
          videoController: videoController,
        );

        await controller.setLocalVideoEnabled(true);
        await controller.setLocalVideoEnabled(false);

        expect(mediaTypeChanges, <CallMediaType>[
          CallMediaType.video,
          CallMediaType.audio,
        ]);
        expect(sentVideoStates, <bool>[true, false]);
        expect(videoController.syncLocalMediaTracksCalls, 2);
        expect(videoController.refreshVideoChannelHandlesCalls, 1);
        expect(renegotiationReasons, <String>['local video enabled']);
        expect(cancelVideoUplinkFallbackCalls, 1);
        expect(videoController.cancelVideoQualityUpgradeCalls, 1);
      },
    );

    test(
      'setLocalVideoEnabled renegotiates when transceivers are created on demand',
      () async {
        var currentMediaType = CallMediaType.audio;
        final videoController = _FakeVideoController(
          ensureVideoTransceiversReadyResult: true,
        );
        final renegotiationReasons = <String>[];
        final controller = CallLocalMediaController(
          mediaStreamController: _FakeMediaStreamController(
            exposedLocalStream: _FakeMediaStream('local'),
          ),
          log: (_) {},
          onMediaTypeChanged: (_) {},
          getPeer: () => _DummyPeerConnection(),
          getPeerId: () => 'peer-b',
          getCallId: () => 'call-1',
          getMediaType: () => currentMediaType,
          setMediaType: (value) => currentMediaType = value,
          getLocalVideoTrackAttached: () => false,
          getVideoSendSender: () => null,
          getVideoSendTransceiver: () => null,
          getVideoReceiveTransceiver: () => null,
          ensureVideoTransceiversReady: () {
            return videoController.ensureVideoTransceiversReady();
          },
          requestRenegotiation: (reason) async {
            renegotiationReasons.add(reason);
          },
          sendVideoState:
              ({required enabled, required peerId, required callId}) async {},
          cancelVideoUplinkFallback: () {},
          videoController: videoController,
        );

        await controller.setLocalVideoEnabled(true);

        expect(videoController.ensureVideoTransceiversReadyCalls, 1);
        expect(videoController.syncLocalMediaTracksCalls, 1);
        expect(renegotiationReasons, <String>[
          'video transceivers created on demand',
        ]);
      },
    );
  });
}

class _DummyPeerConnection implements RTCPeerConnection {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
