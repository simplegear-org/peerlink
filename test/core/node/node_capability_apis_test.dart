import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:test/test.dart';

void main() {
  test('NodeFacade satisfies narrow capability contracts', () {
    expect(_assertNodeFacadeContracts, isA<void Function(NodeFacade)>());
  });
}

void _assertNodeFacadeContracts(NodeFacade facade) {
  final IdentityApi identity = facade;
  final ModerationApi moderation = facade;
  final MessagingApi messaging = facade;
  final NetworkApi network = facade;
  final PresenceApi presence = facade;
  final CallsApi calls = facade;
  final RuntimeEventsApi events = facade;

  Object.hash(
    identity,
    moderation,
    messaging,
    network,
    presence,
    calls,
    events,
  );
}
