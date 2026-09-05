import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/audio_call_peer.dart';
import 'package:peerlink/core/calls/call_connect_orchestration_helper.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

class _FakeAudioCallPeer extends AudioCallPeer {
  _FakeAudioCallPeer()
    : super(
        signaling: _NoopSignalingService(),
        turnAllocator: null,
        localPeerId: 'peer-a',
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

  final List<
    ({
      String peerId,
      String callId,
      TransportMode mode,
      CallMediaType mediaType,
    })
  >
  outgoingCalls =
      <
        ({
          String peerId,
          String callId,
          TransportMode mode,
          CallMediaType mediaType,
        })
      >[];

  @override
  Future<void> startOutgoing({
    required String peerId,
    required String callId,
    required TransportMode mode,
    required CallMediaType mediaType,
  }) async {
    outgoingCalls.add((
      peerId: peerId,
      callId: callId,
      mode: mode,
      mediaType: mediaType,
    ));
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
  group('CallConnectOrchestrationHelper', () {
    test('startPeerConnection starts outgoing peer and arms timeout', () async {
      final helper = CallConnectOrchestrationHelper();
      final peer = _FakeAudioCallPeer();
      final emittedStates = <CallState>[];
      final armedModes = <TransportMode>[];
      var state = const CallState(
        phase: CallPhase.outgoingRinging,
        peerId: 'peer-b',
        callId: 'call-1',
        mediaType: CallMediaType.video,
      );

      await helper.startPeerConnection(
        peerId: 'peer-b',
        callId: 'call-1',
        initialMode: TransportMode.turn,
        ensurePeer: ({required peerId, required callId}) async => peer,
        matchesCurrentCall: (peerId, callId) => true,
        emit: (next) {
          state = next;
          emittedStates.add(next);
        },
        getState: () => state,
        transportLabelFor: (mode) => mode.name,
        getActiveMediaType: () => CallMediaType.video,
        log: (_) {},
        retryViaTurn:
            ({required peerId, required callId, required reason}) async {},
        failAndReset: (_) async {},
        armConnectAttemptTimeout:
            ({required peerId, required callId, required mode}) {
              armedModes.add(mode);
            },
      );

      expect(peer.outgoingCalls, hasLength(1));
      expect(peer.outgoingCalls.single.mode, TransportMode.turn);
      expect(emittedStates.single.phase, CallPhase.connecting);
      expect(armedModes, <TransportMode>[TransportMode.turn]);
    });

    test('armConnectAttemptTimeout falls back to TURN on direct timeout', () {
      final helper = CallConnectOrchestrationHelper();
      final retryReasons = <String>[];
      var failed = <String>[];

      final timer = helper.armConnectAttemptTimeout(
        timeout: const Duration(milliseconds: 10),
        peerId: 'peer-b',
        callId: 'call-1',
        mode: TransportMode.direct,
        expectedEpoch: 1,
        getState: () => const CallState(
          phase: CallPhase.connecting,
          peerId: 'peer-b',
          callId: 'call-1',
        ),
        getCurrentEpoch: () => 1,
        getTurnFallbackAttempted: () => false,
        hasTurnAvailableNow: () => true,
        log: (_) {},
        retryViaTurn:
            ({required peerId, required callId, required reason}) async {
              retryReasons.add(reason);
            },
        failAndReset: (error) async {
          failed.add(error);
        },
      );

      return Future<void>.delayed(const Duration(milliseconds: 40), () {
        timer.cancel();
        expect(retryReasons, <String>['Direct timeout']);
        expect(failed, isEmpty);
      });
    });

    test('retryViaTurn recreates peer and starts turn connection', () async {
      final helper = CallConnectOrchestrationHelper();
      final peer = _FakeAudioCallPeer();
      final emittedStates = <CallState>[];
      final armedModes = <TransportMode>[];
      var disposed = 0;
      AudioCallPeer? storedPeer;
      var state = const CallState(
        phase: CallPhase.connecting,
        peerId: 'peer-b',
        callId: 'call-1',
      );

      await helper.retryViaTurn(
        peerId: 'peer-b',
        callId: 'call-1',
        reason: 'Direct timeout',
        getTurnFallbackAttempted: () => false,
        setTurnFallbackAttempted: (_) {},
        cancelConnectAttemptTimeout: () {},
        clearMediaReadyTimeout: () {},
        resetMediaRuntimeTracking: () {},
        hasTurnAvailable: () async => true,
        emit: (next) {
          state = next;
          emittedStates.add(next);
        },
        getState: () => state,
        failAndReset: (_) async {},
        log: (_) {},
        disposePeer: () async {
          disposed++;
        },
        setPeer: (peerValue) {
          storedPeer = peerValue;
        },
        ensurePeer: ({required peerId, required callId}) async => peer,
        matchesCurrentCall: (peerId, callId) => true,
        getActiveMediaType: () => CallMediaType.audio,
        armConnectAttemptTimeout:
            ({required peerId, required callId, required mode}) {
              armedModes.add(mode);
            },
      );

      expect(disposed, 1);
      expect(storedPeer, isNull);
      expect(emittedStates.single.transportMode, TransportMode.turn);
      expect(peer.outgoingCalls.single.mode, TransportMode.turn);
      expect(armedModes, <TransportMode>[TransportMode.turn]);
    });
  });
}
