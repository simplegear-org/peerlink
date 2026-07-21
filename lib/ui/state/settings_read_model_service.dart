import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../core/runtime/server_availability.dart';
import '../../core/runtime/server_config_payload.dart';
import '../../core/runtime/server_health_coordinator.dart';
import '../../core/turn/turn_server_config.dart';
import '../localization/app_strings.dart';
import 'settings_controller_models.dart';
import 'settings_server_status_presenter.dart';

class SettingsReadModelService {
  final ServerHealthCoordinator health;
  final List<String> Function() connectedBootstrapServers;
  String _appVersionLabel = '—';

  SettingsReadModelService({
    required this.health,
    required this.connectedBootstrapServers,
  });

  List<String> get bootstrapPeers => health.bootstrapEndpoints;
  List<String> get relayServers => health.relayEndpoints;
  List<TurnServerConfig> get turnServers => health.turnServers;
  List<String> get pushServers => health.pushEndpoints;
  String get appVersionLabel => _appVersionLabel;

  List<String> get sortedBootstrapPeers {
    final items = List<String>.from(bootstrapPeers);
    items.sort((a, b) {
      final aConnected = connectedBootstrapServers().contains(a) ? 0 : 1;
      final bConnected = connectedBootstrapServers().contains(b) ? 0 : 1;
      if (aConnected != bConnected) {
        return aConnected.compareTo(bConnected);
      }
      final rank = SettingsServerStatusPresenter.rank(
        bootstrapState(a),
      ).compareTo(SettingsServerStatusPresenter.rank(bootstrapState(b)));
      if (rank != 0) {
        return rank;
      }
      return a.compareTo(b);
    });
    return items;
  }

  int get bootstrapAvailableCount => _countByState(
    bootstrapPeers,
    bootstrapState,
    SettingsServerState.connected,
  );

  int get bootstrapUnavailableCount => _countByState(
    bootstrapPeers,
    bootstrapState,
    SettingsServerState.unavailable,
  );

  int get relayAvailableCount =>
      _countByState(relayServers, relayState, SettingsServerState.connected);

  int get relayUnavailableCount =>
      _countByState(relayServers, relayState, SettingsServerState.unavailable);

  int get turnAvailableCount => turnServers
      .where((server) => turnState(server.url) == SettingsServerState.connected)
      .length;

  int get turnUnavailableCount => turnServers
      .where(
        (server) => turnState(server.url) == SettingsServerState.unavailable,
      )
      .length;

  List<String> get sortedRelayServers => _sortStrings(relayServers, relayState);

  List<TurnServerConfig> get sortedTurnServers {
    final items = List<TurnServerConfig>.from(turnServers);
    items.sort((a, b) {
      final rank = SettingsServerStatusPresenter.rank(
        turnState(a.url),
      ).compareTo(SettingsServerStatusPresenter.rank(turnState(b.url)));
      if (rank != 0) {
        return rank;
      }
      return a.url.compareTo(b.url);
    });
    return items;
  }

  List<String> get sortedPushServers => _sortStrings(pushServers, pushState);

  SettingsServerState bootstrapState(String endpoint) {
    return SettingsServerStatusPresenter.stateFromAvailability(
      health.bootstrapAvailabilityFor(endpoint),
    );
  }

  SettingsServerState relayState(String endpoint) {
    return SettingsServerStatusPresenter.stateFromAvailability(
      health.relayAvailabilityFor(endpoint),
    );
  }

  SettingsServerState turnState(String url) {
    return SettingsServerStatusPresenter.stateFromAvailability(
      health.turnAvailabilityFor(url),
    );
  }

  SettingsServerState pushState(String endpoint) {
    if (health.push.isPaused(endpoint)) {
      return SettingsServerState.paused;
    }
    return SettingsServerStatusPresenter.stateFromAvailability(
      health.pushAvailabilityFor(endpoint),
    );
  }

  bool isPushServerPaused(String endpoint) => health.push.isPaused(endpoint);

