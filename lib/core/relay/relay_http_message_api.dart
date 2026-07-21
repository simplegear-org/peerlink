import 'dart:convert';
import 'dart:io';

import 'relay_http_server_pool.dart';
import 'relay_http_transport.dart';
import 'relay_http_types.dart';
import 'relay_models.dart';

class RelayHttpMessageApi {
  final RelayHttpServerPool serverPool;
  final RelayHttpTransport transport;
  final void Function(String message) log;
  final Duration controlTimeout;
  final Duration blobTimeout;
  final int writeQuorum;
  final int ackQuorum;

  const RelayHttpMessageApi({
    required this.serverPool,
    required this.transport,
    required this.log,
    required this.controlTimeout,
    required this.blobTimeout,
    required this.writeQuorum,
    required this.ackQuorum,
  });

  Future<RelayWriteReceipt> store(RelayEnvelope envelope) {
    return postToQuorum(
      '/relay/store',
      envelope.toJson(),
      operationName: 'store',
      quorum: writeQuorum,
    );
  }

  Future<RelayWriteReceipt> storeGroup(RelayGroupEnvelope envelope) {
    return postToQuorum(
      '/relay/group/store',
      envelope.toJson(),
      operationName: 'group-store',
      quorum: writeQuorum,
    );
  }

  Future<void> updateGroupMembers(RelayGroupMembersUpdateEnvelope envelope) {
    return postToQuorum(
      '/relay/group/members/update',
      envelope.toJson(),
      operationName: 'group-members-update',
      quorum: writeQuorum,
    );
  }

  Future<void> registerPushToken({
    required String peerId,
    required String token,
  }) {
    return postToQuorum(
      '/relay/push/register',
      <String, dynamic>{'peerId': peerId, 'token': token},
      operationName: 'push-register',
      quorum: 1,
    );
  }

  Future<void> unregisterPushToken({
    required String peerId,
    required String token,
  }) {
    return postToQuorum(
      '/relay/push/unregister',
      <String, dynamic>{'peerId': peerId, 'token': token},
      operationName: 'push-unregister',
      quorum: 1,
    );
  }

  Future<void> ack(RelayAck ack) {
    return postToQuorum(
      '/relay/ack',
      ack.toJson(),
      operationName: 'ack',
      quorum: ackQuorum,
    );
  }

  Future<RelayWriteReceipt> postToQuorum(
    String path,
    Map<String, dynamic> payload, {
    required String operationName,
    required int quorum,
  }) async {
    if (serverPool.isEmpty) {
      log('relay $operationName skip reason=no relay servers');
      throw RelayUnavailableException();
    }

    final body = jsonEncode(payload);
    final errors = <String>[];
    var successCount = 0;
    final successfulServers = <String>[];
    final targets = await serverPool.writeTargets();
    if (targets.isEmpty) {
      log('relay $operationName skip reason=relay servers unavailable');
      throw RelayUnavailableException(
        details: RelayUnavailableException.unavailable,
      );
    }

    final outcomes = await Future.wait(
      targets.map(
        (server) => postToServer(
          server,
          path,
          body,
          operationName: operationName,
          timeout: controlTimeout,
        ),
      ),
    );

    for (var index = 0; index < outcomes.length; index++) {
      final outcome = outcomes[index];
      if (outcome.success) {
        successCount += 1;
        successfulServers.add(targets[index].toString());
      } else if (outcome.error != null) {
        errors.add(outcome.error!);
      }
    }

    if (successCount >= effectiveQuorum(targets.length, quorum)) {
      if (errors.isNotEmpty) {
        log(
          'relay $operationName quorum-met success=$successCount/${targets.length} '
          'errors=${errors.join(' | ')}',
        );
      }
      return RelayWriteReceipt(
        serverUrls: successfulServers.toSet().toList(growable: false)..sort(),
      );
    }

    throw Exception('Relay $operationName failed: ${errors.join(' | ')}');
  }

