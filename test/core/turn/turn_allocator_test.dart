import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/server_availability.dart';
import 'package:peerlink/core/turn/turn_allocator.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

void main() {
  group('TurnAllocator', () {
    test(
      'allocateAll excludes unavailable servers when healthy ones exist',
      () {
        final allocator = TurnAllocator()
          ..configureServers(const <TurnServerConfig>[
            TurnServerConfig(
              url: 'turn:peerlink.club:3478?transport=udp',
              username: 'peerlink',
              password: 'secret',
            ),
            TurnServerConfig(
              url: 'turn:peerlink.club:3478?transport=tcp',
              username: 'peerlink',
              password: 'secret',
            ),
            TurnServerConfig(
              url: 'turn:176.109.100.203:3478?transport=udp',
              username: 'peerlink',
              password: 'secret',
            ),
            TurnServerConfig(
              url: 'turn:176.109.100.203:3478?transport=tcp',
              username: 'peerlink',
              password: 'secret',
            ),
          ])
          ..setAvailabilityLookup((url) {
            if (url.contains('peerlink.club')) {
              return ServerAvailability.available(checkedAt: DateTime.now());
            }
            return ServerAvailability.unavailable(
              error: 'offline',
              checkedAt: DateTime.now(),
            );
          });

        final urls = allocator.allocateAll().map((creds) => creds.url).toList();

        expect(urls, contains('turn:peerlink.club:3478?transport=udp'));
        expect(urls, contains('turn:peerlink.club:3478?transport=tcp'));
        expect(urls.any((url) => url.contains('176.109.100.203')), isFalse);
      },
    );

    test(
      'reportFailure removes failed URL from allocation when another works',
      () {
        final allocator = TurnAllocator()
          ..configureServers(const <TurnServerConfig>[
            TurnServerConfig(
              url: 'turn:peerlink.club:3478?transport=udp',
              username: 'peerlink',
              password: 'secret',
            ),
            TurnServerConfig(
              url: 'turn:peerlink.club:3478?transport=tcp',
              username: 'peerlink',
              password: 'secret',
            ),
          ]);

        allocator.reportFailure('turn:peerlink.club:3478?transport=udp');

        final urls = allocator.allocateAll().map((creds) => creds.url).toList();

        expect(urls, ['turn:peerlink.club:3478?transport=tcp']);
      },
    );
  });
}
