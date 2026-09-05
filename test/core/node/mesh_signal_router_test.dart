import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_service.dart';
import 'package:peerlink/core/node/mesh_peer_transports.dart';
import 'package:peerlink/core/node/mesh_signal_router.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';
import 'package:peerlink/core/transport/transport_mode.dart';
import 'package:peerlink/core/transport/webrtc_transport.dart';

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

class _FakeWebRtcTransport extends WebRtcTransport {
  _FakeWebRtcTransport({required super.signaling})
    : super(mode: TransportMode.direct, subscribeToSignaling: false);

  final List<SignalingMessage> handled = <SignalingMessage>[];

  @override
  Future<void> connect(String peerId) async {}

  @override
  Future<void> send(Uint8List data) async {}

  @override
  Future<void> close() async {}

  @override
  bool get isHealthy => true;

  @override
  Future<void> handleSignal(SignalingMessage message) async {
    handled.add(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MeshSignalRouter', () {
    test('routes call control signals into CallService', () async {
      final signaling = _FakeSignalingService();
      final calls = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      final router = MeshSignalRouter(
        selfPeerId: 'self',
        calls: calls,
        ensurePeerSession: (_, {required initiateDial}) async {},
        getPeerTransports: (_) => null,
        log: (_) {},
      );

      addTearDown(() async {
        await calls.dispose();
        await signaling.close();
      });

      await router.handleSignalingMessage(
        SignalingMessage(
          type: 'call_invite',
          fromPeerId: 'peer-a',
          toPeerId: 'self',
          data: const <String, dynamic>{
            'callId': 'call-a',
            'mediaType': 'video',
          },
        ),
      );

      expect(calls.state.phase, CallPhase.incomingRinging);
      expect(calls.state.peerId, 'peer-a');
      expect(calls.state.mediaType, CallMediaType.video);
    });

    test('routes non-call transport signals through peer transports', () async {
      final signaling = _FakeSignalingService();
      final calls = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      final target = _FakeWebRtcTransport(signaling: signaling);
      final transports = MeshPeerTransports(direct: target);
      var ensuredPeerId = '';
      var ensuredInitiateDial = true;
      final router = MeshSignalRouter(
        selfPeerId: 'self',
        calls: calls,
        ensurePeerSession: (peerId, {required initiateDial}) async {
          ensuredPeerId = peerId;
          ensuredInitiateDial = initiateDial;
        },
        getPeerTransports: (_) => transports,
        log: (_) {},
      );

      addTearDown(() async {
        await calls.dispose();
        await signaling.close();
      });

      final message = SignalingMessage(
        type: 'offer',
        fromPeerId: 'peer-b',
        toPeerId: 'self',
        data: const <String, dynamic>{},
      );
      await router.handleSignalingMessage(message);

      expect(ensuredPeerId, 'peer-b');
      expect(ensuredInitiateDial, isFalse);
      expect(target.handled, <SignalingMessage>[message]);
    });

    test('routes call heartbeat as call control signal', () async {
      final signaling = _FakeSignalingService();
      final calls = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      var ensureCalls = 0;
      final router = MeshSignalRouter(
        selfPeerId: 'self',
        calls: calls,
        ensurePeerSession: (_, {required initiateDial}) async {
          ensureCalls++;
        },
        getPeerTransports: (_) => null,
        log: (_) {},
      );

      addTearDown(() async {
        await calls.dispose();
        await signaling.close();
      });

      await router.handleSignalingMessage(
        SignalingMessage(
          type: 'call_heartbeat',
          fromPeerId: 'peer-heartbeat',
          toPeerId: 'self',
          data: const <String, dynamic>{
            'callId': 'call-heartbeat',
            'seq': 1,
            'sentAtMs': 123,
          },
        ),
      );

      expect(ensureCalls, 0);
    });

    test('drops non-call transport signals while call is active', () async {
      final signaling = _FakeSignalingService();
      final calls = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      final target = _FakeWebRtcTransport(signaling: signaling);
      final transports = MeshPeerTransports(direct: target);
      var ensureCalls = 0;
      final router = MeshSignalRouter(
        selfPeerId: 'self',
        calls: calls,
        ensurePeerSession: (_, {required initiateDial}) async {
          ensureCalls++;
        },
        getPeerTransports: (_) => transports,
        log: (_) {},
      );

      addTearDown(() async {
        await calls.dispose();
        await signaling.close();
      });

      await calls.presentIncomingCallFromPush(
        peerId: 'peer-c',
        callId: 'call-c',
      );

      await router.handleSignalingMessage(
        SignalingMessage(
          type: 'offer',
          fromPeerId: 'peer-c',
          toPeerId: 'self',
          data: const <String, dynamic>{},
        ),
      );

      expect(calls.state.isBusy, isTrue);
      expect(ensureCalls, 0);
      expect(target.handled, isEmpty);
    });
  });
}
