import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_control_signal_router.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/signaling/signaling_message.dart';
import 'package:peerlink/core/transport/transport_mode.dart';

void main() {
  group('CallControlSignalRouter', () {
    test('applies invite runtime metadata before incoming ringing', () async {
      final events = <String>[];
      late CallState emittedState;
      final router = CallControlSignalRouter(
        sendSignal: (_, _, _) async {},
        isPendingRemoteEndedCall: ({required peerId, required callId}) => false,
        rememberPendingRemoteEndedCall: ({required peerId, required callId}) {},
        parseMediaType: (_) => CallMediaType.audio,
        cancelOutgoingTimeout: () {},
        emit: (state) {
          events.add('emit:${state.phase.name}');
          emittedState = state;
        },
        log: (_) {},
        endAndReset: (_) async {},
        applyInviteRuntimeMetadata: (data) async {
          events.add('metadata:${data.containsKey('priority_servers')}');
        },
        preferredInitialMode: () async => TransportMode.turn,
        startPeerConnection:
            ({required peerId, required callId, required initialMode}) async {},
        onRemoteMediaReady: ({required peerId, required callId}) async {},
        onRemoteHeartbeat:
            ({
              required peerId,
              required callId,
              required seq,
              required sentAtMs,
            }) async {},
        onRemoteAudioMuteState:
            ({
              required peerId,
              required callId,
              required muted,
              required version,
            }) async {},
        onRemoteVideoState:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoStateAck:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoFlowAck:
            ({required peerId, required callId, required version}) async {},
      );

      final handled = await router.handle(
        currentState: CallState.idle,
        message: SignalingMessage(
          type: 'call_invite',
          fromPeerId: 'peer-a',
          toPeerId: 'self',
          data: const <String, dynamic>{
            'callId': 'call-a',
            'priority_servers': <String, dynamic>{},
          },
        ),
      );

      expect(handled, isTrue);
      expect(events, <String>['metadata:true', 'emit:incomingRinging']);
      expect(emittedState.peerId, 'peer-a');
      expect(emittedState.callId, 'call-a');
    });

    test('routes remote audio mute state for current call', () async {
      var routedMuted = false;
      var routedVersion = 0;
      final router = CallControlSignalRouter(
        sendSignal: (_, _, _) async {},
        isPendingRemoteEndedCall: ({required peerId, required callId}) => false,
        rememberPendingRemoteEndedCall: ({required peerId, required callId}) {},
        parseMediaType: (_) => CallMediaType.audio,
        cancelOutgoingTimeout: () {},
        emit: (_) {},
        log: (_) {},
        endAndReset: (_) async {},
        applyInviteRuntimeMetadata: (_) async {},
        preferredInitialMode: () async => TransportMode.turn,
        startPeerConnection:
            ({required peerId, required callId, required initialMode}) async {},
        onRemoteMediaReady: ({required peerId, required callId}) async {},
        onRemoteHeartbeat:
            ({
              required peerId,
              required callId,
              required seq,
              required sentAtMs,
            }) async {},
        onRemoteAudioMuteState:
            ({
              required peerId,
              required callId,
              required muted,
              required version,
            }) async {
              routedMuted = muted;
              routedVersion = version;
            },
        onRemoteVideoState:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoStateAck:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoFlowAck:
            ({required peerId, required callId, required version}) async {},
      );

      final handled = await router.handle(
        currentState: const CallState(
          phase: CallPhase.active,
          callId: 'call-a',
          peerId: 'peer-a',
        ),
        message: SignalingMessage(
          type: 'call_audio_mute_state',
          fromPeerId: 'peer-a',
          toPeerId: 'self',
          data: const <String, dynamic>{
            'callId': 'call-a',
            'muted': true,
            'version': 4,
          },
        ),
      );

      expect(handled, isTrue);
      expect(routedMuted, isTrue);
      expect(routedVersion, 4);
    });

    test(
      'duplicate call_invite for same active call does not send busy',
      () async {
        final sentTypes = <String>[];
        final logs = <String>[];
        var emitted = false;
        var appliedMetadata = false;
        final router = CallControlSignalRouter(
          sendSignal: (_, type, _) async {
            sentTypes.add(type);
          },
          isPendingRemoteEndedCall: ({required peerId, required callId}) =>
              false,
          rememberPendingRemoteEndedCall:
              ({required peerId, required callId}) {},
          parseMediaType: (_) => CallMediaType.audio,
          cancelOutgoingTimeout: () {},
          emit: (_) {
            emitted = true;
          },
          log: logs.add,
          endAndReset: (_) async {},
          applyInviteRuntimeMetadata: (_) async {
            appliedMetadata = true;
          },
          preferredInitialMode: () async => TransportMode.turn,
          startPeerConnection:
              ({
                required peerId,
                required callId,
                required initialMode,
              }) async {},
          onRemoteMediaReady: ({required peerId, required callId}) async {},
          onRemoteHeartbeat:
              ({
                required peerId,
                required callId,
                required seq,
                required sentAtMs,
              }) async {},
          onRemoteAudioMuteState:
              ({
                required peerId,
                required callId,
                required muted,
                required version,
              }) async {},
          onRemoteVideoState:
              ({
                required peerId,
                required callId,
                required enabled,
                required version,
              }) async {},
          onRemoteVideoStateAck:
              ({
                required peerId,
                required callId,
                required enabled,
                required version,
              }) async {},
          onRemoteVideoFlowAck:
              ({required peerId, required callId, required version}) async {},
        );

        final handled = await router.handle(
          currentState: const CallState(
            phase: CallPhase.active,
            callId: 'call-a',
            peerId: 'peer-a',
          ),
          message: SignalingMessage(
            type: 'call_invite',
            fromPeerId: 'peer-a',
            toPeerId: 'self',
            data: const <String, dynamic>{
              'callId': 'call-a',
              'mediaType': 'audio',
            },
          ),
        );

        expect(handled, isTrue);
        expect(sentTypes, isEmpty);
        expect(emitted, isFalse);
        expect(appliedMetadata, isFalse);
        expect(logs.single, contains('invite:ignore duplicate'));
        expect(logs.single, contains('phase=active'));
      },
    );

    test('routes call heartbeat for current call', () async {
      var routedSeq = 0;
      var routedSentAtMs = 0;
      final router = CallControlSignalRouter(
        sendSignal: (_, _, _) async {},
        isPendingRemoteEndedCall: ({required peerId, required callId}) => false,
        rememberPendingRemoteEndedCall: ({required peerId, required callId}) {},
        parseMediaType: (_) => CallMediaType.audio,
        cancelOutgoingTimeout: () {},
        emit: (_) {},
        log: (_) {},
        endAndReset: (_) async {},
        applyInviteRuntimeMetadata: (_) async {},
        preferredInitialMode: () async => TransportMode.turn,
        startPeerConnection:
            ({required peerId, required callId, required initialMode}) async {},
        onRemoteMediaReady: ({required peerId, required callId}) async {},
        onRemoteHeartbeat:
            ({
              required peerId,
              required callId,
              required seq,
              required sentAtMs,
            }) async {
              routedSeq = seq;
              routedSentAtMs = sentAtMs;
            },
        onRemoteAudioMuteState:
            ({
              required peerId,
              required callId,
              required muted,
              required version,
            }) async {},
        onRemoteVideoState:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoStateAck:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoFlowAck:
            ({required peerId, required callId, required version}) async {},
      );

      final handled = await router.handle(
        currentState: const CallState(
          phase: CallPhase.active,
          callId: 'call-a',
          peerId: 'peer-a',
        ),
        message: SignalingMessage(
          type: 'call_heartbeat',
          fromPeerId: 'peer-a',
          toPeerId: 'self',
          data: const <String, dynamic>{
            'callId': 'call-a',
            'seq': 7,
            'sentAtMs': 12345,
          },
        ),
      );

      expect(handled, isTrue);
      expect(routedSeq, 7);
      expect(routedSentAtMs, 12345);
    });

    test('routes remote video mute state as disabled video', () async {
      var routedEnabled = true;
      var routedVersion = 0;
      final router = CallControlSignalRouter(
        sendSignal: (_, _, _) async {},
        isPendingRemoteEndedCall: ({required peerId, required callId}) => false,
        rememberPendingRemoteEndedCall: ({required peerId, required callId}) {},
        parseMediaType: (_) => CallMediaType.audio,
        cancelOutgoingTimeout: () {},
        emit: (_) {},
        log: (_) {},
        endAndReset: (_) async {},
        applyInviteRuntimeMetadata: (_) async {},
        preferredInitialMode: () async => TransportMode.turn,
        startPeerConnection:
            ({required peerId, required callId, required initialMode}) async {},
        onRemoteMediaReady: ({required peerId, required callId}) async {},
        onRemoteHeartbeat:
            ({
              required peerId,
              required callId,
              required seq,
              required sentAtMs,
            }) async {},
        onRemoteAudioMuteState:
            ({
              required peerId,
              required callId,
              required muted,
              required version,
            }) async {},
        onRemoteVideoState:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {
              routedEnabled = enabled;
              routedVersion = version;
            },
        onRemoteVideoStateAck:
            ({
              required peerId,
              required callId,
              required enabled,
              required version,
            }) async {},
        onRemoteVideoFlowAck:
            ({required peerId, required callId, required version}) async {},
      );

      final handled = await router.handle(
        currentState: const CallState(
          phase: CallPhase.active,
          callId: 'call-a',
          peerId: 'peer-a',
        ),
        message: SignalingMessage(
          type: 'call_video_mute_state',
          fromPeerId: 'peer-a',
          toPeerId: 'self',
          data: const <String, dynamic>{
            'callId': 'call-a',
            'muted': true,
            'version': 5,
          },
        ),
      );

      expect(handled, isTrue);
      expect(routedEnabled, isFalse);
      expect(routedVersion, 5);
    });

    test(
      'matching call_end is remembered before ending current call',
      () async {
        final remembered = <String>[];
        final ended = <String>[];
        final router = CallControlSignalRouter(
          sendSignal: (_, _, _) async {},
          isPendingRemoteEndedCall: ({required peerId, required callId}) =>
              false,
          rememberPendingRemoteEndedCall: ({required peerId, required callId}) {
            remembered.add('$peerId:$callId');
          },
          parseMediaType: (_) => CallMediaType.audio,
          cancelOutgoingTimeout: () {},
          emit: (_) {},
          log: (_) {},
          endAndReset: (status) async {
            ended.add(status);
          },
          applyInviteRuntimeMetadata: (_) async {},
          preferredInitialMode: () async => TransportMode.turn,
          startPeerConnection:
              ({
                required peerId,
                required callId,
                required initialMode,
              }) async {},
          onRemoteMediaReady: ({required peerId, required callId}) async {},
          onRemoteHeartbeat:
              ({
                required peerId,
                required callId,
                required seq,
                required sentAtMs,
              }) async {},
          onRemoteAudioMuteState:
              ({
                required peerId,
                required callId,
                required muted,
                required version,
              }) async {},
          onRemoteVideoState:
              ({
                required peerId,
                required callId,
                required enabled,
                required version,
              }) async {},
          onRemoteVideoStateAck:
              ({
                required peerId,
                required callId,
                required enabled,
                required version,
              }) async {},
          onRemoteVideoFlowAck:
              ({required peerId, required callId, required version}) async {},
        );

        final handled = await router.handle(
          currentState: const CallState(
            phase: CallPhase.active,
            callId: 'call-a',
            peerId: 'peer-a',
          ),
          message: SignalingMessage(
            type: 'call_end',
            fromPeerId: 'peer-a',
            toPeerId: 'self',
            data: const <String, dynamic>{'callId': 'call-a'},
          ),
        );

        expect(handled, isTrue);
        expect(remembered, <String>['peer-a:call-a']);
        expect(ended, <String>['Завершен']);
      },
    );
  });
}
