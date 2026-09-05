import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/features/calls/platform/ios_callkit_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

class _PresentedIncomingCall {
  const _PresentedIncomingCall({
    required this.peerId,
    required this.callId,
    required this.mediaType,
  });

  final String peerId;
  final String callId;
  final CallMediaType mediaType;
}

class _CapturedPushPayload {
  const _CapturedPushPayload({required this.payload, required this.source});

  final Map<String, dynamic> payload;
  final String source;
}

class _FakeCallkitAdapter {
  _FakeCallkitAdapter({CallState initialState = CallState.idle})
    : _state = initialState;

  final StreamController<CallState> _stateController =
      StreamController<CallState>.broadcast();
  final List<_PresentedIncomingCall> presentedIncomingCalls =
      <_PresentedIncomingCall>[];
  final List<bool> speakerUpdates = <bool>[];
  int acceptCalls = 0;
  int rejectCalls = 0;
  int endCalls = 0;
  int registerPushTokenCalls = 0;
  String? lastRegisteredPushToken;
  CallState _state;

  CallState get state => _state;

  IosCallkitFacadeAdapter build() {
    return IosCallkitFacadeAdapter(
      getCallState: () => _state,
      getCallStateStream: () => _stateController.stream,
      presentIncomingCallFromPush:
          ({
            required String peerId,
            required String callId,
            required CallMediaType mediaType,
          }) async {
            presentedIncomingCalls.add(
              _PresentedIncomingCall(
                peerId: peerId,
                callId: callId,
                mediaType: mediaType,
              ),
            );
          },
      acceptIncomingCall: () async {
        acceptCalls++;
      },
      rejectIncomingCall: () async {
        rejectCalls++;
      },
      endCall: () async {
        endCalls++;
      },
      setCallSpeakerOn: (enabled) async {
        speakerUpdates.add(enabled);
      },
      registerPushDeviceToken: (token) async {
        registerPushTokenCalls++;
        lastRegisteredPushToken = token;
      },
    );
  }

  void emitState(CallState state) {
    _state = state;
    _stateController.add(state);
  }

  Future<void> close() async {
    await _stateController.close();
  }
}

