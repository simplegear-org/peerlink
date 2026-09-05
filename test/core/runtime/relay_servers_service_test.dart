import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/relay_servers_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

void main() {
  test('add normalizes relay host to https default port', () async {
    expect(
      RelayServersService.normalizeEndpoint('relay.example.org'),
      'https://relay.example.org:444',
    );
  });

  test('refreshAvailability requires both health and relay probe', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      if (request.uri.path == '/health' && request.method == 'GET') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
        return;
      }
      if (request.uri.path == '/relay/probe' && request.method == 'POST') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"ok":true,"protocolVersion":"1"}');
        await request.response.close();
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final endpoint = 'http://${server.address.address}:${server.port}';
    final service = RelayServersService(
      facade: _FakeNodeFacade(),
      storage: StorageService(),
    );
    addTearDown(service.dispose);
    service.endpoints.add(endpoint);

    await service.refreshAvailability();

    final availability = service.availabilityFor(endpoint);
    expect(availability.isAvailable, isTrue);
  });

  test('refreshAvailability rejects health-only relay endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      if (request.uri.path == '/health' && request.method == 'GET') {
        request.response.statusCode = HttpStatus.ok;
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final endpoint = 'http://${server.address.address}:${server.port}';
    final service = RelayServersService(
      facade: _FakeNodeFacade(),
      storage: StorageService(),
    );
    addTearDown(service.dispose);
    service.endpoints.add(endpoint);

    await service.refreshAvailability();

    final availability = service.availabilityFor(endpoint);
    expect(availability.isAvailable, isFalse);
    expect(availability.error, contains('probe status 404'));
  });

  test(
    'refreshAvailability treats hanging relay probe as unavailable',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) {
        // Keep the response open to simulate a relay health endpoint that hangs.
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final endpoint = 'http://${server.address.address}:${server.port}';
      final service = RelayServersService(
        facade: _FakeNodeFacade(),
        storage: StorageService(),
        probeTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(service.dispose);
      service.endpoints.add(endpoint);

      await service.refreshAvailability();

      final availability = service.availabilityFor(endpoint);
      expect(availability.isAvailable, isFalse);
      expect(availability.error, contains('таймаут'));
    },
  );

  test('refreshAvailability skips overlapping relay probe runs', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requestCount = 0;
    final subscription = server.listen((request) {
      requestCount++;
      // Keep the first probe in flight long enough for the overlap attempt.
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final endpoint = 'http://${server.address.address}:${server.port}';
    final service = RelayServersService(
      facade: _FakeNodeFacade(),
      storage: StorageService(),
      probeTimeout: const Duration(milliseconds: 60),
    );
    addTearDown(service.dispose);
    service.endpoints.add(endpoint);

    final firstRefresh = service.refreshAvailability();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.refreshAvailability();
    await firstRefresh;

    expect(requestCount, 1);
  });
}

class _FakeNodeFacade implements NodeFacade {
  final List<String> configuredRelayServers = <String>[];

  @override
  List<String> get relayServers =>
      List<String>.unmodifiable(configuredRelayServers);

  @override
  Future<void> configureRelayServers(List<String> endpoints) async {
    configuredRelayServers
      ..clear()
      ..addAll(endpoints);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
