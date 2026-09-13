// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'app_file_logger.dart';
import 'bootstrap_servers_service.dart';
import 'relay_servers_service.dart';
import 'push_servers_service.dart';
import 'server_config_payload.dart';
import 'turn_servers_service.dart';

typedef HttpClientFactory = HttpClient Function();

class InitialServerConfigBootstrapper {
  static const _defaultConfigUrl = String.fromEnvironment(
    'PEERLINK_INITIAL_SERVER_CONFIG_URL',
    defaultValue: 'https://simplegear.org/config/initial-server-config.json',
  );
  static const _defaultTimeout = Duration(seconds: 6);
  static const _maxConfigBytes = 64 * 1024;

  final BootstrapServersService bootstrap;
  final RelayServersService relay;
  final TurnServersService turn;
  final PushServersService push;
  final Uri configUri;
  final Duration timeout;
  final HttpClientFactory _httpClientFactory;

  InitialServerConfigBootstrapper({
    required this.bootstrap,
    required this.relay,
    required this.turn,
    required this.push,
    Uri? configUri,
    this.timeout = _defaultTimeout,
    HttpClientFactory? httpClientFactory,
  }) : configUri = configUri ?? Uri.parse(_defaultConfigUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  Future<void> importIfEmpty({bool throwOnFailure = false}) async {
    if (!_hasNoConfiguredServers) {
      _log('skip reason=configured_servers_present');
      return;
    }

    try {
      final payload = await _fetchConfig();
      if (_payloadIsEmpty(payload)) {
        _log('skip reason=remote_payload_empty');
        return;
      }
      await bootstrap.merge(payload.bootstrap);
      await relay.merge(payload.relay);
      await turn.merge(payload.turn);
      await push.merge(payload.push);
      _log(
        'imported bootstrap=${payload.bootstrap.length} '
        'relay=${payload.relay.length} turn=${payload.turn.length} '
        'push=${payload.push.length}',
      );
    } catch (error, stackTrace) {
      _log('failed url=$configUri error=$error', stackTrace: stackTrace);
      if (throwOnFailure) rethrow;
    }
  }

  bool get _hasNoConfiguredServers =>
      bootstrap.endpoints.isEmpty &&
      relay.endpoints.isEmpty &&
      turn.servers.isEmpty &&
      push.endpoints.isEmpty;

  bool _payloadIsEmpty(ServerConfigPayload payload) =>
      payload.bootstrap.isEmpty &&
      payload.relay.isEmpty &&
      payload.turn.isEmpty &&
      payload.push.isEmpty;

  Future<ServerConfigPayload> _fetchConfig() async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(configUri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'initial server config status ${response.statusCode}',
          uri: configUri,
        );
      }
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) {
            final nextLength = buffer.length + chunk.length;
            if (nextLength > _maxConfigBytes) {
              throw const FormatException('Initial server config is too large');
            }
            buffer.addAll(chunk);
            return buffer;
          })
          .timeout(timeout);
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) {
        throw const FormatException('Initial server config must be an object');
      }
      return ServerConfigPayload.fromJson(Map<String, dynamic>.from(decoded));
    } finally {
      client.close(force: true);
    }
  }

  void _log(String message, {StackTrace? stackTrace}) {
    AppFileLogger.log(
      '[initial_server_config] $message',
      stackTrace: stackTrace,
    );
  }
}