IosCallkitService _testService() {
  return IosCallkitService.test(
    isIosOverride: () => true,
    storage: StorageService(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('peerlink/callkit/methods');
  const eventMethodChannel = MethodChannel('peerlink/callkit/events');

  setUp(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      switch (call.method) {
        case 'refreshVoipRegistration':
          return null;
        case 'getVoipToken':
          return null;
        case 'startOutgoingCall':
          return null;
        case 'updateOutgoingCall':
          return null;
        case 'endSystemCall':
          return null;
        case 'updateIncomingCallerName':
          return null;
        case 'callUiPresented':
          return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(eventMethodChannel, (call) async {
      if (call.method == 'listen' || call.method == 'cancel') {
        return null;
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockMethodCallHandler(eventMethodChannel, null);
  });

  group('IosCallkitService', () {
    test('call_incoming applies payload and presents incoming call', () async {
      final adapter = _FakeCallkitAdapter();
      final capturedPayloads = <_CapturedPushPayload>[];
      final service = _testService();

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(
        adapter.build(),
        onPushPayload: (payload, {required source}) async {
          capturedPayloads.add(
            _CapturedPushPayload(
              payload: Map<String, dynamic>.from(payload),
              source: source,
            ),
          );
        },
      );

      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'call_incoming',
        'callId': 'call-1',
        'fromPeerId': 'peer-a',
        'mediaType': 'video',
        'servers': '{"bootstrap":["wss://s1"]}',
      });

      expect(adapter.presentedIncomingCalls, hasLength(1));
      expect(adapter.presentedIncomingCalls.single.peerId, 'peer-a');
      expect(adapter.presentedIncomingCalls.single.callId, 'call-1');
      expect(
        adapter.presentedIncomingCalls.single.mediaType,
        CallMediaType.video,
      );
      expect(capturedPayloads, hasLength(1));
      expect(capturedPayloads.single.source, 'call_incoming');
      expect(capturedPayloads.single.payload['callId'], 'call-1');
    });

    test('accept action restores incoming state and accepts call', () async {
      final adapter = _FakeCallkitAdapter();
      final capturedPayloads = <_CapturedPushPayload>[];
      final service = _testService();

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(
        adapter.build(),
        onPushPayload: (payload, {required source}) async {
          capturedPayloads.add(
            _CapturedPushPayload(
              payload: Map<String, dynamic>.from(payload),
              source: source,
            ),
          );
        },
      );

      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'call_action',
        'action': 'accept',
        'callId': 'call-2',
        'fromPeerId': 'peer-b',
        'mediaType': 'audio',
      });

      expect(adapter.presentedIncomingCalls, hasLength(1));
      expect(adapter.presentedIncomingCalls.single.peerId, 'peer-b');
      expect(adapter.presentedIncomingCalls.single.callId, 'call-2');
      expect(adapter.acceptCalls, 1);
      expect(capturedPayloads, hasLength(1));
      expect(capturedPayloads.single.source, 'call_accept');
    });

    test('reject action delegates to rejectIncomingCall', () async {
      final adapter = _FakeCallkitAdapter();
      final service = _testService();

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(adapter.build());
      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'call_action',
        'action': 'reject',
        'callId': 'call-reject',
        'fromPeerId': 'peer-r',
      });

      expect(adapter.rejectCalls, 1);
      expect(adapter.acceptCalls, 0);
      expect(adapter.endCalls, 0);
    });

    test('end action delegates to endCall', () async {
      final adapter = _FakeCallkitAdapter();
      final service = _testService();

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(adapter.build());
      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'call_action',
        'action': 'end',
        'callId': 'call-end',
        'fromPeerId': 'peer-e',
      });

      expect(adapter.endCalls, 1);
      expect(adapter.acceptCalls, 0);
      expect(adapter.rejectCalls, 0);
    });

    test('audio session activated reapplies current speaker route', () async {
      final adapter = _FakeCallkitAdapter(
        initialState: const CallState(
          phase: CallPhase.active,
          callId: 'call-3',
          peerId: 'peer-c',
          direction: CallDirection.outgoing,
          speakerOn: true,
        ),
      );
      final service = _testService();

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(adapter.build());
      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'audio_session_activated',
      });

      expect(adapter.speakerUpdates, <bool>[true]);
    });

    test('open_call_screen emits stream event', () async {
      final adapter = _FakeCallkitAdapter();
      final service = _testService();
      final openEvents = <int>[];
      StreamSubscription<void>? subscription;

      addTearDown(() async {
        await subscription?.cancel();
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(adapter.build());
      subscription = service.onOpenCallScreen.listen((_) {
        openEvents.add(openEvents.length + 1);
      });

      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'open_call_screen',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(openEvents, hasLength(1));
    });

    test('voip_token event triggers push token registration flow', () async {
      final adapter = _FakeCallkitAdapter();
      final service = _testService();

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(adapter.build());
      await service.handleNativeEventForTesting(<String, dynamic>{
        'type': 'voip_token',
        'token': 'token-123',
      });

      expect(adapter.registerPushTokenCalls, 1);
      expect(adapter.lastRegisteredPushToken, isNull);
    });

    test('outgoing call state reports start and connected update', () async {
      final adapter = _FakeCallkitAdapter();
      final service = _testService();
      final recordedMethodCalls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        recordedMethodCalls.add(call);
        switch (call.method) {
          case 'refreshVoipRegistration':
            return null;
          case 'getVoipToken':
            return null;
          case 'startOutgoingCall':
            return null;
          case 'updateOutgoingCall':
            return null;
          case 'endSystemCall':
            return null;
        }
        return null;
      });

      addTearDown(() async {
        await service.dispose();
        await adapter.close();
      });

      await service.initializeWithAdapter(adapter.build());
      adapter.emitState(
        const CallState(
          phase: CallPhase.outgoingRinging,
          callId: 'call-4',
          peerId: 'peer-d',
          direction: CallDirection.outgoing,
          mediaType: CallMediaType.video,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      adapter.emitState(
        const CallState(
          phase: CallPhase.active,
          callId: 'call-4',
          peerId: 'peer-d',
          direction: CallDirection.outgoing,
          mediaType: CallMediaType.video,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final startCalls = recordedMethodCalls
          .where((call) => call.method == 'startOutgoingCall')
          .toList(growable: false);
      final updateCalls = recordedMethodCalls
          .where((call) => call.method == 'updateOutgoingCall')
          .toList(growable: false);

      expect(startCalls, hasLength(1));
      expect(startCalls.single.arguments['callId'], 'call-4');
      expect(startCalls.single.arguments['peerId'], 'peer-d');
      expect(startCalls.single.arguments['mediaType'], 'video');
      expect(updateCalls, hasLength(1));
      expect(updateCalls.single.arguments['callId'], 'call-4');
      expect(updateCalls.single.arguments['connected'], isTrue);
    });
  });
}
