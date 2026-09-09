// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'relay_http_message_api.dart';
import 'relay_http_server_pool.dart';
import 'relay_http_transport.dart';
import 'relay_http_types.dart';
import 'relay_models.dart';
import 'relay_transfer_status.dart';

class RelayHttpBlobApi {
  final RelayHttpServerPool serverPool;
  final RelayHttpTransport transport;
  final RelayHttpMessageApi messageApi;
  final void Function(String message) log;
  final Duration blobTimeout;
  final int blobChunkSizeBytes;
  final int blobChunkUploadConcurrency;
  final int chunkedUploadThresholdBytes;

  const RelayHttpBlobApi({
    required this.serverPool,
    required this.transport,
    required this.messageApi,
    required this.log,
    required this.blobTimeout,
    required this.blobChunkSizeBytes,
    required this.blobChunkUploadConcurrency,
    required this.chunkedUploadThresholdBytes,
  });

  Future<void> storeBlob(
    RelayBlobUploadEnvelope envelope, {
    RelayUploadProgressCallback? onProgress,
  }) async {
    if (envelope.payload.length >= chunkedUploadThresholdBytes) {
      onProgress?.call(
        sentBytes: 0,
        totalBytes: envelope.payload.length,
        status: RelayTransferStatus.outgoingUploadingRelay,
      );
      final chunkedOk = await storeBlobChunked(
        envelope,
        onProgress: onProgress,
      );
      if (chunkedOk) {
        return;
      }
      log('blob-upload chunked unavailable, fallback to single upload');
    }
    onProgress?.call(
      sentBytes: 0,
      totalBytes: envelope.payload.length,
      status: RelayTransferStatus.outgoingUploadingRelay,
    );
    await messageApi.postToQuorum(
      '/relay/blob/upload',
      envelope.toJson(),
      operationName: 'blob-upload',
      quorum: serverPool.maxActiveRelayPool,
    );
    onProgress?.call(
      sentBytes: envelope.payload.length,
      totalBytes: envelope.payload.length,
      status: RelayTransferStatus.outgoingFinalizing,
    );
  }

