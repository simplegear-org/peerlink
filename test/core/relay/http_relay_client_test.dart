import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peerlink/core/relay/http_relay_client.dart';
import 'package:peerlink/core/relay/relay_models.dart';

void main() {
  late RelayEnvelope sampleEnvelope;

  setUp(() {
    sampleEnvelope = RelayEnvelope(
      id: 'msg1',
      from: 'alice',
      to: 'bob',
      timestampMs: 1000,
      ttlSeconds: 3600,
      payload: Uint8List.fromList([1, 2, 3]),
      signature: Uint8List.fromList([11, 22]),
      senderSigningPublicKey: Uint8List.fromList([33, 44]),
    );
  });

  test('httpsOnly skips non-https server', () {
    final httpOnlyClient = HttpRelayClient(
      servers: ['http://relay.example'],
      httpsOnly: true,
    );
    expect(httpOnlyClient.serverStatuses, isEmpty);

    final httpsClient = HttpRelayClient(
      servers: ['https://relay.example'],
      httpsOnly: true,
    );
    expect(httpsClient.serverStatuses.single.url, 'https://relay.example');
  });

  test('store failover uses fallback server', () async {
    final calls = <Uri>[];
    final client = HttpRelayClient(
      servers: ['http://first.example', 'http://second.example'],
      httpClient: MockClient((request) async {
        calls.add(request.url);
        if (request.url.path == '/health' &&
            request.url.host == 'first.example') {
          return http.Response('error', 500);
        }
        if (request.url.path == '/health') {
          return http.Response('', 204);
        }
        if (request.url.host == 'first.example') {
          return http.Response('unexpected first store', 500);
        }
        return http.Response('', 204);
      }),
    );

    await client.store(sampleEnvelope);

    final healthCalls = calls.where((uri) => uri.path == '/health').toList();
    final storeCalls = calls
        .where((uri) => uri.path == '/relay/store')
        .toList();
    expect(healthCalls.map((uri) => uri.host), <String>[
      'first.example',
      'second.example',
    ]);
    expect(storeCalls, hasLength(1));
    expect(storeCalls.single.host, 'second.example');
  });

  test('store failover treats POST connect error as relay failure', () async {
    final calls = <Uri>[];
    final client = HttpRelayClient(
      servers: [
        'http://first.example',
        'http://second.example',
        'http://third.example',
      ],
      httpClient: MockClient((request) async {
        calls.add(request.url);
        if (request.url.path == '/health') {
          return http.Response('', 204);
        }
        if (request.url.host == 'first.example') {
          throw const HttpException(
            'Connection closed before full header was received',
          );
        }
        return http.Response('', 204);
      }),
    );

    await client.store(sampleEnvelope);

    final storeCalls = calls
        .where((uri) => uri.path == '/relay/store')
        .toList();
    expect(storeCalls.map((uri) => uri.host).toSet(), <String>{
      'first.example',
      'second.example',
      'third.example',
    });
  });

  test('fetch returns parsed envelope and cursor', () async {
    final client = HttpRelayClient(
      servers: ['http://relay.example'],
      httpClient: MockClient((request) async {
        final responseBody = jsonEncode({
          'messages': [sampleEnvelope.toJson()],
          'cursor': 'next-cursor',
        });
        return http.Response(
          responseBody,
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await client.fetch('bob', limit: 10);

    expect(result.cursor, 'next-cursor');
    expect(result.messages, hasLength(1));
    expect(result.messages.first.id, sampleEnvelope.id);
  });

  test('fetch without configured relays returns empty result', () async {
    final client = HttpRelayClient(servers: const <String>[]);

    final result = await client.fetch('bob', cursor: 'cursor-1', limit: 10);

    expect(result.messages, isEmpty);
    expect(result.cursor, 'cursor-1');
  });

  test('store without configured relays throws relay unavailable', () async {
    final client = HttpRelayClient(servers: const <String>[]);

    await expectLater(
      client.store(sampleEnvelope),
      throwsA(isA<RelayUnavailableException>()),
    );
  });

  test(
    'store with configured but unavailable relays throws relay unavailable',
    () async {
      final client = HttpRelayClient(
        servers: ['http://relay.example'],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('offline', 503);
          }
          return http.Response('unexpected', 500);
        }),
      );

      await expectLater(
        client.store(sampleEnvelope),
        throwsA(
          isA<RelayUnavailableException>().having(
            (error) => error.details,
            'details',
            RelayUnavailableException.unavailable,
          ),
        ),
      );
    },
  );

  test(
    'fetch treats closed header connection as transient relay failure',
    () async {
      final client = HttpRelayClient(
        servers: ['http://relay.example'],
        httpClient: MockClient((request) async {
          throw const HttpException(
            'Connection closed before full header was received',
          );
        }),
      );

      final result = await client.fetch('bob', limit: 10);

      expect(result.messages, isEmpty);
      expect(result.cursor, isNull);
    },
  );

  test(
    'fetch with configured but unavailable relays returns outage result',
    () async {
      final client = HttpRelayClient(
        servers: ['http://relay.example'],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('offline', 503);
          }
          return http.Response('unexpected', 500);
        }),
      );

      final result = await client.fetch('bob', limit: 10);

      expect(result.messages, isEmpty);
      expect(result.hadSuccessfulServer, isFalse);
      expect(result.allServersUnavailable, isTrue);
    },
  );

  test('fetch treats connection refused as transient relay failure', () async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();

    final client = HttpRelayClient(servers: ['http://127.0.0.1:$port']);

    final result = await client.fetch('bob', limit: 10);

    expect(result.messages, isEmpty);
    expect(result.cursor, isNull);
  });

  test(
    'fetchBlob falls back to remaining relays after shortlist 404s',
    () async {
      final client = HttpRelayClient(
        servers: [
          'http://relay1.example',
          'http://relay2.example',
          'http://relay3.example',
          'http://relay4.example',
        ],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('', 200);
          }
          if (request.url.path == '/relay/blob/blob-123') {
            if (request.url.host == 'relay4.example') {
              return http.Response(
                jsonEncode({
                  'id': 'blob-123',
                  'fileName': 'hello.txt',
                  'payload': base64Encode(utf8.encode('hello')),
                  'sizeBytes': 5,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }
          return http.Response('unexpected', 500);
        }),
      );

      final result = await client.fetchBlob('blob-123');

      expect(result.id, 'blob-123');
      expect(result.fileName, 'hello.txt');
      expect(utf8.decode(result.payload), 'hello');
    },
  );

  test(
    'fetchBlob falls back to remaining relays after mixed timeout and 404',
    () async {
      final client = HttpRelayClient(
        servers: [
          'http://relay1.example',
          'http://relay2.example',
          'http://relay3.example',
          'http://relay4.example',
        ],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('', 200);
          }
          if (request.url.path == '/relay/blob/blob-123') {
            if (request.url.host == 'relay1.example') {
              throw const SocketException('timed out');
            }
            if (request.url.host == 'relay4.example') {
              return http.Response(
                jsonEncode({
                  'id': 'blob-123',
                  'fileName': 'hello.txt',
                  'payload': base64Encode(utf8.encode('hello')),
                  'sizeBytes': 5,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('not found', 404);
          }
          return http.Response('unexpected', 500);
        }),
      );

      final result = await client.fetchBlob('blob-123');

      expect(result.id, 'blob-123');
      expect(result.fileName, 'hello.txt');
      expect(utf8.decode(result.payload), 'hello');
    },
  );

  test(
    'fetchBlob returns notFound sentinel when all relays return 404',
    () async {
      final client = HttpRelayClient(
        servers: [
          'http://relay1.example',
          'http://relay2.example',
          'http://relay3.example',
        ],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('', 200);
          }
          if (request.url.path == '/relay/blob/missing-blob') {
            return http.Response('not found', 404);
          }
          return http.Response('unexpected', 500);
        }),
      );

      final result = await client.fetchBlob('missing-blob');

      expect(result.isNotFound, isTrue);
      expect(result.id, 'missing-blob');
      expect(result.payload, isEmpty);
    },
  );

  test('fetchBlob does not report download progress for a 404 body', () async {
    final progress = <int>[];
    final client = HttpRelayClient(
      servers: ['http://relay.example'],
      httpClient: MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response('', 200);
        }
        return http.Response('{"error":"blob not found"}', 404);
      }),
    );

    final result = await client.fetchBlob(
      'missing-blob',
      onProgress:
          ({required receivedBytes, required totalBytes, required status}) =>
              progress.add(receivedBytes),
    );

    expect(result.isNotFound, isTrue);
    expect(progress, isEmpty);
  });

  test('storeBlob requires every available relay', () async {
    final uploads = <String>[];
    final client = HttpRelayClient(
      servers: [
        'http://relay1.example',
        'http://relay2.example',
        'http://relay3.example',
      ],
      httpClient: MockClient((request) async {
        if (request.url.path == '/health') {
          return http.Response('', 200);
        }
        if (request.url.path == '/relay/blob/upload') {
          uploads.add(request.url.host);
          return request.url.host == 'relay3.example'
              ? http.Response('offline', 503)
              : http.Response('', 200);
        }
        return http.Response('unexpected', 500);
      }),
    );
    final blob = RelayBlobUploadEnvelope(
      id: 'blob-123',
      from: 'alice',
      groupId: 'dm:alice|bob',
      fileName: 'hello.txt',
      mimeType: 'text/plain',
      timestampMs: 1000,
      ttlSeconds: 3600,
      payload: Uint8List.fromList(utf8.encode('hello')),
      signature: Uint8List.fromList([11, 22]),
      senderSigningPublicKey: Uint8List.fromList([33, 44]),
    );

    await expectLater(client.storeBlob(blob), throwsA(isA<Exception>()));

    expect(
      uploads,
      containsAll(<String>[
        'relay1.example',
        'relay2.example',
        'relay3.example',
      ]),
    );
  });

  test(
    'chunked storeBlob reports one monotonic replication progress',
    () async {
      final progress = <int>[];
      final client = HttpRelayClient(
        servers: [
          'http://relay1.example',
          'http://relay2.example',
          'http://relay3.example',
        ],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('', 200);
          }
          if (request.url.path == '/relay/blob/upload/chunk' ||
              request.url.path == '/relay/blob/upload/complete') {
            return http.Response('', 200);
          }
          return http.Response('unexpected', 500);
        }),
      );
      final payload = Uint8List(512 * 1024);
      final blob = RelayBlobUploadEnvelope(
        id: 'blob-123',
        from: 'alice',
        groupId: 'dm:alice|bob',
        fileName: 'large.bin',
        mimeType: 'application/octet-stream',
        timestampMs: 1000,
        ttlSeconds: 3600,
        payload: payload,
        signature: Uint8List.fromList([11, 22]),
        senderSigningPublicKey: Uint8List.fromList([33, 44]),
      );

      await client.storeBlob(
        blob,
        onProgress:
            ({required sentBytes, required totalBytes, required status}) =>
                progress.add(sentBytes),
      );

      expect(progress, orderedEquals(progress.toList()..sort()));
      expect(progress.last, payload.length);
      expect(progress.where((bytes) => bytes == payload.length), hasLength(1));
    },
  );

  test(
    'chunked storeBlob excludes a relay that times out mid-upload',
    () async {
      final completedServers = <String>[];
      final client = HttpRelayClient(
        servers: [
          'http://relay1.example',
          'http://relay2.example',
          'http://relay3.example',
        ],
        httpClient: MockClient((request) async {
          if (request.url.path == '/health') {
            return http.Response('', 200);
          }
          if (request.url.path == '/relay/blob/upload/chunk' &&
              request.url.host == 'relay1.example') {
            throw const SocketException('timed out');
          }
          if (request.url.path == '/relay/blob/upload/chunk') {
            return http.Response('', 200);
          }
          if (request.url.path == '/relay/blob/upload/complete') {
            completedServers.add(request.url.host);
            return http.Response('', 200);
          }
          return http.Response('unexpected', 500);
        }),
      );
      final blob = RelayBlobUploadEnvelope(
        id: 'blob-123',
        from: 'alice',
        groupId: 'dm:alice|bob',
        fileName: 'large.bin',
        mimeType: 'application/octet-stream',
        timestampMs: 1000,
        ttlSeconds: 3600,
        payload: Uint8List(512 * 1024),
        signature: Uint8List.fromList([11, 22]),
        senderSigningPublicKey: Uint8List.fromList([33, 44]),
      );

      await client.storeBlob(blob);

      expect(completedServers, <String>['relay2.example', 'relay3.example']);
    },
  );
}
