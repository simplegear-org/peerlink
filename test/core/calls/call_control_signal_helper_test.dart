import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_control_signal_helper.dart';
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

  _FakeSignalingService({
    SignalingConnectionStatus connectionStatus =
        SignalingConnectionStatus.connected,
  }) : _connectionStatus = connectionStatus;

  final List<_RecordedSignal> sentSignals = <_RecordedSignal>[];
  SignalingConnectionStatus _connectionStatus;

  void setConnectionStatus(SignalingConnectionStatus status) {
    _connectionStatus = status;
    _statusController.add(status);
  }

  @override
  Stream<SignalingMessage> get messages => _messagesController.stream;

  @override
  Stream<List<String>> get peersStream => _peersController.stream;

  @override
  SignalingConnectionStatus get connectionStatus => _connectionStatus;

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
  group('CallControlSignalHelper', () {
    test(
      'sendBestEffort waits for signaling reconnect and then sends control signal',
      () async {
        final signaling = _FakeSignalingService(
          connectionStatus: SignalingConnectionStatus.connecting,
        );
        final helper = CallControlSignalHelper(
          signaling: signaling,
          emitWaitingState: () {},
          log: (_) {},
          logError: (_, {error, stackTrace}) {},
        );

        addTearDown(signaling.close);

        final sendFuture = helper.sendBestEffort(
          'peer-a',
          'call_media_ready',
          const <String, dynamic>{'callId': 'call-a'},
          purpose: 'bootstrap reconnect during active call',
        );

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(signaling.sentSignals, isEmpty);

        signaling.setConnectionStatus(SignalingConnectionStatus.connected);
        await sendFuture;

        expect(signaling.sentSignals, hasLength(1));
        expect(signaling.sentSignals.single.peerId, 'peer-a');
        expect(signaling.sentSignals.single.type, 'call_media_ready');
        expect(signaling.sentSignals.single.data['callId'], 'call-a');
      },
    );
  });
}