  Future<bool> storeBlobChunked(
    RelayBlobUploadEnvelope envelope, {
    RelayUploadProgressCallback? onProgress,
  }) async {
    if (serverPool.isEmpty) {
      log('blob-upload chunked skip reason=no relay servers');
      throw RelayUnavailableException();
    }
    final totalBytes = envelope.payload.length;
    if (totalBytes == 0) {
      return false;
    }
    final totalChunks = (totalBytes / blobChunkSizeBytes).ceil();

    final targets = await serverPool.liveServers(
      limit: serverPool.maxActiveRelayPool,
    );
    if (targets.isEmpty) {
      log('blob-upload chunked skip reason=relay servers unavailable');
      throw RelayUnavailableException(
        details: RelayUnavailableException.unavailable,
      );
    }
    log(
      'blob-upload chunked start bytes=$totalBytes chunks=$totalChunks '
      'chunkSize=$blobChunkSizeBytes servers=${targets.length}',
    );
    var successfulServers = 0;
    var unavailableServers = 0;
    void reportReplicatedProgress({
      required int sentBytes,
      required String status,
    }) {
      // UI progress represents the complete replication, rather than the
      // current replica. This prevents the indicator from restarting for
      // every relay while the same blob is replicated.
      final boundedBytes = sentBytes < 0
          ? 0
          : sentBytes > totalBytes
          ? totalBytes
          : sentBytes;
      final bytesBeforeFinalize =
          status == RelayTransferStatus.outgoingFinalizing &&
              boundedBytes == totalBytes
          ? totalBytes - 1
          : boundedBytes;
      final activeReplicaCount = targets.length - unavailableServers;
      onProgress?.call(
        sentBytes:
            (successfulServers * totalBytes + bytesBeforeFinalize) ~/
            activeReplicaCount,
        totalBytes: totalBytes,
        status: status,
      );
    }

    for (final server in targets) {
      var endpointMissing = false;
      try {
        log(
          'blob-upload chunked server=${server.toString()} '
          'bytes=$totalBytes chunks=$totalChunks',
        );
        var nextChunkIndex = 0;
        var completedChunks = 0;
        var completedBytes = 0;
        Object? firstError;

        Future<void> uploadWorker() async {
          while (!endpointMissing && firstError == null) {
            final chunkIndex = nextChunkIndex;
            nextChunkIndex += 1;
            if (chunkIndex >= totalChunks) {
              return;
            }

            final start = chunkIndex * blobChunkSizeBytes;
            final end = start + blobChunkSizeBytes > totalBytes
                ? totalBytes
                : start + blobChunkSizeBytes;
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
            final chunkResponse = await transport.sendPost(
              server.resolve('/relay/blob/upload/chunk'),
              body: jsonEncode(chunkRequest),
              timeout: blobTimeout,
            );
            if (chunkResponse == null) {
              firstError ??= HttpException('blob chunk timeout');
              return;
            }
            if (chunkResponse.statusCode == 404) {
              endpointMissing = true;
              return;
            }
            if (chunkResponse.statusCode < 200 ||
                chunkResponse.statusCode >= 300) {
              firstError ??= HttpException(
                'blob chunk failed ${chunkResponse.statusCode}: ${chunkResponse.body}',
              );
              return;
            }

            completedChunks += 1;
            completedBytes += chunkBytes.length;
            reportReplicatedProgress(
              sentBytes: completedBytes,
              status: completedChunks == totalChunks
                  ? RelayTransferStatus.outgoingFinalizing
                  : RelayTransferStatus.outgoingUploadingRelay,
            );
            if (completedChunks == 1 ||
                completedChunks == totalChunks ||
                completedChunks % 5 == 0) {
              log(
                'blob-upload chunked progress server=${server.toString()} '
                'chunk=$completedChunks/$totalChunks '
                'sent=$completedBytes/$totalBytes',
              );
            }
          }
        }

        final workerCount = totalChunks < blobChunkUploadConcurrency
            ? totalChunks
            : blobChunkUploadConcurrency;
        await Future.wait(
          List<Future<void>>.generate(workerCount, (_) => uploadWorker()),
        );

        if (firstError != null) {
          serverPool.markUnhealthy(server, 'blob-upload chunk failed');
          throw firstError!;
        }
        if (endpointMissing) {
          log('blob-upload chunk endpoint missing server=${server.toString()}');
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
        final completeResponse = await transport.sendPost(
          server.resolve('/relay/blob/upload/complete'),
          body: jsonEncode(completeRequest),
          timeout: blobTimeout,
        );
        if (completeResponse == null) {
          serverPool.markUnhealthy(server, 'blob-upload complete timeout');
          throw HttpException('blob complete timeout');
        }
        if (completeResponse.statusCode == 404) {
          log(
            'blob-upload complete endpoint missing server=${server.toString()}',
          );
          continue;
        }
        if (completeResponse.statusCode < 200 ||
            completeResponse.statusCode >= 300) {
          serverPool.markUnhealthy(
            server,
            'blob-upload complete ${completeResponse.statusCode}',
          );
          throw HttpException(
            'blob complete failed ${completeResponse.statusCode}: ${completeResponse.body}',
          );
        }
        serverPool.markHealthy(server);
        log(
          'blob-upload chunked ok server=${server.toString()} '
          'bytes=$totalBytes chunks=$totalChunks',
        );
        successfulServers += 1;
        final activeReplicaCount = targets.length - unavailableServers;
        onProgress?.call(
          sentBytes: successfulServers * totalBytes ~/ activeReplicaCount,
          totalBytes: totalBytes,
          status: successfulServers == activeReplicaCount
              ? RelayTransferStatus.outgoingFinalizing
              : RelayTransferStatus.outgoingUploadingRelay,
        );
      } on HttpException catch (e) {
        serverPool.markUnhealthy(server, 'blob-upload chunked http');
        unavailableServers += 1;
        log('blob-upload chunked failed server=${server.toString()} error=$e');
        continue;
      } catch (e) {
        serverPool.markUnhealthy(server, 'blob-upload chunked error');
        unavailableServers += 1;
        log('blob-upload chunked failed server=${server.toString()} error=$e');
        continue;
      }
    }
    final requiredSuccesses = targets.length - unavailableServers;
    if (successfulServers > 0 && successfulServers >= requiredSuccesses) {
      return true;
    }
    log(
      'blob-upload chunked quorum failed success=$successfulServers/'
      '${targets.length} unavailable=$unavailableServers '
      'required=$requiredSuccesses',
    );
    return false;
  }

  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    RelayDownloadProgressCallback? onProgress,
  }) async {
    if (serverPool.isEmpty) {
      log('blob-fetch skip blobId=$blobId reason=no relay servers');
      throw RelayUnavailableException();
    }
    final attempted = <String>{};
    final errors = <String>[];
    final initialTargets = await serverPool.liveServers(
      limit: serverPool.maxActiveRelayPool,
    );
    if (initialTargets.isEmpty) {
      log('blob-fetch skip blobId=$blobId reason=relay servers unavailable');
      throw RelayUnavailableException(
        details: RelayUnavailableException.unavailable,
      );
    }
    final initialBatch = collectBlobFetchBatch(
      attempted,
      errors,
      await fetchBlobAcrossServers(
        initialTargets,
        blobId,
        onProgress: onProgress,
      ),
    );
    if (initialBatch.download != null) {
      return initialBatch.download!;
    }

    final initialNotFoundErrors = initialBatch.errors
        .where((error) => error.startsWith('blob-fetch 404'))
        .toList(growable: false);
    if (initialNotFoundErrors.isNotEmpty &&
        attempted.length < serverPool.totalServers) {
      final fallbackTargets = serverPool
          .prioritizedServers(limit: serverPool.totalServers)
          .where((server) => !attempted.contains(server.toString()))
          .toList(growable: false);
      final fallbackBatch = collectBlobFetchBatch(
        attempted,
        errors,
        await fetchBlobAcrossServers(
          fallbackTargets,
          blobId,
          onProgress: onProgress,
        ),
      );
      if (fallbackBatch.download != null) {
        return fallbackBatch.download!;
      }
    }

    final notFoundErrors = errors
        .where((error) => error.startsWith('blob-fetch 404'))
        .toList(growable: false);
    if (notFoundErrors.isNotEmpty && notFoundErrors.length == errors.length) {
      log(
        'blob-fetch blobId=$blobId not-found attempted=${attempted.length}/${serverPool.totalServers}',
      );
      return RelayBlobDownload.notFound(blobId);
    }

    throw Exception('Relay blob-fetch failed: ${errors.join(' | ')}');
  }

  Future<List<RelayBlobFetchServerOutcome>> fetchBlobAcrossServers(
    List<Uri> servers,
    String blobId, {
    RelayDownloadProgressCallback? onProgress,
  }) {
    return Future.wait(
      servers.map(
        (server) async => RelayBlobFetchServerOutcome(
          server: server,
          outcome: await fetchBlobFromServer(
            server,
            blobId,
            onProgress: onProgress,
          ),
        ),
      ),
    );
  }

  RelayBlobFetchBatchOutcome collectBlobFetchBatch(
    Set<String> attempted,
    List<String> errors,
    List<RelayBlobFetchServerOutcome> outcomes,
  ) {
    if (outcomes.isEmpty) {
      return const RelayBlobFetchBatchOutcome();
    }
    final localErrors = <String>[];
    for (final result in outcomes) {
      attempted.add(result.server.toString());
      final download = result.outcome.download;
      if (download != null) {
        return RelayBlobFetchBatchOutcome(download: download);
      }
      if (result.outcome.error != null) {
        localErrors.add(result.outcome.error!);
        errors.add(result.outcome.error!);
      }
    }
    return RelayBlobFetchBatchOutcome(errors: localErrors);
  }

  Future<RelayBlobFetchOutcome> fetchBlobFromServer(
    Uri server,
    String blobId, {
    RelayDownloadProgressCallback? onProgress,
  }) async {
    final uri = server.resolve('/relay/blob/$blobId');
    try {
      final response = await transport.sendGet(
        uri,
        onProgress: onProgress,
        timeout: blobTimeout,
      );
      if (response == null) {
        serverPool.markUnhealthy(server, 'blob-fetch timeout');
        return const RelayBlobFetchOutcome(error: 'blob-fetch timeout');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode != 404) {
          serverPool.markUnhealthy(server, 'blob-fetch ${response.statusCode}');
        }
        return RelayBlobFetchOutcome(
          error: 'blob-fetch ${response.statusCode}: ${response.body}',
        );
      }
      serverPool.markHealthy(server);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return RelayBlobFetchOutcome(
          error: 'blob-fetch invalid response type: ${decoded.runtimeType}',
        );
      }
      final id = decoded['id'];
      final fileName = decoded['fileName'];
      final payload = decoded['payload'];
      final mimeType = decoded['mimeType'];
      final sizeBytes = decoded['sizeBytes'];
      if (id is! String || fileName is! String || payload is! String) {
        return const RelayBlobFetchOutcome(error: 'blob-fetch invalid fields');
      }
      final payloadBytes = base64Decode(payload);
      onProgress?.call(
        receivedBytes: payloadBytes.length,
        totalBytes: payloadBytes.length,
        status: RelayTransferStatus.incomingDownloadComplete,
      );
      return RelayBlobFetchOutcome(
        download: RelayBlobDownload(
          id: id,
          fileName: fileName,
          mimeType: mimeType is String ? mimeType : null,
          sizeBytes: sizeBytes is int ? sizeBytes : payloadBytes.length,
          payload: Uint8List.fromList(payloadBytes),
        ),
      );
    } on HttpException catch (e) {
      serverPool.markUnhealthy(server, 'blob-fetch http');
      return RelayBlobFetchOutcome(error: 'blob-fetch http: $e');
    } catch (e) {
      serverPool.markUnhealthy(server, 'blob-fetch error');
      return RelayBlobFetchOutcome(error: e.toString());
    }
  }
}
