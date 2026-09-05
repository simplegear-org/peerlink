import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_service.dart';
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
  final SignalingConnectionStatus connectionStatus =
      SignalingConnectionStatus.connected;

  @override
  Stream<SignalingMessage> get messages => _messagesController.stream;

  @override
  Stream<List<String>> get peersStream => _peersController.stream;

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

  test(
    'CallService smoke: outgoing and incoming control cycles stay stable',
    () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      final phases = <CallPhase>[service.state.phase];
      final subscription = service.stateStream.listen((state) {
        phases.add(state.phase);
      });

      addTearDown(() async {
        await subscription.cancel();
        await service.dispose();
        await signaling.close();
      });

      await service.startOutgoingCall(
        'peer-smoke',
        mediaType: CallMediaType.video,
        callId: 'call-smoke',
      );

      expect(service.state.phase, CallPhase.outgoingRinging);
      expect(service.state.peerId, 'peer-smoke');
      expect(service.state.mediaType, CallMediaType.video);
      expect(signaling.sentSignals.single.type, 'call_invite');
      expect(signaling.sentSignals.single.peerId, 'peer-smoke');
      expect(signaling.sentSignals.single.data['callId'], 'call-smoke');
      expect(signaling.sentSignals.single.data['mediaType'], 'video');

      await service.handleControlSignal(
        SignalingMessage(
          type: 'call_end',
          fromPeerId: 'peer-smoke',
          toPeerId: 'self',
          data: const <String, dynamic>{'callId': 'call-smoke'},
        ),
      );

      expect(service.state.phase, CallPhase.idle);

      await service.presentIncomingCallFromPush(
        peerId: 'peer-smoke-2',
        callId: 'call-smoke-2',
        mediaType: CallMediaType.audio,
      );
      expect(service.state.phase, CallPhase.incomingRinging);

      await service.rejectIncomingCall();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(service.state.phase, CallPhase.idle);

      expect(
        phases,
        containsAllInOrder(<CallPhase>[
          CallPhase.idle,
          CallPhase.outgoingRinging,
          CallPhase.idle,
          CallPhase.incomingRinging,
          CallPhase.idle,
        ]),
      );
    },
  );
}
