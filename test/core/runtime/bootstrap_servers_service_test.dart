import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/bootstrap_servers_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

void main() {
  test(
    'normalizeEndpoint strips arbitrary scheme and defaults public host to wss',
    () {
      expect(
        BootstrapServersService.normalizeEndpoint('we://signal.tkm795.com'),
        'wss://signal.tkm795.com',
      );
      expect(
        BootstrapServersService.normalizeEndpoint('signal.tkm795.com'),
        'wss://signal.tkm795.com',
      );
    },
  );

  test('normalizeEndpoint keeps local addresses on ws', () {
    expect(
      BootstrapServersService.normalizeEndpoint('127.0.0.1:9000'),
      'ws://127.0.0.1:9000',
    );
    expect(
      BootstrapServersService.normalizeEndpoint('localhost:8080'),
      'ws://localhost:8080',
    );
  });

  test(
    'refreshAvailability treats hanging websocket probe as unavailable',
    () async {
      const endpoint = 'wss://bootstrap.example';
      final service = BootstrapServersService(
        facade: _FakeNodeFacade(),
        storage: StorageService(),
        probeTimeout: const Duration(milliseconds: 20),
        webSocketConnector: (_, {customClient}) =>
            Completer<WebSocket>().future,
      );
      addTearDown(service.dispose);
      service.endpoints.add(endpoint);

      await service.refreshAvailability();

      final availability = service.availabilityFor(endpoint);
      expect(availability.isAvailable, isFalse);
      expect(availability.error, contains('таймаут'));
    },
  );

  test('refreshAvailability skips overlapping probe runs', () async {
    const endpoint = 'wss://bootstrap.example';
    var connectCount = 0;
    final service = BootstrapServersService(
      facade: _FakeNodeFacade(),
      storage: StorageService(),
      probeTimeout: const Duration(milliseconds: 40),
      webSocketConnector: (_, {customClient}) {
        connectCount++;
        return Completer<WebSocket>().future;
      },
    );
    addTearDown(service.dispose);
    service.endpoints.add(endpoint);

    final firstRefresh = service.refreshAvailability();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.refreshAvailability();
    await firstRefresh;

    expect(connectCount, 1);
  });

  test(
    'refreshAvailability treats successful websocket handshake as available',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        await server.close(force: true);
      });
      final subscription = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        unawaited(
          socket.drain<void>().whenComplete(() async {
            await socket.close();
          }),
        );
      });
      addTearDown(() async {
        await subscription.cancel();
      });

      final endpoint = 'ws://127.0.0.1:${server.port}';
      final service = BootstrapServersService(
        facade: _FakeNodeFacade(),
        storage: StorageService(),
        probeTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(service.dispose);
      service.endpoints.add(endpoint);

      await service.refreshAvailability();

      final availability = service.availabilityFor(endpoint);
      expect(availability.isAvailable, isTrue);
    },
  );
}

class _FakeNodeFacade implements NodeFacade {
  final List<String> configuredBootstrapServers = <String>[];

  @override
  List<String> get bootstrapServers =>
      List<String>.unmodifiable(configuredBootstrapServers);

  @override
  Future<void> configureBootstrapServers(List<String> endpoints) async {
    configuredBootstrapServers
      ..clear()
      ..addAll(endpoints);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