  String connectionStatusLabel(String endpoint, {AppStrings? strings}) {
    final availability = health.bootstrapAvailabilityFor(endpoint);
    final connected = connectedBootstrapServers().contains(endpoint);
    return SettingsServerStatusPresenter.label(
      availability,
      connected: connected,
      strings: strings,
    );
  }

  String relayStatusLabel(String endpoint, {AppStrings? strings}) {
    return _statusLabel(
      health.relayAvailabilityFor(endpoint),
      strings: strings,
    );
  }

  String turnStatusLabel(String url, {AppStrings? strings}) {
    return _statusLabel(health.turnAvailabilityFor(url), strings: strings);
  }

  String pushStatusLabel(String endpoint, {AppStrings? strings}) {
    if (health.push.isPaused(endpoint)) {
      return strings?.serverPausedStatus ?? 'на паузе';
    }
    return _statusLabel(health.pushAvailabilityFor(endpoint), strings: strings);
  }

  String exportServerConfigQrPayload() {
    final availableBootstrap = bootstrapPeers
        .where(
          (endpoint) =>
              bootstrapState(endpoint) == SettingsServerState.connected,
        )
        .toList(growable: false);
    final availableRelay = relayServers
        .where(
          (endpoint) => relayState(endpoint) == SettingsServerState.connected,
        )
        .toList(growable: false);
    final availableTurn = turnServers
        .where(
          (server) => turnState(server.url) == SettingsServerState.connected,
        )
        .toList(growable: false);
    final availablePush = pushServers
        .where(
          (endpoint) => pushState(endpoint) == SettingsServerState.connected,
        )
        .toList(growable: false);

    return jsonEncode(
      ServerConfigPayload(
        bootstrap: availableBootstrap,
        relay: availableRelay,
        turn: availableTurn,
        push: availablePush,
      ).toJson(),
    );
  }

  ServerConfigPayload currentConfiguredServerConfigPayload() {
    return ServerConfigPayload(
      bootstrap: List<String>.from(bootstrapPeers),
      relay: List<String>.from(relayServers),
      turn: List<TurnServerConfig>.from(turnServers),
      push: List<String>.from(health.push.activeEndpoints),
    );
  }

  Future<void> loadAppVersion() async {
    try {
      const buildName = String.fromEnvironment('FLUTTER_BUILD_NAME');
      const buildNumber = String.fromEnvironment('FLUTTER_BUILD_NUMBER');
      if (buildName.trim().isNotEmpty) {
        _appVersionLabel = buildNumber.trim().isEmpty
            ? buildName.trim()
            : '${buildName.trim()}+${buildNumber.trim()}';
        return;
      }
      final pubspec = await rootBundle.loadString('pubspec.yaml');
      final match = RegExp(
        r'^version:\s*([^\s]+)',
        multiLine: true,
      ).firstMatch(pubspec);
      if (match != null) {
        _appVersionLabel = match.group(1) ?? _appVersionLabel;
      }
    } catch (_) {
      _appVersionLabel = '—';
    }
  }

  int _countByState<T>(
    Iterable<T> items,
    SettingsServerState Function(T item) stateOf,
    SettingsServerState state,
  ) {
    var count = 0;
    for (final item in items) {
      if (stateOf(item) == state) {
        count += 1;
      }
    }
    return count;
  }

  List<String> _sortStrings(
    List<String> source,
    SettingsServerState Function(String endpoint) stateOf,
  ) {
    final items = List<String>.from(source);
    items.sort((a, b) {
      final rank = SettingsServerStatusPresenter.rank(
        stateOf(a),
      ).compareTo(SettingsServerStatusPresenter.rank(stateOf(b)));
      if (rank != 0) {
        return rank;
      }
      return a.compareTo(b);
    });
    return items;
  }

  String _statusLabel(ServerAvailability availability, {AppStrings? strings}) {
    return SettingsServerStatusPresenter.label(
      availability,
      connected: false,
      strings: strings,
    );
  }
}
