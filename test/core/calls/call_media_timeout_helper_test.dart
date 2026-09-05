import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/audio_call_peer.dart';
import 'package:peerlink/core/calls/call_media_timeout_helper.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_recovery_coordinator.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';

class _FakeSignalingService implements SignalingService {
  final StreamController<SignalingMessage> _messagesController =
      StreamController<SignalingMessage>.broadcast();
  final StreamController<List<String>> _peersController =
      StreamController<List<String>>.broadcast();
  final StreamController<SignalingConnectionStatus> _statusController =
      StreamController<SignalingConnectionStatus>.broadcast();
  final StreamController<String?> _lastErrorController =
      StreamController<String?>.broadcast();

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
  ) async {}

  @override
  Future<void> setServer(String endpoint) async {}
}

void main() {
  group('CallMediaTimeoutHelper', () {
    test('stale epoch suppresses pending timer after peer dispose', () async {
      final signaling = _FakeSignalingService();
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
        onIceRecoveryStateChanged: ({required recovering, required status}) {},
        onStats: ({required sentBytes, required receivedBytes}) {},
        onError: (_) {},
      );
      const helper = CallMediaTimeoutHelper();
      final logMessages = <String>[];
      var rearmCount = 0;
      var failCount = 0;
      var epoch = 1;

      addTearDown(() async {
        await peer.dispose();
        await signaling.close();
      });

      final timer = helper.armMediaReadyTimeout(
        timeout: const Duration(milliseconds: 10),
        getState: () => const CallState(
          phase: CallPhase.connecting,
          peerId: 'peer-a',
          callId: 'call-a',
        ),
        getLocalMediaReady: () => false,
        getRemoteMediaReady: () => false,
        expectedEpoch: epoch,
        getCurrentEpoch: () => epoch,
        expectedPeer: peer,
        expectedPeerId: 'peer-a',
        expectedCallId: 'call-a',
        matchesCurrentCall: (peerId, callId) =>
            peerId == 'peer-a' && callId == 'call-a',
        getPeer: () => peer,
        getMediaRecoveryAttempt: () => 0,
        setMediaRecoveryAttempt: (_) {},
        onMediaReadyTimeout:
            ({
              required attempt,
              required localMediaReady,
              required remoteMediaReady,
            }) async {
              return CallRecoveryDisposition.retryLater;
            },
        log: logMessages.add,
        rearmMediaReadyTimeout: () => rearmCount++,
      );

      epoch = 2;
      await Future<void>.delayed(const Duration(milliseconds: 40));
      timer.cancel();

      expect(logMessages, isEmpty);
      expect(rearmCount, 0);
      expect(failCount, 0);
    });
  });
}
