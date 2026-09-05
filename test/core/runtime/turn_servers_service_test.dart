import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/runtime/turn_servers_service.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

void main() {
  test('add normalizes turn host to turn default port', () async {
    expect(
      TurnServersService.normalizeTurnsEndpoint('turn.example.org'),
      'turn:turn.example.org:3478?transport=tcp',
    );
  });

  test(
    'normalizeTurnsEndpoint migrates legacy turns port 5349 to turn 3478',
    () async {
      expect(
        TurnServersService.normalizeTurnsEndpoint(
          'turns:213.171.27.236:5349?transport=tcp',
        ),
        'turns:213.171.27.236:5349?transport=tcp',
      );
    },
  );

  test('normalizeTurnsEndpoint preserves explicit udp transport', () async {
    expect(
      TurnServersService.normalizeTurnsEndpoint(
        'turn:turn.example.org:3478?transport=udp',
      ),
      'turn:turn.example.org:3478?transport=udp',
    );
  });

  test(
    'refreshAvailability treats silent UDP TURN probe as unavailable',
    () async {
      const url = 'turn:127.0.0.1:9?transport=udp';
      final service = TurnServersService(
        facade: _FakeNodeFacade(),
        storage: StorageService(),
        probeTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(service.dispose);
      service.servers.add(
        const TurnServerConfig(url: url, username: '', password: ''),
      );

      await service.refreshAvailability();

      final availability = service.availabilityFor(url);
      expect(availability.isAvailable, isFalse);
      expect(availability.error, contains('udp probe timeout'));
    },
  );

  test(
    'refreshAvailability treats silent TCP TURN probe as unavailable',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close();
      });
      final connections = <Socket>[];
      final subscription = server.listen((socket) {
        connections.add(socket);
      });
      addTearDown(() async {
        await subscription.cancel();
        for (final socket in connections) {
          socket.destroy();
        }
      });

      final url = 'turn:127.0.0.1:${server.port}?transport=tcp';
      final service = TurnServersService(
        facade: _FakeNodeFacade(),
        storage: StorageService(),
        probeTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(service.dispose);
      service.servers.add(
        TurnServerConfig(url: url, username: '', password: ''),
      );

      await service.refreshAvailability();

      final availability = service.availabilityFor(url);
      expect(availability.isAvailable, isFalse);
      expect(availability.error, contains('tcp probe timeout'));
    },
  );
}

class _FakeNodeFacade implements NodeFacade {
  final List<TurnServerConfig> configuredTurnServers = <TurnServerConfig>[];

  @override
  List<TurnServerConfig> get turnServers =>
      List<TurnServerConfig>.unmodifiable(configuredTurnServers);

  @override
  Future<void> configureTurnServers(List<TurnServerConfig> servers) async {
    configuredTurnServers
      ..clear()
      ..addAll(servers);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
