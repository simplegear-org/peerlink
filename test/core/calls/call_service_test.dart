import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_control_reliable_payload.dart';
import 'package:peerlink/core/calls/call_control_transport.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/calls/call_service.dart';
import 'package:peerlink/core/firebase/firebase_push_callback_registry.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
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
  SignalingConnectionStatus _connectionStatus;
  Future<void> Function(String peerId, String type, Map<String, dynamic> data)?
  onSendSignal;

  _FakeSignalingService({
    SignalingConnectionStatus connectionStatus =
        SignalingConnectionStatus.connected,
  }) : _connectionStatus = connectionStatus;

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
    final handler = onSendSignal;
    if (handler != null) {
      await handler(peerId, type, data);
    }
  }

  @override
  Future<void> setServer(String endpoint) async {}
}

class _FakeCallControlTransport implements CallControlTransport {
  final sent = <({String peerId, String text})>[];
  CallControlInboundHandler? handler;

  @override
  Future<void> send(String peerId, String text) async {
    sent.add((peerId: peerId, text: text));
  }

  @override
  void setIncomingHandler(CallControlInboundHandler? handler) {
    this.handler = handler;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallService', () {
    test(
      'rejectIncomingCall does not block on disconnected signaling',
      () async {
        final signaling = _FakeSignalingService(
          connectionStatus: SignalingConnectionStatus.connecting,
        );
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-a',
          callId: 'call-a',
        );

        final stopwatch = Stopwatch()..start();
        await service.rejectIncomingCall();
        stopwatch.stop();

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(service.state.phase, CallPhase.idle);

        signaling.setConnectionStatus(SignalingConnectionStatus.connected);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          signaling.sentSignals.any((signal) => signal.type == 'call_reject'),
          isTrue,
        );
      },
    );

    test('endCall does not block on disconnected signaling', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-b',
        mediaType: CallMediaType.audio,
        callId: 'call-b',
      );
      signaling.setConnectionStatus(SignalingConnectionStatus.connecting);

      final stopwatch = Stopwatch()..start();
      await service.endCall();
      stopwatch.stop();

      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(service.state.phase, CallPhase.idle);

      signaling.setConnectionStatus(SignalingConnectionStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        signaling.sentSignals.any((signal) => signal.type == 'call_end'),
        isTrue,
      );
    });

    test(
      'remote end before invite suppresses later push and signaling invite',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.endCallFromRemotePush(peerId: 'peer-c', callId: 'call-c');
        expect(service.state.phase, CallPhase.idle);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-c',
          callId: 'call-c',
          mediaType: CallMediaType.video,
        );
        expect(service.state.phase, CallPhase.idle);

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-c',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-c', 'mediaType': 'video'},
          ),
        );
        expect(service.state.phase, CallPhase.idle);
      },
    );

    test(
      'delayed timestamp invite is ignored from push and signaling',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );
        final delayedCallId = DateTime.now()
            .subtract(const Duration(minutes: 3))
            .microsecondsSinceEpoch
            .toString();

        addTearDown(signaling.close);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-delayed',
          callId: delayedCallId,
        );
        expect(service.state.phase, CallPhase.idle);

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-delayed',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': delayedCallId},
          ),
        );
        expect(service.state.phase, CallPhase.idle);
        expect(signaling.sentSignals, isEmpty);
      },
    );

    test('blocked peer cannot be called directly', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
        outgoingCallAccessDecision: (_) =>
            IncomingInteractionDecision.blockedPeer,
      );

      addTearDown(signaling.close);

      expect(
        () => service.startOutgoingCall('peer-blocked', callId: 'call-blocked'),
        throwsA(isA<StateError>()),
      );
      expect(service.state.phase, CallPhase.idle);
      expect(signaling.sentSignals, isEmpty);
    });

    test('blocked push call invite is ignored', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
        incomingCallAccessDecision: (_) =>
            IncomingInteractionDecision.blockedPeer,
      );

      addTearDown(signaling.close);

      await service.presentIncomingCallFromPush(
        peerId: 'peer-blocked',
        callId: 'call-blocked',
      );

      expect(service.state.phase, CallPhase.idle);
    });

    test('blocked reliable call invite is ignored', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
        incomingCallAccessDecision: (_) =>
            IncomingInteractionDecision.blockedPeer,
      );
      const codec = CallControlReliablePayload();
      final text = codec.encode(
        controlType: 'call_invite',
        callId: 'call-blocked',
        data: codec.inviteData(
          callId: 'call-blocked',
          mediaType: CallMediaType.audio,
          inviteMetadata: const <String, dynamic>{},
        ),
      );

      addTearDown(signaling.close);

      final handled = await service.handleReliableControlPayload(
        fromPeerId: 'peer-blocked',
        text: text,
      );

      expect(handled, isTrue);
      expect(service.state.phase, CallPhase.idle);
    });

    test(
      'uses injected call control transport for reliable fallback',
      () async {
        final signaling = _FakeSignalingService();
        final transport = _FakeCallControlTransport();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
          callControlTransport: transport,
        );

        addTearDown(() async {
          await service.dispose();
          await signaling.close();
        });

        await service.startOutgoingCall('peer-port', callId: 'call-port');
        await Future<void>.delayed(Duration.zero);

        expect(transport.sent, hasLength(1));
        expect(transport.sent.single.peerId, 'peer-port');
        expect(
          transport.sent.single.text,
          startsWith(CallControlReliablePayload.prefix),
        );
        expect(transport.handler, isNotNull);
      },
    );

    test(
      'preserves video mediaType for outgoing and incoming invite flow',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.startOutgoingCall(
          'peer-d',
          mediaType: CallMediaType.video,
          callId: 'call-d',
        );
        expect(service.state.phase, CallPhase.outgoingRinging);
        expect(service.state.mediaType, CallMediaType.video);
        expect(signaling.sentSignals.last.type, 'call_invite');
        expect(signaling.sentSignals.last.data['mediaType'], 'video');

        await service.endCallFromRemotePush(peerId: 'peer-d', callId: 'call-d');
        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-e',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-e', 'mediaType': 'video'},
          ),
        );
        expect(service.state.phase, CallPhase.incomingRinging);
        expect(service.state.mediaType, CallMediaType.video);
      },
    );

    test(
      'outgoing bootstrap invite includes runtime server metadata',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        service.setCallInviteMetadataBuilder((peerId) {
          expect(peerId, 'peer-meta');
          return <String, dynamic>{
            'servers': <String, dynamic>{
              'turn': const <Map<String, dynamic>>[
                <String, dynamic>{
                  'url': 'turn:peerlink.club:3478?transport=udp',
                  'username': 'peerlink',
                  'password': 'secret',
                },
              ],
            },
            'priority_servers': <String, dynamic>{
              'turn': const <Map<String, dynamic>>[
                <String, dynamic>{
                  'url': 'turn:peerlink.club:3478?transport=tcp',
                  'username': 'peerlink',
                  'password': 'secret',
                },
              ],
            },
          };
        });

        await service.startOutgoingCall(
          'peer-meta',
          mediaType: CallMediaType.audio,
          callId: 'call-meta',
        );

        final invite = signaling.sentSignals.singleWhere(
          (signal) => signal.type == 'call_invite',
        );
        expect(invite.data['callId'], 'call-meta');
        expect(invite.data['servers'], isA<Map<String, dynamic>>());
        expect(invite.data['priority_servers'], isA<Map<String, dynamic>>());
        expect(
          ((invite.data['servers'] as Map<String, dynamic>)['turn'] as List)
              .single,
          containsPair('url', 'turn:peerlink.club:3478?transport=udp'),
        );
        expect(
          ((invite.data['priority_servers'] as Map<String, dynamic>)['turn']
                  as List)
              .single,
          containsPair('url', 'turn:peerlink.club:3478?transport=tcp'),
        );
      },
    );

    test(
      'startOutgoingCall waits for signaling reconnect before invite',
      () async {
        final signaling = _FakeSignalingService(
          connectionStatus: SignalingConnectionStatus.connecting,
        );
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        final startFuture = service.startOutgoingCall(
          'peer-wait',
          callId: 'call-wait',
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));

        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_invite'),
          isEmpty,
        );
        expect(service.state.phase, CallPhase.outgoingRinging);

        signaling.setConnectionStatus(SignalingConnectionStatus.connected);
        await startFuture;

        final invite = signaling.sentSignals.singleWhere(
          (signal) => signal.type == 'call_invite',
        );
        expect(invite.peerId, 'peer-wait');
        expect(invite.data['callId'], 'call-wait');
      },
    );

    test(
      'outgoing call retries invite while ringing and stops after reject',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.startOutgoingCall('peer-retry', callId: 'call-retry');

        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_invite'),
          hasLength(1),
        );

        await Future<void>.delayed(const Duration(milliseconds: 4200));

        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_invite'),
          hasLength(2),
        );

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_reject',
            fromPeerId: 'peer-retry',
            toPeerId: 'self',
            data: const <String, dynamic>{'callId': 'call-retry'},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 4200));

        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_invite'),
          hasLength(2),
        );
      },
    );

    test(
      'remote reject sends terminal end fallback before local reset',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );
        final reliableControls = <String>[];
        service.setReliableControlSender((peerId, text) async {
          reliableControls.add('$peerId|$text');
        });

        addTearDown(() async {
          await service.dispose();
          await signaling.close();
        });

        await service.startOutgoingCall(
          'peer-terminal',
          callId: 'call-terminal',
        );
        reliableControls.clear();

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_reject',
            fromPeerId: 'peer-terminal',
            toPeerId: 'self',
            data: const <String, dynamic>{'callId': 'call-terminal'},
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final terminalEndSignals = signaling.sentSignals.where(
          (signal) =>
              signal.type == 'call_end' &&
              signal.peerId == 'peer-terminal' &&
              signal.data['callId'] == 'call-terminal',
        );
        expect(terminalEndSignals, isNotEmpty);
        expect(
          reliableControls.where(
            (control) =>
                control.startsWith('peer-terminal|') &&
                control.contains(CallControlReliablePayload.prefix),
          ),
          isNotEmpty,
        );
      },
    );

    test('acceptIncomingCall retries accept while waiting for offer', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(() async {
        await service.dispose();
        await signaling.close();
      });

      await service.presentIncomingCallFromPush(
        peerId: 'peer-accept',
        callId: 'call-accept',
      );
      await service.acceptIncomingCall();

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
        hasLength(1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 3200));

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
        hasLength(2),
      );

      await service.handleControlSignal(
        SignalingMessage(
          type: 'call_end',
          fromPeerId: 'peer-accept',
          toPeerId: 'self',
          data: const <String, dynamic>{'callId': 'call-accept'},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 3200));

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
        hasLength(2),
      );
    });

    test('rejectIncomingCall retries reject after local reset', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(() async {
        await service.dispose();
        await signaling.close();
      });

      await service.presentIncomingCallFromPush(
        peerId: 'peer-reject',
        callId: 'call-reject',
      );
      await service.rejectIncomingCall();

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_reject'),
        hasLength(1),
      );

      await Future<void>.delayed(const Duration(milliseconds: 3200));

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_reject'),
        hasLength(2),
      );
    });

    test(
      'acceptIncomingCall uses reliable fallback when signaling is disconnected',
      () async {
        final signaling = _FakeSignalingService(
          connectionStatus: SignalingConnectionStatus.connecting,
        );
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );
        final reliableControls = <String>[];
        service.setReliableControlSender((peerId, text) async {
          reliableControls.add('$peerId|$text');
        });

        addTearDown(() async {
          await service.dispose();
          await signaling.close();
        });

        await service.presentIncomingCallFromPush(
          peerId: 'peer-reliable-accept',
          callId: 'call-reliable-accept',
        );

        final stopwatch = Stopwatch()..start();
        await service.acceptIncomingCall();
        stopwatch.stop();

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(service.state.phase, CallPhase.connecting);
        expect(reliableControls, hasLength(1));
        expect(reliableControls.single, startsWith('peer-reliable-accept|'));
        expect(
          reliableControls.single,
          contains(CallControlReliablePayload.prefix),
        );
        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
          isEmpty,
        );

        signaling.setConnectionStatus(SignalingConnectionStatus.connected);
        await Future<void>.delayed(const Duration(milliseconds: 3200));

        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
          hasLength(1),
        );
      },
    );

    test('reliable call_invite payload opens incoming call', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      const codec = CallControlReliablePayload();
      final text = codec.encode(
        controlType: 'call_invite',
        callId: 'call-reliable-invite',
        data: codec.inviteData(
          callId: 'call-reliable-invite',
          mediaType: CallMediaType.video,
          inviteMetadata: const <String, dynamic>{},
        ),
      );

      addTearDown(signaling.close);

      final handled = await service.handleReliableControlPayload(
        fromPeerId: 'peer-reliable-invite',
        text: text,
      );

      expect(handled, isTrue);
      expect(service.state.phase, CallPhase.incomingRinging);
      expect(service.state.peerId, 'peer-reliable-invite');
      expect(service.state.callId, 'call-reliable-invite');
      expect(service.state.mediaType, CallMediaType.video);
    });

    test('setMuted sends versioned audio mute control signal', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-mute',
        mediaType: CallMediaType.audio,
        callId: 'call-mute',
      );

      await service.setMuted(true);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final muteSignal = signaling.sentSignals.lastWhere(
        (signal) => signal.type == 'call_audio_mute_state',
      );
      expect(muteSignal.peerId, 'peer-mute');
      expect(muteSignal.data['callId'], 'call-mute');
      expect(muteSignal.data['muted'], isTrue);
      expect(muteSignal.data['version'], 1);
    });

    test('acceptIncomingCall waits for pending runtime enrichment', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );
      final pendingMerge = Completer<void>();

      addTearDown(() async {
        if (!pendingMerge.isCompleted) {
          pendingMerge.complete();
        }
        await signaling.close();
      });

      FirebasePushCallbackRegistry.trackPendingServersApply(
        pendingMerge.future,
      );
      await service.presentIncomingCallFromPush(
        peerId: 'peer-f',
        callId: 'call-f',
      );

      final acceptFuture = service.acceptIncomingCall();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
        isEmpty,
      );
      expect(service.state.phase, CallPhase.incomingRinging);

      pendingMerge.complete();
      await acceptFuture;

      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_accept'),
        hasLength(1),
      );
      expect(service.state.phase, CallPhase.connecting);
    });

    test('delayed terminal reset does not wipe newer call session', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-g',
        mediaType: CallMediaType.audio,
        callId: 'call-g',
      );

      final endFuture = service.endCall();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await service.startOutgoingCall(
        'peer-h',
        mediaType: CallMediaType.video,
        callId: 'call-h',
      );
      await endFuture;
      await Future<void>.delayed(const Duration(milliseconds: 320));

      expect(service.state.phase, CallPhase.outgoingRinging);
      expect(service.state.callId, 'call-h');
      expect(service.state.peerId, 'peer-h');
      expect(service.state.mediaType, CallMediaType.video);
    });

    test(
      'repeated remote call_end does not resurrect or break state',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-i',
          callId: 'call-i',
        );

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_end',
            fromPeerId: 'peer-i',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-i'},
          ),
        );
        expect(service.state.phase, CallPhase.idle);

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_end',
            fromPeerId: 'peer-i',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-i'},
          ),
        );
        expect(service.state.phase, CallPhase.idle);
      },
    );

    test(
      'late call_accept does not resurrect finished outgoing call',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.startOutgoingCall(
          'peer-j',
          mediaType: CallMediaType.audio,
          callId: 'call-j',
        );
        await service.endCall();
        await Future<void>.delayed(const Duration(milliseconds: 320));
        expect(service.state.phase, CallPhase.idle);

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_accept',
            fromPeerId: 'peer-j',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-j'},
          ),
        );

        expect(service.state.phase, CallPhase.idle);
        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_invite'),
          hasLength(1),
        );
      },
    );

    test('late answer does not resurrect finished outgoing call', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-j',
        mediaType: CallMediaType.audio,
        callId: 'call-j-answer',
      );
      await service.endCall();
      await Future<void>.delayed(const Duration(milliseconds: 320));
      expect(service.state.phase, CallPhase.idle);

      await service.handleMediaSignal(
        SignalingMessage(
          type: 'answer',
          fromPeerId: 'peer-j',
          toPeerId: 'self',
          data: <String, dynamic>{
            'callId': 'call-j-answer',
            'type': 'answer',
            'sdp': 'late-answer-sdp',
            'transportMode': 'direct',
          },
        ),
      );

      expect(service.state.phase, CallPhase.idle);
      expect(service.state.callId, isNull);
      expect(service.state.peerId, isNull);
      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_invite'),
        hasLength(1),
      );
    });

    test(
      'mismatched media signal does not rebind active incoming call',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-k',
          callId: 'call-k',
        );
        expect(service.state.phase, CallPhase.incomingRinging);

        await service.handleMediaSignal(
          SignalingMessage(
            type: 'offer',
            fromPeerId: 'peer-z',
            toPeerId: 'self',
            data: <String, dynamic>{
              'callId': 'call-z',
              'type': 'offer',
              'sdp': 'fake-sdp',
              'transportMode': 'direct',
            },
          ),
        );

        expect(service.state.phase, CallPhase.incomingRinging);
        expect(service.state.peerId, 'peer-k');
        expect(service.state.callId, 'call-k');
      },
    );

    test(
      'foreign peer with same callId does not rebind active incoming call',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-k',
          callId: 'call-shared',
        );
        expect(service.state.phase, CallPhase.incomingRinging);

        await service.handleMediaSignal(
          SignalingMessage(
            type: 'offer',
            fromPeerId: 'peer-z',
            toPeerId: 'self',
            data: <String, dynamic>{
              'callId': 'call-shared',
              'type': 'offer',
              'sdp': 'fake-sdp',
              'transportMode': 'direct',
            },
          ),
        );

        expect(service.state.phase, CallPhase.incomingRinging);
        expect(service.state.peerId, 'peer-k');
        expect(service.state.callId, 'call-shared');
      },
    );

    test('duplicate call_invite for same incoming call is ignored', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.presentIncomingCallFromPush(
        peerId: 'peer-l',
        callId: 'call-l',
      );

      await service.handleControlSignal(
        SignalingMessage(
          type: 'call_invite',
          fromPeerId: 'peer-l',
          toPeerId: 'self',
          data: <String, dynamic>{'callId': 'call-l', 'mediaType': 'audio'},
        ),
      );

      expect(service.state.phase, CallPhase.incomingRinging);
      expect(service.state.peerId, 'peer-l');
      expect(service.state.callId, 'call-l');
      expect(
        signaling.sentSignals.where((signal) => signal.type == 'call_busy'),
        isEmpty,
      );
    });

    test(
      'foreign call_invite during incoming call gets busy and does not rebind',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.presentIncomingCallFromPush(
          peerId: 'peer-m',
          callId: 'call-m',
        );

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-n',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-n', 'mediaType': 'video'},
          ),
        );

        expect(service.state.phase, CallPhase.incomingRinging);
        expect(service.state.peerId, 'peer-m');
        expect(service.state.callId, 'call-m');
        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_busy'),
          hasLength(1),
        );
        expect(
          signaling.sentSignals
              .where((signal) => signal.type == 'call_busy')
              .last
              .peerId,
          'peer-n',
        );
        expect(
          signaling.sentSignals
              .where((signal) => signal.type == 'call_busy')
              .last
              .data['callId'],
          'call-n',
        );
      },
    );

    test('foreign call_accept does not switch active outgoing call', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-o',
        mediaType: CallMediaType.audio,
        callId: 'call-o',
      );

      await service.handleControlSignal(
        SignalingMessage(
          type: 'call_accept',
          fromPeerId: 'peer-p',
          toPeerId: 'self',
          data: <String, dynamic>{'callId': 'call-p'},
        ),
      );

      expect(service.state.phase, CallPhase.outgoingRinging);
      expect(service.state.peerId, 'peer-o');
      expect(service.state.callId, 'call-o');
    });

    test('foreign call_busy does not terminate active outgoing call', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-q',
        mediaType: CallMediaType.video,
        callId: 'call-q',
      );

      await service.handleControlSignal(
        SignalingMessage(
          type: 'call_busy',
          fromPeerId: 'peer-r',
          toPeerId: 'self',
          data: <String, dynamic>{'callId': 'call-r'},
        ),
      );

      expect(service.state.phase, CallPhase.outgoingRinging);
      expect(service.state.peerId, 'peer-q');
      expect(service.state.callId, 'call-q');
      expect(service.state.mediaType, CallMediaType.video);
    });

    test('foreign call_end does not terminate active outgoing call', () async {
      final signaling = _FakeSignalingService();
      final service = CallService(
        selfPeerId: 'self',
        signaling: signaling,
        turnAllocator: null,
      );

      addTearDown(signaling.close);

      await service.startOutgoingCall(
        'peer-s',
        mediaType: CallMediaType.audio,
        callId: 'call-s',
      );

      await service.handleControlSignal(
        SignalingMessage(
          type: 'call_end',
          fromPeerId: 'peer-t',
          toPeerId: 'self',
          data: <String, dynamic>{'callId': 'call-t'},
        ),
      );

      expect(service.state.phase, CallPhase.outgoingRinging);
      expect(service.state.peerId, 'peer-s');
      expect(service.state.callId, 'call-s');
    });

    test(
      'foreign call_end suppresses later invite for same peer and call',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );

        addTearDown(signaling.close);

        await service.startOutgoingCall(
          'peer-u',
          mediaType: CallMediaType.video,
          callId: 'call-u',
        );

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_end',
            fromPeerId: 'peer-v',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-v'},
          ),
        );

        await service.endCall();
        await Future<void>.delayed(const Duration(milliseconds: 320));
        expect(service.state.phase, CallPhase.idle);

        await service.handleControlSignal(
          SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-v',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-v', 'mediaType': 'audio'},
          ),
        );

        expect(service.state.phase, CallPhase.idle);
        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_busy'),
          isEmpty,
        );
      },
    );

    test(
      'control and media signaling transitions are serialized at service level',
      () async {
        final signaling = _FakeSignalingService();
        final service = CallService(
          selfPeerId: 'self',
          signaling: signaling,
          turnAllocator: null,
        );
        final busyBlocker = Completer<void>();

        signaling.onSendSignal = (peerId, type, data) async {
          if (type == 'call_busy' && peerId == 'peer-x') {
            await busyBlocker.future;
          }
        };

        addTearDown(() async {
          if (!busyBlocker.isCompleted) {
            busyBlocker.complete();
          }
          await signaling.close();
        });

        await service.presentIncomingCallFromPush(
          peerId: 'peer-w',
          callId: 'call-w',
        );

        final firstFuture = service.handleControlSignal(
          SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-x',
            toPeerId: 'self',
            data: <String, dynamic>{'callId': 'call-x', 'mediaType': 'audio'},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));

        var mediaHandled = false;
        final secondFuture = service
            .handleMediaSignal(
              SignalingMessage(
                type: 'offer',
                fromPeerId: 'peer-z',
                toPeerId: 'self',
                data: <String, dynamic>{
                  'callId': 'call-z',
                  'type': 'offer',
                  'sdp': 'fake-sdp',
                  'transportMode': 'direct',
                },
              ),
            )
            .then((_) => mediaHandled = true);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(
          signaling.sentSignals.where((signal) => signal.type == 'call_busy'),
          hasLength(1),
        );
        expect(mediaHandled, isFalse);

        busyBlocker.complete();
        await firstFuture;
        await secondFuture;

        expect(mediaHandled, isTrue);
        expect(service.state.phase, CallPhase.incomingRinging);
        expect(service.state.peerId, 'peer-w');
        expect(service.state.callId, 'call-w');
      },
    );
  });
}
