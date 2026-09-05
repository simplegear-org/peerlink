import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_video_signaling_controller.dart';
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

CallVideoSignalingController _buildController({
  required _FakeSignalingService signaling,
  required CallVideoState state,
  int Function()? getSessionEpoch,
  String? Function()? getPeerId,
  String? Function()? getCallId,
  void Function(bool active)? onRemoteVideoFlowChanged,
  Future<void> Function(String reason)? onRemoteVideoFlowStalled,
  void Function()? scheduleVideoQualityUpgrade,
}) {
  return CallVideoSignalingController(
    signaling: signaling,
    state: state,
    log: (_) {},
    getSessionEpoch: getSessionEpoch ?? () => 1,
    getPeerId: getPeerId ?? () => 'peer-b',
    getCallId: getCallId ?? () => 'call-1',
    onRemoteVideoFlowChanged: onRemoteVideoFlowChanged ?? (_) {},
    onRemoteVideoFlowStalled: onRemoteVideoFlowStalled ?? (_) async {},
    scheduleVideoQualityUpgrade: scheduleVideoQualityUpgrade ?? () {},
  );
}

void main() {
  group('CallVideoSignalingController', () {
    test('sendVideoState retries until matching ack', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final controller = _buildController(signaling: signaling, state: state);

        controller.sendVideoState(
          enabled: true,
          peerId: 'peer-b',
          callId: 'call-1',
        );
        async.flushMicrotasks();

        expect(signaling.sentSignals, hasLength(2));
        expect(signaling.sentSignals.first.type, 'call_video_state');
        expect(signaling.sentSignals.last.type, 'call_video_mute_state');

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

    test('remote video enabled arms recovery timeout', () {
      fakeAsync((async) {
        final signaling = _FakeSignalingService();
        final state = CallVideoState();
        final flowChanges = <bool>[];
        final stalledReasons = <String>[];
        final controller = _buildController(
          signaling: signaling,
          state: state,
          onRemoteVideoFlowChanged: flowChanges.add,
          onRemoteVideoFlowStalled: (reason) async {
            stalledReasons.add(reason);
          },
        );

        controller.handleRemoteVideoState(
          enabled: true,
          version: 3,
          peerId: 'peer-b',
          callId: 'call-1',
        );
        async.flushMicrotasks();

        expect(signaling.sentSignals.single.type, 'call_video_state_ack');
        expect(flowChanges, <bool>[false]);

        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();

        expect(stalledReasons, <String>['Remote video flow timeout version=3']);
      });
    });

    test('flow ack clears pending version and schedules quality upgrade', () {
      final signaling = _FakeSignalingService();
      final state = CallVideoState()..pendingVideoFlowVersion = 9;
      var upgrades = 0;
      final controller = _buildController(
        signaling: signaling,
        state: state,
        scheduleVideoQualityUpgrade: () => upgrades++,
      );

      controller.handleVideoFlowAck(version: 9);

      expect(state.pendingVideoFlowVersion, isNull);
      expect(upgrades, 1);
    });
  });
}
