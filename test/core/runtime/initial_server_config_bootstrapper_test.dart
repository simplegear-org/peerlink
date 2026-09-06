import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/bootstrap_servers_service.dart';
import 'package:peerlink/core/runtime/initial_server_config_bootstrapper.dart';
import 'package:peerlink/core/runtime/push_servers_service.dart';
import 'package:peerlink/core/runtime/relay_servers_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/runtime/turn_servers_service.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peerlink-config-test-');
    await StorageService.resetForTesting();
    addTearDown(() async {
      await StorageService.resetForTesting();
      await root.delete(recursive: true);
    });
  });

  test(
    'imports remote initial server config when all server lists are empty',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        expect(request.uri.path, '/config/initial-server-config.json');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(<String, dynamic>{
            'type': 'peerlink_server_config',
            'version': 1,
            'bootstrap': <String>['wss://bootstrap.example'],
            'relay': <String>['https://relay.example:444'],
            'turn': <Map<String, dynamic>>[
              <String, dynamic>{
                'url': 'turn:turn.example:3478?transport=tcp',
                'username': 'peerlink',
                'password': 'peerlink',
                'priority': 10,
              },
            ],
            'push': <String>['https://push.example'],
          }),
        );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final facade = _FakeNodeFacade();
      final storage = StorageService();
      await storage.initForTesting(rootDirectory: root);
      final bootstrap = BootstrapServersService(
        facade: facade,
        storage: storage,
      );
      final relay = RelayServersService(facade: facade, storage: storage);
      final turn = TurnServersService(facade: facade, storage: storage);
      final push = PushServersService(storage: storage);
      addTearDown(bootstrap.dispose);
      addTearDown(relay.dispose);
      addTearDown(turn.dispose);
      addTearDown(push.dispose);

      await InitialServerConfigBootstrapper(
        bootstrap: bootstrap,
        relay: relay,
        turn: turn,
        push: push,
        configUri: Uri.parse(
          'http://${server.address.address}:${server.port}/config/initial-server-config.json',
        ),
      ).importIfEmpty();

      expect(facade.configuredBootstrapServers, <String>[
        'wss://bootstrap.example',
      ]);
      expect(facade.configuredRelayServers, <String>[
        'https://relay.example:444',
      ]);
      expect(
        facade.configuredTurnServers.single.url,
        'turn:turn.example:3478?transport=tcp',
      );
      expect(push.endpoints, <String>['https://push.example']);
    },
  );

  test('skips remote fetch when any server is already configured', () async {
    var requestCount = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((request) async {
      requestCount++;
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close(force: true);
    });

    final facade = _FakeNodeFacade();
    final storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    final bootstrap = BootstrapServersService(facade: facade, storage: storage)
      ..endpoints.add('wss://existing.example');
    final relay = RelayServersService(facade: facade, storage: storage);
    final turn = TurnServersService(facade: facade, storage: storage);
    final push = PushServersService(storage: storage);
    addTearDown(bootstrap.dispose);
    addTearDown(relay.dispose);
    addTearDown(turn.dispose);
    addTearDown(push.dispose);

    await InitialServerConfigBootstrapper(
      bootstrap: bootstrap,
      relay: relay,
      turn: turn,
      push: push,
      configUri: Uri.parse(
        'http://${server.address.address}:${server.port}/config/initial-server-config.json',
      ),
    ).importIfEmpty();

    expect(requestCount, 0);
    expect(facade.configuredBootstrapServers, isEmpty);
  });
}

class _FakeNodeFacade implements NodeFacade {
  final List<String> configuredBootstrapServers = <String>[];
  final List<String> configuredRelayServers = <String>[];
  final List<TurnServerConfig> configuredTurnServers = <TurnServerConfig>[];

  @override
  List<String> get bootstrapServers =>
      List<String>.unmodifiable(configuredBootstrapServers);

  @override
  List<String> get relayServers =>
      List<String>.unmodifiable(configuredRelayServers);

  @override
  List<TurnServerConfig> get turnServers =>
      List<TurnServerConfig>.unmodifiable(configuredTurnServers);

  @override
  Future<void> configureBootstrapServers(List<String> endpoints) async {
    configuredBootstrapServers
      ..clear()
      ..addAll(endpoints);
  }

  @override
  Future<void> configureRelayServers(List<String> endpoints) async {
    configuredRelayServers
      ..clear()
      ..addAll(endpoints);
  }

  @override
  Future<void> configureTurnServers(List<TurnServerConfig> servers) async {
    configuredTurnServers
      ..clear()
      ..addAll(servers);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
