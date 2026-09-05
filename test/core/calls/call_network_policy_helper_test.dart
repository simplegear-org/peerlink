import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_network_policy_helper.dart';
import 'package:peerlink/core/transport/transport_mode.dart';
import 'package:peerlink/core/turn/turn_allocator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CallNetworkPolicyHelper', () {
    test('preferredInitialMode returns turn when TURN is available', () async {
      final allocator = TurnAllocator()
        ..registerServer(
          url: 'turn:relay.example.com:3478?transport=udp',
          username: 'u',
          password: 'p',
        );
      final logs = <String>[];
      final helper = CallNetworkPolicyHelper(
        connectivity: Connectivity(),
        turnAllocator: allocator,
        directConnectAttemptTimeout: const Duration(seconds: 3),
        turnConnectAttemptTimeout: const Duration(seconds: 5),
      );

      final mode = await helper.preferredInitialMode(log: logs.add);

      expect(mode, TransportMode.turn);
      expect(
        logs.any((message) => message.contains('TURN available=true')),
        isTrue,
      );
      expect(
        logs.any((message) => message.contains('preferredMode=turn')),
        isTrue,
      );
    });

    test('preferredInitialMode throws when TURN is unavailable', () async {
      final logs = <String>[];
      final helper = CallNetworkPolicyHelper(
        connectivity: Connectivity(),
        turnAllocator: TurnAllocator(),
        directConnectAttemptTimeout: const Duration(seconds: 3),
        turnConnectAttemptTimeout: const Duration(seconds: 5),
      );

      await expectLater(
        () => helper.preferredInitialMode(log: logs.add),
        throwsA(isA<StateError>()),
      );
      expect(
        logs.any((message) => message.contains('TURN unavailable')),
        isTrue,
      );
    });

    test('timeoutForMode and transportLabelFor map modes correctly', () {
      final helper = CallNetworkPolicyHelper(
        connectivity: Connectivity(),
        turnAllocator: null,
        directConnectAttemptTimeout: const Duration(seconds: 3),
        turnConnectAttemptTimeout: const Duration(seconds: 5),
      );

      expect(
        helper.timeoutForMode(TransportMode.direct),
        const Duration(seconds: 3),
      );
      expect(
        helper.timeoutForMode(TransportMode.turn),
        const Duration(seconds: 5),
      );
      expect(
        helper.transportLabelFor(TransportMode.direct),
        'Прямое соединение',
      );
      expect(helper.transportLabelFor(TransportMode.turn), 'TURN relay');
    });
  });
}
