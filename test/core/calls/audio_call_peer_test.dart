import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/audio_call_peer.dart';
import 'package:peerlink/core/calls/call_models.dart';
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
  final StreamController<SignalingMessage> _messagesController =
      StreamController<SignalingMessage>.broadcast();
  final StreamController<List<String>> _peersController =
      StreamController<List<String>>.broadcast();
  final StreamController<SignalingConnectionStatus> _statusController =
      StreamController<SignalingConnectionStatus>.broadcast();
  final StreamController<String?> _lastErrorController =
      StreamController<String?>.broadcast();

  final List<_RecordedSignal> sentSignals = <_RecordedSignal>[];

  @override
  Stream<SignalingMessage> get messages => _messagesController.stream;

  @override
  Stream<List<String>> get peersStream => _peersController.stream;

  @override
  SignalingConnectionStatus get connectionStatus =>
      SignalingConnectionStatus.connected;

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  @override
  String? get lastError => null;

  @override
  Stream<String?> get lastErrorStream => _lastErrorController.stream;

  @override
  Future<void> close() async {
    await _messagesController.close();
    await _peersController.close();
    await _statusController.close();
    await _lastErrorController.close();
  }

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioCallPeer', () {
    test(
      'setMediaType switches local state without peer and local stream',
      () async {
        final signaling = _FakeSignalingService();
        final mediaTypeChanges = <CallMediaType>[];
        final peer = AudioCallPeer(
          localPeerId: 'peer-a',
          signaling: signaling,
          turnAllocator: null,
          onConnected: (_) {},
          onMediaFlow: () async {},
          onMediaTypeChanged: mediaTypeChanges.add,
          onLocalStream: (_) {},
          onRemoteStream: (_) {},
          onRemoteVideoFlowChanged: (_) {},
          onRemoteVideoTrackChanged: (_) {},
          onVideoCodecChanged: (_) {},
          onIceRecoveryStateChanged:
              ({required recovering, required status}) {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          onError: (_) {},
        );

        addTearDown(() async {
          await peer.dispose();
          await signaling.close();
        });

        await peer.setMediaType(CallMediaType.video, reason: 'test');
        await peer.setMediaType(CallMediaType.audio, reason: 'test-back');

        expect(mediaTypeChanges, <CallMediaType>[
          CallMediaType.video,
          CallMediaType.audio,
        ]);
      },
    );

    test(
      'toggleVideo flips media type through facade without active peer',
      () async {
        final signaling = _FakeSignalingService();
        final mediaTypeChanges = <CallMediaType>[];
        final peer = AudioCallPeer(
          localPeerId: 'peer-a',
          signaling: signaling,
          turnAllocator: null,
          onConnected: (_) {},
          onMediaFlow: () async {},
          onMediaTypeChanged: mediaTypeChanges.add,
          onLocalStream: (_) {},
          onRemoteStream: (_) {},
          onRemoteVideoFlowChanged: (_) {},
          onRemoteVideoTrackChanged: (_) {},
          onVideoCodecChanged: (_) {},
          onIceRecoveryStateChanged:
              ({required recovering, required status}) {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          onError: (_) {},
        );

        addTearDown(() async {
          await peer.dispose();
          await signaling.close();
        });

        final first = await peer.toggleVideo();
        final second = await peer.toggleVideo();

        expect(first, CallMediaType.video);
        expect(second, CallMediaType.audio);
        expect(mediaTypeChanges, <CallMediaType>[
          CallMediaType.video,
          CallMediaType.audio,
        ]);
      },
    );

    test(
      'handleRemoteVideoState sends ack and reports awaiting video flow',
      () async {
        final signaling = _FakeSignalingService();
        final remoteVideoFlowChanges = <bool>[];
        final peer = AudioCallPeer(
          localPeerId: 'peer-a',
          signaling: signaling,
          turnAllocator: null,
          onConnected: (_) {},
          onMediaFlow: () async {},
          onMediaTypeChanged: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: (_) {},
          onRemoteVideoFlowChanged: remoteVideoFlowChanges.add,
          onRemoteVideoTrackChanged: (_) {},
          onVideoCodecChanged: (_) {},
          onIceRecoveryStateChanged:
              ({required recovering, required status}) {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          onError: (_) {},
        );

        addTearDown(() async {
          await peer.dispose();
          await signaling.close();
        });

        await peer.handleRemoteVideoState(
          enabled: true,
          version: 3,
          peerId: 'peer-b',
          callId: 'call-1',
        );

        expect(remoteVideoFlowChanges, <bool>[false]);
        expect(signaling.sentSignals, hasLength(1));
        expect(signaling.sentSignals.single.peerId, 'peer-b');
        expect(signaling.sentSignals.single.type, 'call_video_state_ack');
        expect(signaling.sentSignals.single.data['callId'], 'call-1');
        expect(signaling.sentSignals.single.data['version'], 3);
        expect(signaling.sentSignals.single.data['enabled'], isTrue);
      },
    );

    test('flipCamera skips when signaling is not stable', () async {
      final signaling = _FakeSignalingService();
      var performCalls = 0;
      final mediaTypeChanges = <CallMediaType>[];
      final peer = AudioCallPeer(
        localPeerId: 'peer-a',
        signaling: signaling,
        turnAllocator: null,
        onConnected: (_) {},
        onMediaFlow: () async {},
        onMediaTypeChanged: mediaTypeChanges.add,
        onLocalStream: (_) {},
        onRemoteStream: (_) {},
        onRemoteVideoFlowChanged: (_) {},
        onRemoteVideoTrackChanged: (_) {},
        onVideoCodecChanged: (_) {},
        onIceRecoveryStateChanged: ({required recovering, required status}) {},
        onStats: ({required sentBytes, required receivedBytes}) {},
        onError: (_) {},
        hasLocalVideoForFlipOverride: () => true,
        canExecuteCameraFlipOverride: () async => false,
        performCameraFlipOverride: () async {
          performCalls++;
        },
      );

      addTearDown(() async {
        await peer.dispose();
        await signaling.close();
      });

      await peer.setMediaType(CallMediaType.video, reason: 'test');
      await peer.flipCamera();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mediaTypeChanges, <CallMediaType>[CallMediaType.video]);
      expect(performCalls, 0);
    });

    test(
      'flipCamera queues one extra flip while first flip is in progress',
      () async {
        final signaling = _FakeSignalingService();
        final firstFlipBlocker = Completer<void>();
        var performCalls = 0;
        final peer = AudioCallPeer(
          localPeerId: 'peer-a',
          signaling: signaling,
          turnAllocator: null,
          onConnected: (_) {},
          onMediaFlow: () async {},
          onMediaTypeChanged: (_) {},
          onLocalStream: (_) {},
          onRemoteStream: (_) {},
          onRemoteVideoFlowChanged: (_) {},
          onRemoteVideoTrackChanged: (_) {},
          onVideoCodecChanged: (_) {},
          onIceRecoveryStateChanged:
              ({required recovering, required status}) {},
          onStats: ({required sentBytes, required receivedBytes}) {},
          onError: (_) {},
          hasLocalVideoForFlipOverride: () => true,
          canExecuteCameraFlipOverride: () async => true,
          performCameraFlipOverride: () async {
            performCalls++;
            if (performCalls == 1) {
              await firstFlipBlocker.future;
            }
          },
        );

        addTearDown(() async {
          if (!firstFlipBlocker.isCompleted) {
            firstFlipBlocker.complete();
          }
          await peer.dispose();
          await signaling.close();
        });

        await peer.setMediaType(CallMediaType.video, reason: 'test');
        final firstFlip = peer.flipCamera();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        await peer.flipCamera();
        expect(performCalls, 1);

        firstFlipBlocker.complete();
        await firstFlip;
        await Future<void>.delayed(const Duration(milliseconds: 320));

        expect(performCalls, 2);
      },
    );
  });
}
