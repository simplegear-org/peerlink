import 'dart:async';

import 'package:peerlink/app/calls/app_call_coordinator.dart';
import 'package:peerlink/core/calls/call_log_entry.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/features/calls/platform/ios_callkit_service.dart';
import 'package:test/test.dart';

void main() {
  test('records terminal call once and refreshes missed badge', () async {
    final calls = _FakeCallsApi();
    final callkit = _FakeIosCallkitService();
    var records = 0;
    var historyChanges = 0;
    var badgeRefreshes = 0;
    final coordinator = AppCallCoordinator(
      calls: calls,
      canHandleExternalInteraction: () => true,
      recordCall: (_) async {
        records++;
      },
      logStatusFor: (_) => CallLogStatus.completed,
      syncCallRoute: (_) async {},
      refreshMissedCallsBadge: ({required markSeen}) async {
        badgeRefreshes++;
        expect(markSeen, isTrue);
      },
      isCallsTabSelected: () => true,
      showCallsTab: () {},
      onHistoryChanged: () {
        historyChanges++;
      },
      showError: (_) {},
      iosCallkitService: callkit,
    );

    coordinator.start();
    calls.emit(
      const CallState(
        phase: CallPhase.ended,
        peerId: 'peer-a',
        callId: 'call-1',
        direction: CallDirection.outgoing,
      ),
    );
    calls.emit(
      const CallState(
        phase: CallPhase.ended,
        peerId: 'peer-a',
        callId: 'call-1',
        direction: CallDirection.outgoing,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(records, 1);
    expect(historyChanges, 1);
    expect(badgeRefreshes, 1);
    await coordinator.dispose();
    await calls.dispose();
    await callkit.dispose();
  });
}

class _FakeCallsApi implements CallsApi {
  final _states = StreamController<CallState>.broadcast();

  @override
  CallState get callState => CallState.idle;

  @override
  Stream<CallState> get callStateStream => _states.stream;

  void emit(CallState state) {
    _states.add(state);
  }

  Future<void> dispose() => _states.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIosCallkitService implements IosCallkitService {
  final _openCallScreen = StreamController<void>.broadcast();

  @override
  Stream<void> get onOpenCallScreen => _openCallScreen.stream;

  @override
  Future<void> dispose() => _openCallScreen.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
