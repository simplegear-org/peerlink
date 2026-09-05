import 'package:peerlink/app/push/app_push_coordinator.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/firebase/firebase_messaging_service.dart';
import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/runtime/moderation_policy_service.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    FirebaseMessagingService.onGroupMembersUpdateFromPush = null;
    FirebaseMessagingService.onModerationPolicyFromPush = null;
    FirebaseMessagingService.onPushOpened = null;
  });

  test('call invite opens calls tab and presents incoming call', () async {
    final facade = _FakeNodeFacade();
    var callsTabShown = false;
    var badgeRefreshed = false;
    var routeSynced = false;
    final coordinator = AppPushCoordinator(
      calls: facade,
      network: facade,
      onGroupMembersUpdate: (_, {sourcePeerId}) async {},
      onModerationPolicy: (_, {required source}) async {},
      shouldDropExternalInteraction: (_) => false,
      shouldDropOpenedPush: (_, {required source}) => false,
      refreshMissedCallsBadge: ({required markSeen}) async {
        badgeRefreshed = markSeen;
      },
      syncCallRoute: (_) async {
        routeSynced = true;
      },
      canHandleExternalInteraction: () => true,
      showCallsTab: () {
        callsTabShown = true;
      },
      showChatsTab: () {},
    );

    coordinator.register();
    await FirebaseMessagingService.onPushOpened!.call({
      'type': 'call_invite',
      'fromPeerId': 'peer-a',
      'callId': 'call-1',
      'mediaType': 'video',
    }, source: 'opened');
    await Future<void>.delayed(Duration.zero);

    expect(facade.presentedIncomingPeerId, 'peer-a');
    expect(facade.presentedIncomingCallId, 'call-1');
    expect(facade.presentedIncomingMediaType, CallMediaType.video);
    expect(callsTabShown, isTrue);
    expect(badgeRefreshed, isTrue);
    expect(routeSynced, isTrue);
  });

  test(
    'foreground message push polls relay without opening chats tab',
    () async {
      final facade = _FakeNodeFacade();
      var chatsTabShown = false;
      final coordinator = AppPushCoordinator(
        calls: facade,
        network: facade,
        onGroupMembersUpdate: (_, {sourcePeerId}) async {},
        onModerationPolicy: (_, {required source}) async {},
        shouldDropExternalInteraction: (_) => false,
        shouldDropOpenedPush: (_, {required source}) => false,
        refreshMissedCallsBadge: ({required markSeen}) async {},
        syncCallRoute: (_) async {},
        canHandleExternalInteraction: () => true,
        showCallsTab: () {},
        showChatsTab: () {
          chatsTabShown = true;
        },
      );

      coordinator.register();
      await FirebaseMessagingService.onPushOpened!.call({
        'type': 'message',
        'fromPeerId': 'peer-a',
      }, source: 'foreground');

      expect(facade.polls, 2);
      expect(chatsTabShown, isFalse);
    },
  );

  test('dispose clears registered firebase callbacks', () {
    final coordinator = AppPushCoordinator(
      calls: _FakeNodeFacade(),
      network: _FakeNodeFacade(),
      onGroupMembersUpdate: (_, {sourcePeerId}) async {},
      onModerationPolicy: (_, {required source}) async {},
      shouldDropExternalInteraction: (_) => false,
      shouldDropOpenedPush: (_, {required source}) => false,
      refreshMissedCallsBadge: ({required markSeen}) async {},
      syncCallRoute: (_) async {},
      canHandleExternalInteraction: () => true,
      showCallsTab: () {},
      showChatsTab: () {},
    );

    coordinator.register();
    expect(FirebaseMessagingService.onPushOpened, isNotNull);
    expect(FirebaseMessagingService.onGroupMembersUpdateFromPush, isNotNull);
    expect(FirebaseMessagingService.onModerationPolicyFromPush, isNotNull);

    coordinator.dispose();

    expect(FirebaseMessagingService.onPushOpened, isNull);
    expect(FirebaseMessagingService.onGroupMembersUpdateFromPush, isNull);
    expect(FirebaseMessagingService.onModerationPolicyFromPush, isNull);
  });

  test('moderation policy push is dispatched through coordinator', () async {
    final snapshot = ModerationPolicySnapshot.clear().copyWith(
      state: ModerationPolicyState.warning,
    );
    ModerationPolicySnapshot? receivedSnapshot;
    String? receivedSource;
    final coordinator = AppPushCoordinator(
      calls: _FakeNodeFacade(),
      network: _FakeNodeFacade(),
      onGroupMembersUpdate: (_, {sourcePeerId}) async {},
      onModerationPolicy: (snapshot, {required source}) async {
        receivedSnapshot = snapshot;
        receivedSource = source;
      },
      shouldDropExternalInteraction: (_) => false,
      shouldDropOpenedPush: (_, {required source}) => false,
      refreshMissedCallsBadge: ({required markSeen}) async {},
      syncCallRoute: (_) async {},
      canHandleExternalInteraction: () => true,
      showCallsTab: () {},
      showChatsTab: () {},
    );

    coordinator.register();
    await FirebaseMessagingService.onModerationPolicyFromPush!.call(
      snapshot,
      source: 'foreground',
    );

    expect(receivedSnapshot, same(snapshot));
    expect(receivedSource, 'foreground');
  });
}

class _FakeNodeFacade implements CallsApi, NetworkApi {
  String? presentedIncomingPeerId;
  String? presentedIncomingCallId;
  CallMediaType? presentedIncomingMediaType;
  int polls = 0;

  @override
  CallState get callState => const CallState(
    phase: CallPhase.incomingRinging,
    peerId: 'peer-a',
    callId: 'call-1',
    direction: CallDirection.incoming,
  );

  @override
  Future<void> presentIncomingCallFromPush({
    required String peerId,
    required String callId,
    CallMediaType mediaType = CallMediaType.audio,
  }) async {
    presentedIncomingPeerId = peerId;
    presentedIncomingCallId = callId;
    presentedIncomingMediaType = mediaType;
  }

  @override
  Future<void> endCallFromRemotePush({
    required String peerId,
    required String callId,
  }) async {}

  @override
  Future<int> pollRelay({List<String>? relayServers}) async {
    polls++;
    return 0;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
