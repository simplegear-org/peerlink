import '../push/push_api_client.dart';
import '../relay/relay_server_status.dart';
import '../turn/turn_server_config.dart';

class PushRuntimeMetadataBuilder {
  PushRuntimeMetadataBuilder({
    required this.connectedBootstrapServers,
    required this.activeBootstrapServer,
    required this.relayServerStatuses,
    required this.activePushBaseUri,
    required this.turnServers,
    required this.isTurnServerHealthy,
    required this.connectedTargetBootstrapServersForPeer,
    required this.healthyOrderedTurnServerConfigs,
    required this.log,
  });

  final List<String> Function() connectedBootstrapServers;
  final String? Function() activeBootstrapServer;
  final List<RelayServerStatus> Function() relayServerStatuses;
  final Uri? Function() activePushBaseUri;
  final List<TurnServerConfig> Function() turnServers;
  final bool? Function(String url) isTurnServerHealthy;
  final List<String> Function(String peerId) connectedTargetBootstrapServersForPeer;
  final List<TurnServerConfig> Function() healthyOrderedTurnServerConfigs;
  final void Function(String message) log;

  PushServersMetadata? collectAvailableServers() {
    final connectedBootstrap = connectedBootstrapServers();
    final fallbackBootstrap = activeBootstrapServer();
    final bootstrap = connectedBootstrap.isNotEmpty
        ? connectedBootstrap
        : (fallbackBootstrap == null ? const <String>[] : <String>[fallbackBootstrap]);
    final availableRelay =
        relayServerStatuses()
            .where((status) => status.healthy)
            .map((status) => status.url.trim())
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    final activePush = activePushBaseUri()?.toString();
    final availablePush = activePush == null
        ? const <String>[]
        : <String>[activePush];
    final availableTurn =
        turnServers()
            .where((server) => isTurnServerHealthy(server.url) == true)
            .toList(growable: false);
    if (bootstrap.isEmpty &&
        availableRelay.isEmpty &&
        availablePush.isEmpty &&
        availableTurn.isEmpty) {
      return null;
    }
    return PushServersMetadata(
      bootstrap: bootstrap,
      relay: availableRelay,
      push: availablePush,
      turn: availableTurn,
    );
  }

  PushServersMetadata? collectPriorityCallServers(String calleeUserId) {
    final bootstrap = connectedTargetBootstrapServersForPeer(calleeUserId.trim());
    final turn = List<TurnServerConfig>.from(healthyOrderedTurnServerConfigs());
    if (bootstrap.isEmpty && turn.isEmpty) {
      return null;
    }
    return PushServersMetadata(
      bootstrap: bootstrap,
      relay: const <String>[],
      push: const <String>[],
      turn: turn,
    );
  }

  Map<String, dynamic> buildCallInviteRuntimeMetadata(String calleeUserId) {
    final servers = collectAvailableServers();
    final priorityServers = collectPriorityCallServers(calleeUserId);
    final payload = <String, dynamic>{};
    if (servers != null) {
      payload['servers'] = <String, dynamic>{
        'bootstrap': servers.bootstrap,
        'relay': servers.relay,
        'push': servers.push,
        'turn': servers.turn
            .map((item) => item.toJson())
            .toList(growable: false),
      };
    }
    if (priorityServers != null) {
      payload['priority_servers'] = <String, dynamic>{
        'bootstrap': priorityServers.bootstrap,
        'relay': priorityServers.relay,
        'push': priorityServers.push,
        'turn': priorityServers.turn
            .map((item) => item.toJson())
            .toList(growable: false),
      };
    }
    log(
      'callInvite:metadata callee=$calleeUserId '
      'serversTurn=${servers?.turn.length ?? 0} '
      'priorityBootstrap=${priorityServers?.bootstrap.length ?? 0} '
      'priorityTurn=${priorityServers?.turn.length ?? 0}',
    );
    return payload;
  }
}
