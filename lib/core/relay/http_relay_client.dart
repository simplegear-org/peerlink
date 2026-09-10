// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:http/http.dart' as http;
import 'package:peerlink/core/runtime/app_file_logger.dart';

import '../runtime/server_availability.dart';
import 'relay_client.dart';
import 'relay_http_blob_api.dart';
import 'relay_http_message_api.dart';
import 'relay_http_server_pool.dart';
import 'relay_http_transport.dart';
import 'relay_http_types.dart';
import 'relay_models.dart';
import 'relay_replication_policy.dart';
import 'relay_server_status.dart';

export 'relay_server_status.dart';

class HttpRelayClient implements RelayClient {
  static const Duration _controlTimeout = Duration(seconds: 6);
  static const Duration _blobTimeout = Duration(seconds: 20);
  static const Duration _blobChunkUploadTimeout = Duration(seconds: 5);
  static const Duration _sharedHealthFreshness = Duration(seconds: 12);
  static const int _blobChunkSizeBytes = 1024 * 1024;
  static const int _blobChunkUploadConcurrency = 5;
  static const int _chunkedUploadThresholdBytes = 512 * 1024;
  static const int _maxActiveRelayPool = RelayReplicationPolicy.maxCandidates;
  static const int _writeQuorum =
      RelayReplicationPolicy.desiredSuccessfulReplicas;
  static const int _ackQuorum = 2;
  static const int _fetchPoolSize = 3;

  late final RelayHttpServerPool _serverPool;
  late final RelayHttpTransport _transport;
  late final RelayHttpMessageApi _messageApi;
  late final RelayHttpBlobApi _blobApi;

  HttpRelayClient({
    required List<String> servers,
    bool httpsOnly = false,
    http.Client? httpClient,
    ServerAvailability? Function(String endpoint)? availabilityLookup,
    Future<void> Function(List<String> endpoints)?
    refreshAvailabilityForEndpoints,
  }) {
    _serverPool = RelayHttpServerPool(
      httpsOnly: httpsOnly,
      maxActiveRelayPool: _maxActiveRelayPool,
      fetchPoolSize: _fetchPoolSize,
      sharedHealthFreshness: _sharedHealthFreshness,
      log: _log,
      probeServerHealth: _probeServerHealth,
      availabilityLookup: availabilityLookup,
      refreshAvailability: refreshAvailabilityForEndpoints,
    );
    _transport = RelayHttpTransport(httpClient: httpClient, log: _log);
    _messageApi = RelayHttpMessageApi(
      serverPool: _serverPool,
      transport: _transport,
      log: _log,
      controlTimeout: _controlTimeout,
      blobTimeout: _blobTimeout,
      writeQuorum: _writeQuorum,
      ackQuorum: _ackQuorum,
    );
    _blobApi = RelayHttpBlobApi(
      serverPool: _serverPool,
      transport: _transport,
      messageApi: _messageApi,
      log: _log,
      blobTimeout: _blobTimeout,
      blobChunkUploadTimeout: _blobChunkUploadTimeout,
      blobChunkSizeBytes: _blobChunkSizeBytes,
      blobChunkUploadConcurrency: _blobChunkUploadConcurrency,
      chunkedUploadThresholdBytes: _chunkedUploadThresholdBytes,
    );
    configureServers(servers);
  }

  void setAvailabilityLookup(
    ServerAvailability? Function(String endpoint)? availabilityLookup,
  ) {
    _serverPool.setAvailabilityLookup(availabilityLookup);
  }

  void setAvailabilityRefresh(
    Future<void> Function(List<String> endpoints)?
    refreshAvailabilityForEndpoints,
  ) {
    _serverPool.setAvailabilityRefresh(refreshAvailabilityForEndpoints);
  }

  void _log(String message) {
    AppFileLogger.log('[relay_http] $message');
  }

  List<RelayServerStatus> get serverStatuses => _serverPool.serverStatuses;

  @override
  Future<RelayWriteReceipt> store(
    RelayEnvelope envelope, {
    List<String> preferredServers = const <String>[],
  }) => _messageApi.store(envelope, preferredServers: preferredServers);

  @override
  Future<RelayWriteReceipt> storeGroup(RelayGroupEnvelope envelope) {
    return _messageApi.storeGroup(envelope);
  }

  @override
  Future<void> updateGroupMembers(RelayGroupMembersUpdateEnvelope envelope) {
    return _messageApi.updateGroupMembers(envelope);
  }

  @override
  Future<void> registerPushToken({
    required String peerId,
    required String token,
  }) {
    return _messageApi.registerPushToken(peerId: peerId, token: token);
  }

  @override
  Future<void> unregisterPushToken({
    required String peerId,
    required String token,
  }) {
    return _messageApi.unregisterPushToken(peerId: peerId, token: token);
  }

  @override
  Future<void> storeBlob(
    RelayBlobUploadEnvelope envelope, {
    RelayUploadProgressCallback? onProgress,
  }) {
    return _blobApi.storeBlob(envelope, onProgress: onProgress);
  }

  @override
  Future<RelayBlobStoreReceipt> storeBlobWithReceipt(
    RelayBlobUploadEnvelope envelope, {
    RelayUploadProgressCallback? onProgress,
  }) => _blobApi.storeBlobWithReceipt(envelope, onProgress: onProgress);

  @override
  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    List<String>? relayServers,
    RelayDownloadProgressCallback? onProgress,
  }) {
    return _blobApi.fetchBlob(
      blobId,
      relayServers: relayServers,
      onProgress: onProgress,
    );
  }

  @override
  Future<RelayFetchResult> fetch(
    String recipientId, {
    String? cursor,
    int limit = 100,
  }) {
    return _messageApi.fetch(recipientId, cursor: cursor, limit: limit);
  }

  @override
  Future<RelayFetchResult> fetchFromServers(
    String recipientId, {
    required List<String> servers,
    String? cursor,
    int limit = 100,
  }) {
    return _messageApi.fetchFromServers(
      recipientId,
      servers: servers,
      cursor: cursor,
      limit: limit,
    );
  }

  @override
  Future<void> ack(RelayAck ack) => _messageApi.ack(ack);

  @override
  void configureServers(List<String> servers) {
    _serverPool.configureServers(servers);
  }

  Future<bool> _probeServerHealth(Uri server) async {
    try {
      final response = await _transport.sendGet(
        server.resolve('/health'),
        timeout: const Duration(seconds: 2),
      );
      if (response == null) {
        _serverPool.markUnhealthy(server, 'health timeout');
        return false;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _serverPool.markHealthy(server);
        return true;
      }
      _serverPool.markUnhealthy(server, 'health ${response.statusCode}');
      return false;
    } catch (_) {
      _serverPool.markUnhealthy(server, 'health error');
      return false;
    }
  }
}
