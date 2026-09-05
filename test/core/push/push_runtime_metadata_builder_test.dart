import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/push/push_runtime_metadata_builder.dart';
import 'package:peerlink/core/relay/relay_server_status.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

void main() {
  group('PushRuntimeMetadataBuilder', () {
    test('collectAvailableServers publishes all active push servers', () {
      final builder = PushRuntimeMetadataBuilder(
        connectedBootstrapServers: () => const <String>[],
        activeBootstrapServer: () => null,
        relayServerStatuses: () => const [],
        activePushBaseUris: () => <Uri>[
          Uri.parse('https://push-b.example.com:445'),
          Uri.parse('https://push-a.example.com:445'),
          Uri.parse('https://push-a.example.com:445'),
        ],
        turnServers: () => const [],
        isTurnServerHealthy: (_) => false,
        connectedTargetBootstrapServersForPeer: (_) => const <String>[],
        healthyOrderedTurnServerConfigs: () => const [],
        log: (_) {},
      );

      final servers = builder.collectAvailableServers();

      expect(servers, isNotNull);
      expect(servers!.push, <String>[
        'https://push-a.example.com:445',
        'https://push-b.example.com:445',
      ]);
    });

    test('collectAvailableServers publishes all available server types', () {
      const healthyTurn = TurnServerConfig(
        url: 'turn:turn.available.example:3478?transport=tcp',
        username: 'turn-user',
        password: 'turn-secret',
      );
      const offlineTurn = TurnServerConfig(
        url: 'turn:turn.offline.example:3478?transport=tcp',
        username: 'turn-user',
        password: 'turn-secret',
      );
      final builder = PushRuntimeMetadataBuilder(
        connectedBootstrapServers: () => const <String>[
          'wss://bootstrap-a.example.com',
          'wss://bootstrap-b.example.com',
        ],
        activeBootstrapServer: () => null,
        relayServerStatuses: () => const <RelayServerStatus>[
          RelayServerStatus(
            url: 'https://relay.available.example.com:444',
            healthy: true,
          ),
          RelayServerStatus(
            url: 'https://relay.offline.example.com:444',
            healthy: false,
          ),
        ],
        activePushBaseUris: () => <Uri>[
          Uri.parse('https://push-a.example.com:445'),
          Uri.parse('https://push-b.example.com:445'),
        ],
        turnServers: () => const <TurnServerConfig>[healthyTurn, offlineTurn],
        isTurnServerHealthy: (url) => url == healthyTurn.url,
        connectedTargetBootstrapServersForPeer: (_) => const <String>[],
        healthyOrderedTurnServerConfigs: () => const [],
        log: (_) {},
      );

      final servers = builder.collectAvailableServers();

      expect(servers, isNotNull);
      expect(servers!.bootstrap, const <String>[
        'wss://bootstrap-a.example.com',
        'wss://bootstrap-b.example.com',
      ]);
      expect(servers.relay, const <String>[
        'https://relay.available.example.com:444',
      ]);
      expect(servers.push, const <String>[
        'https://push-a.example.com:445',
        'https://push-b.example.com:445',
      ]);
      expect(servers.turn, const <TurnServerConfig>[healthyTurn]);
    });

    test('collectAvailableServers includes configured bootstrap servers', () {
      final builder = PushRuntimeMetadataBuilder(
        configuredBootstrapServers: () => const <String>[
          'wss://bootstrap-configured.example.com',
        ],
        connectedBootstrapServers: () => const <String>[],
        activeBootstrapServer: () => null,
        relayServerStatuses: () => const <RelayServerStatus>[
          RelayServerStatus(
            url: 'https://relay.available.example.com:444',
            healthy: true,
          ),
        ],
        activePushBaseUris: () => const <Uri>[],
        turnServers: () => const [],
        isTurnServerHealthy: (_) => false,
        connectedTargetBootstrapServersForPeer: (_) => const <String>[],
        healthyOrderedTurnServerConfigs: () => const [],
        log: (_) {},
      );

      final servers = builder.collectAvailableServers();

      expect(servers, isNotNull);
      expect(servers!.bootstrap, const <String>[
        'wss://bootstrap-configured.example.com',
      ]);
      expect(servers.relay, const <String>[
        'https://relay.available.example.com:444',
      ]);
    });
  });
}
