import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'relay_client.dart';
import 'relay_models.dart';
import '../runtime/server_availability.dart';

class RelayServerStatus {
  final String url;
  final bool healthy;
  final String? lastError;
  final DateTime? lastSuccessAt;

  const RelayServerStatus({
    required this.url,
    required this.healthy,
    this.lastError,
    this.lastSuccessAt,
  });
}

class HttpRelayClient implements RelayClient {
  static const Duration _controlTimeout = Duration(seconds: 6);
  static const Duration _blobTimeout = Duration(seconds: 20);
  static const Duration _healthProbeTimeout = Duration(seconds: 2);
  static const Duration _sharedHealthFreshness = Duration(seconds: 12);
  static const int _blobChunkSizeBytes = 256 * 1024;
  static const int _chunkedUploadThresholdBytes = 512 * 1024;
  static const int _maxActiveRelayPool = 3;
  static const int _writeQuorum = 2;
  static const int _ackQuorum = 2;
  static const int _fetchPoolSize = 3;
  final List<Uri> _servers = [];
  final bool _httpsOnly;
  final http.Client? _httpClient;
  final Map<String, RelayServerStatus> _statuses = <String, RelayServerStatus>{};
  final Map<String, String?> _fetchCursorByServer = <String, String?>{};
  ServerAvailability? Function(String endpoint)? _availabilityLookup;
  Future<void> Function(List<String> endpoints)? _refreshAvailabilityForEndpoints;
  int _cursorIndex = 0;

  HttpRelayClient({
    required List<String> servers,
    bool httpsOnly = false,
    http.Client? httpClient,
    ServerAvailability? Function(String endpoint)? availabilityLookup,
    Future<void> Function(List<String> endpoints)? refreshAvailabilityForEndpoints,
  })  : _httpsOnly = httpsOnly,
        _httpClient = httpClient,
        _availabilityLookup = availabilityLookup,
        _refreshAvailabilityForEndpoints = refreshAvailabilityForEndpoints {
    configureServers(servers);
  }

  void setAvailabilityLookup(
    ServerAvailability? Function(String endpoint)? availabilityLookup,
  ) {
    _availabilityLookup = availabilityLookup;
  }

  void setAvailabilityRefresh(
    Future<void> Function(List<String> endpoints)? refreshAvailabilityForEndpoints,
  ) {
    _refreshAvailabilityForEndpoints = refreshAvailabilityForEndpoints;
  }

  void _log(String message) {
    AppFileLogger.log('[relay_http] $message');
  }

  List<RelayServerStatus> get serverStatuses => _servers.map((server) {
    final key = server.toString();
    final shared = _sharedAvailabilityFor(server);
    if (shared?.isAvailable != null) {
      final previous = _statuses[key];
      return RelayServerStatus(
        url: key,
        healthy: shared!.isAvailable!,
        lastError: shared.error,
        lastSuccessAt: shared.isAvailable == true
            ? (shared.checkedAt ?? previous?.lastSuccessAt)
            : previous?.lastSuccessAt,
      );
    }
    return _statuses[key] ??
        RelayServerStatus(
          url: key,
          healthy: false,
          lastError: 'ожидание проверки',
        );
  }).toList(growable: false);

  @override
  Future<void> store(RelayEnvelope envelope) async {
    await _postToQuorum(
      '/relay/store',
      envelope.toJson(),
      operationName: 'store',
      quorum: _writeQuorum,
    );
  }

  @override
  Future<void> storeGroup(RelayGroupEnvelope envelope) async {
    await _postToQuorum(
      '/relay/group/store',
      envelope.toJson(),
      operationName: 'group-store',
      quorum: _writeQuorum,
    );
  }

  @override
  Future<void> updateGroupMembers(
    RelayGroupMembersUpdateEnvelope envelope,
  ) async {
    await _postToQuorum(
      '/relay/group/members/update',
      envelope.toJson(),
      operationName: 'group-members-update',
      quorum: _writeQuorum,
    );
  }