  Future<void> postUntilSuccess(
    String path,
    Map<String, dynamic> payload, {
    required String operationName,
  }) async {
    if (serverPool.isEmpty) {
      log('relay $operationName skip reason=no relay servers');
      throw RelayUnavailableException();
    }

    final body = jsonEncode(payload);
    final errors = <String>[];
    final targets = await serverPool.liveServers(
      limit: serverPool.maxActiveRelayPool,
    );
    if (targets.isEmpty) {
      log('relay $operationName skip reason=relay servers unavailable');
      throw RelayUnavailableException(
        details: RelayUnavailableException.unavailable,
      );
    }

    final outcomes = await Future.wait(
      targets.map(
        (server) => postToServer(
          server,
          path,
          body,
          operationName: operationName,
          timeout: blobTimeout,
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

  Future<RelayFetchResult> fetch(
    String recipientId, {
    String? cursor,
    int limit = 100,
  }) async {
    if (serverPool.isEmpty) {
      log('fetch skip recipient=$recipientId reason=no relay servers');
      return RelayFetchResult(
        messages: const [],
        cursor: cursor,
        hadSuccessfulServer: false,
        allServersUnavailable: false,
      );
    }

    final targets = await serverPool.fetchTargets();
    if (targets.isEmpty) {
      log('fetch skip recipient=$recipientId reason=relay servers unavailable');
      return RelayFetchResult(
        messages: const [],
        cursor: cursor,
        hadSuccessfulServer: false,
        allServersUnavailable: true,
      );
    }

    return _fetchAcrossTargets(
      recipientId,
      targets: targets,
      cursor: cursor,
      limit: limit,
    );
  }

  Future<RelayFetchResult> fetchFromServers(
    String recipientId, {
    required List<String> servers,
    String? cursor,
    int limit = 100,
  }) async {
    final targets = serverPool.resolveServers(servers);
    if (targets.isEmpty) {
      log('fetch-targeted skip recipient=$recipientId reason=no valid relay servers');
      return RelayFetchResult(
        messages: const [],
        cursor: cursor,
        hadSuccessfulServer: false,
        allServersUnavailable: false,
      );
    }
    await serverPool.refreshSharedHealthIfStale(targets);
    return _fetchAcrossTargets(
      recipientId,
      targets: targets,
      cursor: cursor,
      limit: limit,
    );
  }

  Future<RelayFetchOutcome> fetchFromServer(
    Uri server,
    String recipientId, {
    String? cursor,
    required int limit,
  }) async {
    final queryParameters = <String, String>{
      'to': recipientId,
      'limit': limit.toString(),
    };
    final serverCursor = serverPool.fetchCursorFor(server, fallback: cursor);
    if (serverCursor != null) {
      queryParameters['cursor'] = serverCursor;
    }
    final uri = server.replace(
      path: '/relay/fetch',
      queryParameters: queryParameters,
    );

    try {
      final response = await transport.sendGet(uri, timeout: controlTimeout);
      if (response == null) {
        serverPool.markUnhealthy(server, 'fetch timeout');
        return const RelayFetchOutcome();
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        serverPool.markUnhealthy(server, 'fetch ${response.statusCode}');
        return const RelayFetchOutcome();
      }
      serverPool.markHealthy(server);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return const RelayFetchOutcome();
      }

      final messagesRaw = decoded['messages'];
      final cursorRaw = decoded['cursor'];
      if (messagesRaw is! List) {
        return const RelayFetchOutcome();
      }

      final messages = <RelayEnvelope>[];
      for (final item in messagesRaw) {
        if (item is Map<String, dynamic>) {
          messages.add(RelayEnvelope.fromJson(item));
        }
      }
      final nextCursor = cursorRaw is String ? cursorRaw : serverCursor;
      serverPool.updateFetchCursor(server, nextCursor);
      return RelayFetchOutcome(
        success: true,
        messages: messages,
        cursor: nextCursor,
      );
    } on HttpException {
      serverPool.markUnhealthy(server, 'fetch http');
      return const RelayFetchOutcome();
    } catch (_) {
      serverPool.markUnhealthy(server, 'fetch error');
      return const RelayFetchOutcome();
    }
  }

  Future<RelayPostOutcome> postToServer(
    Uri server,
    String path,
    String body, {
    required String operationName,
    required Duration timeout,
  }) async {
    final uri = server.resolve(path);
    try {
      final response = await transport.sendPost(
        uri,
        body: body,
        timeout: timeout,
      );
      if (response == null) {
        serverPool.markUnhealthy(server, '$operationName timeout');
        return RelayPostOutcome(error: '$operationName timeout');
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        serverPool.markHealthy(server);
        return const RelayPostOutcome(success: true);
      }

      final normalizedBody = response.body.toLowerCase();
      if (response.statusCode == 401 &&
          normalizedBody.contains('invalid signature')) {
        log(
          '$operationName signature rejected server=${server.toString()} '
          'status=${response.statusCode} body=${response.body}',
        );
      }
      serverPool.markUnhealthy(server, '$operationName ${response.statusCode}');
      return RelayPostOutcome(
        error: '$operationName ${response.statusCode}: ${response.body}',
      );
    } on HttpException catch (e) {
      serverPool.markUnhealthy(server, '$operationName http');
      return RelayPostOutcome(error: '$operationName http: $e');
    } catch (e) {
      serverPool.markUnhealthy(server, '$operationName error');
      return RelayPostOutcome(error: e.toString());
    }
  }

  int effectiveQuorum(int available, int requested) {
    if (available <= 0) {
      return 0;
    }
    if (requested <= 1) {
      return 1;
    }
    return requested > available ? available : requested;
  }

  Future<RelayFetchResult> _fetchAcrossTargets(
    String recipientId, {
    required List<Uri> targets,
    required String? cursor,
    required int limit,
  }) async {
    final envelopesById = <String, RelayEnvelope>{};
    final outcomes = await Future.wait(
      targets.map(
        (server) =>
            fetchFromServer(server, recipientId, cursor: cursor, limit: limit),
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
      return RelayFetchResult(
        messages: messages,
        cursor: nextCursor,
        hadSuccessfulServer: true,
        allServersUnavailable: false,
      );
    }

    return RelayFetchResult(
      messages: const [],
      cursor: cursor,
      hadSuccessfulServer: false,
      allServersUnavailable: outcomes.isNotEmpty,
    );
  }
}
