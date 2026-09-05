import 'package:test/test.dart';

import 'architecture_test_utils.dart';

void main() {
  test(
    'presentation/state code does not instantiate infrastructure services',
    () {
      final sources = dartSourcesUnder(const [
        'lib/ui/screens',
        'lib/ui/state',
      ]);

      final violations = constructorCallViolations(sources, const [
        'StorageService',
        'NetworkDependencies',
        'FirebaseMessagingService',
        'HttpRelayClient',
        'PushApiClient',
        'ModerationApiClient',
        'BootstrapSignalingService',
        'MultiBootstrapSignalingService',
        'TransportManager',
        'TurnAllocator',
        'WebRtcTransport',
      ]);

      expect(
        violations,
        isEmpty,
        reason:
            'UI presentation/state must receive infrastructure through app '
            'composition or narrow injected APIs.',
      );
    },
  );

  test('migrated call screen depends on CallsApi instead of NodeFacade', () {
    final sources = dartSourcesUnder(const ['lib/ui/screens']).where(
      (source) => {
        'lib/ui/screens/call_screen.dart',
        'lib/ui/screens/call_screen_view.dart',
      }.contains(source.path),
    );
    final violations = <String>[];
    for (final source in sources) {
      for (final import in source.imports()) {
        final resolved = import.resolvePeerlinkPath();
        if (resolved == 'lib/core/node/node_facade.dart') {
          violations.add(import.location);
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'The active call presentation surface should depend on CallsApi, '
          'not unrestricted NodeFacade.',
    );
  });
}