  @override
  Future<void> storeBlob(
    RelayBlobUploadEnvelope envelope, {
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  }) async {
    if (envelope.payload.length >= _chunkedUploadThresholdBytes) {
      onProgress?.call(
        sentBytes: 0,
        totalBytes: envelope.payload.length,
        status: 'Загрузка в relay',
      );
      final chunkedOk = await _storeBlobChunked(
        envelope,
        onProgress: onProgress,
      );
      if (chunkedOk) {
        return;
      }
      _log('blob-upload chunked unavailable, fallback to single upload');
    }
    onProgress?.call(
      sentBytes: 0,
      totalBytes: envelope.payload.length,
      status: 'Загрузка в relay',
    );
    await _postUntilSuccess(
      '/relay/blob/upload',
      envelope.toJson(),
      operationName: 'blob-upload',
    );
    onProgress?.call(
      sentBytes: envelope.payload.length,
      totalBytes: envelope.payload.length,
      status: 'Финализация',
    );
  }

  Future<bool> _storeBlobChunked(
    RelayBlobUploadEnvelope envelope, {
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  }) async {
    if (_servers.isEmpty) {
      throw StateError('No message relay servers configured');
    }
    final totalBytes = envelope.payload.length;
    if (totalBytes == 0) {
      return false;
    }
    final totalChunks = (totalBytes / _blobChunkSizeBytes).ceil();

    final targets = await _liveServers(limit: _maxActiveRelayPool);
    for (final server in targets) {
      var endpointMissing = false;
      try {
        for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
          final start = chunkIndex * _blobChunkSizeBytes;
          final end = start + _blobChunkSizeBytes > totalBytes
              ? totalBytes
              : start + _blobChunkSizeBytes;
          final chunkBytes = envelope.payload.sublist(start, end);
          final chunkRequest = <String, dynamic>{
            'id': envelope.id,
            'from': envelope.from,
            'groupId': envelope.groupId,
            'fileName': envelope.fileName,
            'mimeType': envelope.mimeType,
            'ts': envelope.timestampMs,
            'ttl': envelope.ttlSeconds,
            'chunkIndex': chunkIndex,
            'totalChunks': totalChunks,
            'payload': base64Encode(chunkBytes),
          };
          final chunkResponse = await _sendPost(
            server.resolve('/relay/blob/upload/chunk'),
            body: jsonEncode(chunkRequest),
            timeout: _blobTimeout,
          );
          if (chunkResponse == null) {
            _markUnhealthy(server, 'blob-upload chunk timeout');
            throw HttpException('blob chunk timeout');
          }
          if (chunkResponse.statusCode == 404) {
            endpointMissing = true;
            break;
          }
          if (chunkResponse.statusCode < 200 || chunkResponse.statusCode >= 300) {
            _markUnhealthy(
              server,
              'blob-upload chunk ${chunkResponse.statusCode}',
            );
            throw HttpException(
              'blob chunk failed ${chunkResponse.statusCode}: ${chunkResponse.body}',
            );
          }
          onProgress?.call(
            sentBytes: end,
            totalBytes: totalBytes,
            status: chunkIndex == totalChunks - 1
                ? 'Финализация'
                : 'Загрузка в relay',
          );
        }
        if (endpointMissing) {
          continue;
        }

        final completeRequest = <String, dynamic>{
          'id': envelope.id,
          'from': envelope.from,
          'groupId': envelope.groupId,
          'fileName': envelope.fileName,
          'mimeType': envelope.mimeType,
          'ts': envelope.timestampMs,
          'ttl': envelope.ttlSeconds,
          'totalChunks': totalChunks,
          'sig': base64Encode(envelope.signature),
          'signingPub': base64Encode(envelope.senderSigningPublicKey),
        };
        final completeResponse = await _sendPost(
          server.resolve('/relay/blob/upload/complete'),
          body: jsonEncode(completeRequest),
          timeout: _blobTimeout,
        );
        if (completeResponse == null) {
          _markUnhealthy(server, 'blob-upload complete timeout');
          throw HttpException('blob complete timeout');
        }
        if (completeResponse.statusCode == 404) {
          continue;
        }
        if (completeResponse.statusCode < 200 || completeResponse.statusCode >= 300) {
          _markUnhealthy(
            server,
            'blob-upload complete ${completeResponse.statusCode}',
          );
          throw HttpException(
            'blob complete failed ${completeResponse.statusCode}: ${completeResponse.body}',
          );
        }
        _markHealthy(server);
        return true;
      } on HttpException catch (e) {
        _markUnhealthy(server, 'blob-upload chunked http');
        _log('blob-upload chunked failed server=${server.toString()} error=$e');
        continue;
      } catch (e) {
        _markUnhealthy(server, 'blob-upload chunked error');
        _log('blob-upload chunked failed server=${server.toString()} error=$e');
        continue;
      }
    }
    return false;
  }

  @override
  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  }) async {
    if (_servers.isEmpty) {
      throw StateError('No message relay servers configured');
    }
    final errors = <String>[];
    final targets = await _liveServers(limit: _maxActiveRelayPool);
    final futures = targets
        .map(
          (server) => _fetchBlobFromServer(
            server,
            blobId,
            onProgress: onProgress,
          ),
        )
        .toList(growable: false);

    for (final future in futures) {
      final outcome = await future;
      if (outcome.download != null) {
        return outcome.download!;
      }
      if (outcome.error != null) {
        errors.add(outcome.error!);
      }
    }

    throw Exception('Relay blob-fetch failed: ${errors.join(' | ')}');
  }

  Future<_BlobFetchOutcome> _fetchBlobFromServer(
    Uri server,
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  }) async {
    final uri = server.resolve('/relay/blob/$blobId');
    try {
      final response = await _sendGet(
        uri,
        onProgress: onProgress,
        timeout: _blobTimeout,
      );
      if (response == null) {
        _markUnhealthy(server, 'blob-fetch timeout');
        return const _BlobFetchOutcome(error: 'blob-fetch timeout');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _markUnhealthy(server, 'blob-fetch ${response.statusCode}');
        return _BlobFetchOutcome(
          error: 'blob-fetch ${response.statusCode}: ${response.body}',
        );
      }
      _markHealthy(server);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _BlobFetchOutcome(
          error: 'blob-fetch invalid response type: ${decoded.runtimeType}',
        );
      }
      final id = decoded['id'];
      final fileName = decoded['fileName'];
      final payload = decoded['payload'];
      final mimeType = decoded['mimeType'];
      final sizeBytes = decoded['sizeBytes'];
      if (id is! String || fileName is! String || payload is! String) {
        return const _BlobFetchOutcome(error: 'blob-fetch invalid fields');
      }
      final payloadBytes = base64Decode(payload);
      onProgress?.call(
        receivedBytes: payloadBytes.length,
        totalBytes: payloadBytes.length,
        status: 'Загрузка завершена',
      );
      return _BlobFetchOutcome(
        download: RelayBlobDownload(
          id: id,
          fileName: fileName,
          mimeType: mimeType is String ? mimeType : null,
          sizeBytes: sizeBytes is int ? sizeBytes : payloadBytes.length,
          payload: Uint8List.fromList(payloadBytes),
        ),
      );
    } on HttpException catch (e) {
      _markUnhealthy(server, 'blob-fetch http');
      return _BlobFetchOutcome(error: 'blob-fetch http: $e');
    } catch (e) {
      _markUnhealthy(server, 'blob-fetch error');
      return _BlobFetchOutcome(error: e.toString());
    }
  }

  Future<void> _postToQuorum(
    String path,
    Map<String, dynamic> payload, {
    required String operationName,
    required int quorum,
  }) async {
    if (_servers.isEmpty) {
      throw StateError('No message relay servers configured');
    }

    final body = jsonEncode(payload);
    final errors = <String>[];
    var successCount = 0;
    final targets = await _writeTargets(quorum);

    final outcomes = await Future.wait(
      targets.map(
        (server) => _postToServer(
          server,
          path,
          body,
          operationName: operationName,
          timeout: _controlTimeout,
        ),
      ),
    );

    for (final outcome in outcomes) {
      if (outcome.success) {
        successCount += 1;
      } else if (outcome.error != null) {
        errors.add(outcome.error!);
      }
    }

    if (successCount >= _effectiveQuorum(targets.length, quorum)) {
      if (errors.isNotEmpty) {
        _log(
          'relay $operationName quorum-met success=$successCount/${targets.length} '
          'errors=${errors.join(' | ')}',
        );
      }
      return;
    }

    throw Exception('Relay $operationName failed: ${errors.join(' | ')}');
  }

  Future<void> _postUntilSuccess(
    String path,
    Map<String, dynamic> payload, {
    required String operationName,
  }) async {
    if (_servers.isEmpty) {
      throw StateError('No message relay servers configured');
    }

    final body = jsonEncode(payload);
    final errors = <String>[];

    final outcomes = await Future.wait(
      (await _liveServers(limit: _maxActiveRelayPool)).map(
        (server) => _postToServer(
          server,
          path,
          body,
          operationName: operationName,
          timeout: _blobTimeout,
        ),
      ),
    );

    for (final outcome in outcomes) {
      if (outcome.success) {
        return;
      }
      if (outcome.error != null) {
        errors.add(outcome.error!);
      }
    }

    throw Exception('Relay $operationName failed: ${errors.join(' | ')}');
  }

  @override
  Future<RelayFetchResult> fetch(
    String recipientId, {
    String? cursor,
    int limit = 100,
  }) async {
    if (_servers.isEmpty) {
      throw StateError('No message relay servers configured');
    }

    final envelopesById = <String, RelayEnvelope>{};
    final outcomes = await Future.wait(
      (await _fetchTargets()).map(
        (server) => _fetchFromServer(
          server,
          recipientId,
          cursor: cursor,
          limit: limit,
        ),
      ),
    );

    var successCount = 0;
    String? nextCursor = cursor;

    for (final outcome in outcomes) {
      if (!outcome.success) {
        continue;
      }
      successCount += 1;
      if (outcome.cursor != null) {
        nextCursor = outcome.cursor;
      }
      for (final envelope in outcome.messages) {
        envelopesById[envelope.id] = envelope;
      }
    }

    if (successCount > 0) {
      final messages = envelopesById.values.toList(growable: false)
        ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
      return RelayFetchResult(messages: messages, cursor: nextCursor);
    }

    return RelayFetchResult(messages: const [], cursor: cursor);
  }

  Future<_FetchOutcome> _fetchFromServer(
    Uri server,
    String recipientId, {
    String? cursor,
    required int limit,
  }) async {
    final key = server.toString();
    final queryParameters = <String, String>{
      'to': recipientId,
      'limit': limit.toString(),
    };
    final serverCursor = _fetchCursorByServer[key] ?? cursor;
    if (serverCursor != null) {
      queryParameters['cursor'] = serverCursor;
    }
    final uri = server.replace(
      path: '/relay/fetch',
      queryParameters: queryParameters,
    );

    try {
      final response = await _sendGet(uri, timeout: _controlTimeout);
      if (response == null) {
        _markUnhealthy(server, 'fetch timeout');
        return const _FetchOutcome();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        _markUnhealthy(server, 'fetch ${response.statusCode}');
        return const _FetchOutcome();
      }
      _markHealthy(server);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const _FetchOutcome();
      }

      final messagesRaw = decoded['messages'];
      final cursorRaw = decoded['cursor'];
      if (messagesRaw is! List) {
        return const _FetchOutcome();
      }

      final messages = <RelayEnvelope>[];
      for (final item in messagesRaw) {
        if (item is Map<String, dynamic>) {
          messages.add(RelayEnvelope.fromJson(item));
        }
      }
      final nextCursor = cursorRaw is String ? cursorRaw : serverCursor;
      _fetchCursorByServer[key] = nextCursor;
      return _FetchOutcome(
        success: true,
        messages: messages,
        cursor: nextCursor,
      );
    } on HttpException catch (_) {
      _markUnhealthy(server, 'fetch http');
      return const _FetchOutcome();
    } catch (_) {
      _markUnhealthy(server, 'fetch error');
      return const _FetchOutcome();
    }
  }

  @override
  Future<void> ack(RelayAck ack) async {
    await _postToQuorum(
      '/relay/ack',
      ack.toJson(),
      operationName: 'ack',
      quorum: _ackQuorum,
    );
  }

  @override
  void configureServers(List<String> servers) {
    _servers
      ..clear()
      ..addAll(
        servers
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .map((s) => _normalizeBase(s, httpsOnly: _httpsOnly)),
      );
    final activeKeys = _servers.map((server) => server.toString()).toSet();
    _statuses.removeWhere((key, _) => !activeKeys.contains(key));
    _fetchCursorByServer.removeWhere((key, _) => !activeKeys.contains(key));
    for (final server in _servers) {
      final key = server.toString();
      _statuses.putIfAbsent(
        key,
        () => RelayServerStatus(
          url: key,
          healthy: false,
          lastError: 'ожидание проверки',
        ),
      );
      _fetchCursorByServer.putIfAbsent(key, () => null);
    }
  }

  List<Uri> _rotatedServers() {
    if (_servers.length <= 1) {
      return List<Uri>.from(_servers);
    }

    final offset = _cursorIndex % _servers.length;
    _cursorIndex += 1;

    return List<Uri>.from(_servers.skip(offset))..addAll(_servers.take(offset));
  }

  List<Uri> _candidateServers({required int limit}) {
    if (_servers.isEmpty) {
      return const <Uri>[];
    }
    final rotated = _rotatedServers();
    rotated.sort((a, b) => _compareServers(a, b));
    final healthy = rotated
        .where((server) => _effectiveHealthy(server) == true)
        .take(limit)
        .toList(growable: false);
    if (healthy.isNotEmpty) {
      return healthy;
    }
    return rotated.take(limit).toList(growable: false);
  }

  Future<List<Uri>> _writeTargets(int quorum) async {
    final active = await _liveServers(limit: _maxActiveRelayPool);
    if (active.isEmpty) {
      return const <Uri>[];
    }
    final targetCount = _effectiveQuorum(active.length, quorum);
    return active.take(targetCount).toList(growable: false);
  }

  Future<List<Uri>> _fetchTargets() async {
    return _liveServers(limit: _fetchPoolSize);
  }

  Future<List<Uri>> _liveServers({required int limit}) async {
    final candidates = _candidateServers(limit: limit);
    if (candidates.isEmpty) {
      return const <Uri>[];
    }
    await _refreshSharedHealthIfStale(candidates);

    final selected = <Uri>[];
    final deferred = <Uri>[];

    for (final server in candidates) {
      if (_effectiveHealthy(server) == true) {
        selected.add(server);
        if (selected.length >= limit) {
          return selected;
        }
      } else {
        deferred.add(server);
      }
    }

    for (final server in deferred) {
      final live = await _probeServerHealth(server);
      if (live) {
        selected.add(server);
        if (selected.length >= limit) {
          return selected;
        }
      }
    }

    return selected;
  }

  Future<void> _refreshSharedHealthIfStale(List<Uri> candidates) async {
    final refresh = _refreshAvailabilityForEndpoints;
    if (refresh == null || candidates.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final selected = candidates.take(_maxActiveRelayPool).toList(growable: false);
    final stale = selected.any((server) {
      final availability = _sharedAvailabilityFor(server);
      final checkedAt = availability?.checkedAt;
      if (checkedAt == null) {
        return true;
      }
      return now.difference(checkedAt) > _sharedHealthFreshness;
    });
    if (!stale) {
      return;
    }
    try {
      await refresh(
        selected.map((server) => server.toString()).toList(growable: false),
      );
    } catch (error) {
      _log('relay shortlist refresh failed error=$error');
    }
  }

  Future<bool> _probeServerHealth(Uri server) async {
    try {
      final response = await _sendGet(
        server.resolve('/health'),
        timeout: _healthProbeTimeout,
      );
      if (response == null) {
        _markUnhealthy(server, 'health timeout');
        return false;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _markHealthy(server);
        return true;
      }
      _markUnhealthy(server, 'health ${response.statusCode}');
      return false;
    } catch (_) {
      _markUnhealthy(server, 'health error');
      return false;
    }
  }

  int _effectiveQuorum(int available, int requested) {
    if (available <= 0) {
      return 0;
    }
    if (requested <= 1) {
      return 1;
    }
    return requested > available ? available : requested;
  }

  int _compareServers(Uri a, Uri b) {
    final aAvailability = _sharedAvailabilityFor(a);
    final bAvailability = _sharedAvailabilityFor(b);
    final aHealthy = _sortRankForAvailability(aAvailability, _statuses[a.toString()]);
    final bHealthy = _sortRankForAvailability(bAvailability, _statuses[b.toString()]);
    if (aHealthy != bHealthy) {
      return aHealthy.compareTo(bHealthy);
    }
    final aSuccess = _lastSuccessAt(a, aAvailability);
    final bSuccess = _lastSuccessAt(b, bAvailability);
    if (aSuccess != null && bSuccess != null) {
      return bSuccess.compareTo(aSuccess);
    }
    if (aSuccess != null) {
      return -1;
    }
    if (bSuccess != null) {
      return 1;
    }
    return _servers.indexOf(a).compareTo(_servers.indexOf(b));
  }

  ServerAvailability? _sharedAvailabilityFor(Uri server) {
    return _availabilityLookup?.call(server.toString());
  }

  bool? _effectiveHealthy(Uri server) {
    final shared = _sharedAvailabilityFor(server);
    if (shared?.isAvailable != null) {
      return shared!.isAvailable;
    }
    return _statuses[server.toString()]?.healthy;
  }

  int _sortRankForAvailability(
    ServerAvailability? shared,
    RelayServerStatus? local,
  ) {
    final available = shared?.isAvailable;
    if (available == true) {
      return 0;
    }
    if (available == false) {
      return 2;
    }
    return local?.healthy == true ? 0 : 1;
  }

  DateTime? _lastSuccessAt(Uri server, ServerAvailability? shared) {
    final local = _statuses[server.toString()];
    if (shared?.isAvailable == true) {
      return shared?.checkedAt ?? local?.lastSuccessAt;
    }
    return local?.lastSuccessAt;
  }

  Future<_PostOutcome> _postToServer(
    Uri server,
    String path,
    String body, {
    required String operationName,
    required Duration timeout,
  }) async {
    final uri = server.resolve(path);
    try {
      final response = await _sendPost(uri, body: body, timeout: timeout);
      if (response == null) {
        _markUnhealthy(server, '$operationName timeout');
        return _PostOutcome(error: '$operationName timeout');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _markHealthy(server);
        return const _PostOutcome(success: true);
      }

      final normalizedBody = response.body.toLowerCase();
      if (response.statusCode == 401 &&
          normalizedBody.contains('invalid signature')) {
        _log(
          '$operationName signature rejected server=${server.toString()} '
          'status=${response.statusCode} body=${response.body}',
        );
      }
      _markUnhealthy(server, '$operationName ${response.statusCode}');
      return _PostOutcome(error: '$operationName ${response.statusCode}: ${response.body}');
    } on HttpException catch (e) {
      _markUnhealthy(server, '$operationName http');
      return _PostOutcome(error: '$operationName http: $e');
    } catch (e) {
      _markUnhealthy(server, '$operationName error');
      return _PostOutcome(error: e.toString());
    }
  }

  Future<http.Response?> _sendPost(
    Uri uri, {
    required String body,
    required Duration timeout,
  }) async {
    final client = _httpClient ?? _createHttpClientForUri(uri);
    final ownsClient = _httpClient == null;
    try {
      final request = http.Request('POST', uri)
        ..persistentConnection = false
        ..headers.addAll({
          'content-type': 'application/json',
          'accept': 'application/json',
          'connection': 'close',
        })
        ..body = body;
      final streamed = await _awaitWithTimeout(client.send(request), timeout);
      if (streamed == null) {
        return null;
      }
      final response = await _awaitWithTimeout(
        http.Response.fromStream(streamed),
        timeout,
      );
      if (response == null) {
        return null;
      }
      return response;
    } catch (e) {
      throw HttpException('POST request failed: $e');
    } finally {
      if (ownsClient) {
        client.close();
      }
    }
  }

  Future<http.Response?> _sendGet(
    Uri uri, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
    required Duration timeout,
  }) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      final resolvedClient = _httpClient ?? _createHttpClientForUri(uri);
      final ownsClient = _httpClient == null;
      try {
        final request = http.Request('GET', uri)
          ..persistentConnection = false
          ..headers.addAll({
            'accept': 'application/json',
            'connection': 'close',
          });
        final streamed = await _awaitWithTimeout(
          resolvedClient.send(request),
          timeout,
        );
        if (streamed == null) {
          return null;
        }
        final rawContentLength = streamed.contentLength ?? -1;
        final totalBytes = rawContentLength < 0 ? 0 : rawContentLength;
        final chunks = <List<int>>[];
        var receivedBytes = 0;
        await for (final chunk in streamed.stream.timeout(timeout)) {
          chunks.add(chunk);
          receivedBytes += chunk.length;
          onProgress?.call(
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            status: 'Загрузка',
          );
        }
        final bytes = Uint8List(receivedBytes);
        var offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }
        return http.Response.bytes(
          bytes,
          streamed.statusCode,
          headers: streamed.headers,
          request: streamed.request,
          reasonPhrase: streamed.reasonPhrase,
        );
      } catch (e) {
        lastError = e;
        final transient =
            e is http.ClientException || e is SocketException || e is HttpException;
        if (!transient || attempt >= 2) {
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      } finally {
        if (ownsClient) {
          resolvedClient.close();
        }
      }
    }
    throw HttpException('GET request failed: $lastError');
  }

  Future<T?> _awaitWithTimeout<T>(Future<T> future, Duration timeout) async {
    const timeoutMarker = Object();
    final guarded = future.then<Object?>(
      (value) => value,
      onError: (Object error, StackTrace stackTrace) =>
          _AsyncErrorBox(error, stackTrace),
    );
    final result = await Future.any<Object?>([
      guarded,
      Future<Object?>.delayed(timeout, () => timeoutMarker),
    ]);
    if (identical(result, timeoutMarker)) {
      return null;
    }
    if (result is _AsyncErrorBox) {
      Error.throwWithStackTrace(result.error, result.stackTrace);
    }
    return result as T;
  }

  void _markHealthy(Uri server) {
    final key = server.toString();
    _statuses[key] = RelayServerStatus(
      url: key,
      healthy: true,
      lastSuccessAt: DateTime.now(),
    );
  }

  void _markUnhealthy(Uri server, String error) {
    final key = server.toString();
    final previous = _statuses[key];
    _statuses[key] = RelayServerStatus(
      url: key,
      healthy: false,
      lastError: error,
      lastSuccessAt: previous?.lastSuccessAt,
    );
  }

  static Uri _normalizeBase(String raw, {required bool httpsOnly}) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Empty relay server');
    }

    final withScheme =
        trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed
        : 'http://$trimmed';
    final uri = Uri.parse(withScheme);

    if (httpsOnly && uri.scheme != 'https') {
      throw ArgumentError(
        'Relay servers must be HTTPS when httpsOnly=true: $raw',
      );
    }

    return uri;
  }

  http.Client _createHttpClientForUri(Uri uri) {
    if (uri.scheme != 'https' || !_isIpAddressHost(uri.host)) {
      return http.Client();
    }
    final io = HttpClient()
      ..badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) {
        return host == uri.host;
      };
    return IOClient(io);
  }

  bool _isIpAddressHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    return InternetAddress.tryParse(host) != null;
  }
}

class _AsyncErrorBox {
  final Object error;
  final StackTrace stackTrace;

  const _AsyncErrorBox(this.error, this.stackTrace);
}

class _PostOutcome {
  final bool success;
  final String? error;

  const _PostOutcome({this.success = false, this.error});
}

class _FetchOutcome {
  final bool success;
  final List<RelayEnvelope> messages;
  final String? cursor;

  const _FetchOutcome({
    this.success = false,
    this.messages = const <RelayEnvelope>[],
    this.cursor,
  });
}

class _BlobFetchOutcome {
  final RelayBlobDownload? download;
  final String? error;

  const _BlobFetchOutcome({this.download, this.error});
}
