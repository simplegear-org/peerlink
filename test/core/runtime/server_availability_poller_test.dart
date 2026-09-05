import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/server_availability.dart';
import 'package:peerlink/core/runtime/server_availability_poller.dart';

void main() {
  test(
    'scheduled refresh respects retry backoff for unavailable servers',
    () async {
      final serverKeys = <String>['relay-a'];
      var probeCount = 0;
      final poller = ServerAvailabilityPoller(
        providerKey: 'test',
        serverKeysProvider: () => serverKeys,
        probe: (_) async {
          probeCount += 1;
          return ServerAvailability.unavailable(
            error: 'offline',
            checkedAt: DateTime.now(),
          );
        },
        seedAvailability: (_) => const ServerAvailability.unknown(),
        healthyProbeInterval: const Duration(milliseconds: 20),
        initialRetryDelay: const Duration(milliseconds: 40),
        maxRetryDelay: const Duration(milliseconds: 100),
      );
      addTearDown(poller.dispose);

      poller.syncKeys();
      await poller.refreshAvailability();
      expect(probeCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await poller.runScheduledRefresh();
      expect(probeCount, 1);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(probeCount, greaterThanOrEqualTo(2));
    },
  );
}
