import '../../core/runtime/server_config_payload.dart';
import '../../core/runtime/server_health_coordinator.dart';
import '../../core/turn/turn_server_config.dart';
import 'settings_controller_models.dart';

class SettingsServerConfigService {
  final ServerHealthCoordinator health;

  const SettingsServerConfigService({required this.health});

  Future<void> addBootstrap(String peer) async {
    await health.bootstrap.add(peer);
  }

  Future<void> removeBootstrap(String peer) async {
    await health.bootstrap.remove(peer);
  }

  Future<void> addRelay(String endpoint) async {
    await health.relay.add(endpoint);
  }

  Future<void> removeRelay(String endpoint) async {
    await health.relay.remove(endpoint);
  }

  Future<void> addTurnServer(TurnServerConfig server) async {
    await health.turn.add(server);
  }

  Future<void> removeTurnServer(String url) async {
    await health.turn.remove(url);
  }

  Future<void> addPushServer(String endpoint) async {
    await health.push.add(endpoint);
  }

  Future<void> removePushServer(String endpoint) async {
    await health.push.remove(endpoint);
  }

  Future<void> updatePushServer(
    String currentEndpoint, {
    required String host,
    int? port,
  }) async {
    await health.push.update(currentEndpoint, host: host, port: port);
  }

  Future<void> pausePushServer(String endpoint) async {
    await health.push.setPaused(endpoint, paused: true);
  }

  Future<void> resumePushServer(String endpoint) async {
    await health.push.setPaused(endpoint, paused: false);
  }

  ServerConfigImportPreview previewImport(ServerConfigPayload payload) {
    final bootstrapNew = payload.bootstrap
        .where((endpoint) => !health.bootstrapEndpoints.contains(endpoint))
        .length;
    final relayNew = payload.relay
        .where((endpoint) => !health.relayEndpoints.contains(endpoint))
        .length;
    final turnNew = payload.turn
        .where(
          (server) =>
              !health.turnServers.any((entry) => entry.url == server.url),
        )
        .length;
    final pushNew = payload.push
        .where((endpoint) => !health.pushEndpoints.contains(endpoint))
        .length;

    return ServerConfigImportPreview(
      bootstrapTotal: payload.bootstrap.length,
      relayTotal: payload.relay.length,
      turnTotal: payload.turn.length,
      pushTotal: payload.push.length,
      bootstrapNew: bootstrapNew,
      relayNew: relayNew,
      turnNew: turnNew,
      pushNew: pushNew,
    );
  }

  Future<void> importPayload(
    ServerConfigPayload payload, {
    required ServerConfigImportMode mode,
  }) async {
    if (mode == ServerConfigImportMode.replace) {
      await health.bootstrap.replace(payload.bootstrap);
      await health.relay.replace(payload.relay);
      await health.turn.replace(payload.turn);
      await health.push.replace(payload.push);
      return;
    }
    await health.bootstrap.merge(payload.bootstrap);
    await health.relay.merge(payload.relay);
    await health.turn.merge(payload.turn);
    await health.push.merge(payload.push);
  }

  Future<void> addSelfHostedServersFirst({
    required String bootstrapEndpoint,
    required String relayEndpoint,
    required List<TurnServerConfig> turnServers,
  }) async {
    final bootstrap = bootstrapEndpoint.trim();
    final relay = relayEndpoint.trim();
    final turns = turnServers
        .map((server) => server.copyWith(url: server.url.trim()))
        .where((server) => server.url.isNotEmpty)
        .toList(growable: false);
    if (bootstrap.isEmpty || relay.isEmpty || turns.isEmpty) {
      throw const FormatException('Некорректная конфигурация серверов');
    }

    await health.bootstrap.putFirst(bootstrap);
    await health.relay.putFirst(relay);
    await health.turn.putFirstMany(turns);
  }

  Future<void> clearSettingsOwnedServerData() async {
    await health.bootstrap.replace(const <String>[]);
    await health.relay.replace(const <String>[]);
    await health.turn.replace(const <TurnServerConfig>[]);
  }
}
