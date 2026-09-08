import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:peerlink/core/runtime/moderation_api_client.dart';
import 'package:peerlink/core/security/identity_service.dart';

class _MemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late HttpServer server;
  late Uri baseUri;
  late IdentityService identity;
  late List<Map<String, dynamic>> requests;

  setUp(() async {
    requests = <Map<String, dynamic>>[];
    identity = IdentityService(keyStore: _MemoryIdentityKeyStore());
    await identity.initialize();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      requests.add(<String, dynamic>{
        'method': request.method,
        'path': request.uri.path,
        'query': request.uri.queryParameters,
        'body': body.isEmpty ? null : jsonDecode(body),
      });
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'score': <String, dynamic>{
              'policyState': 'warning',
              'reportCount': 2,
              'reporterCount': 1,
            },
          }),
        );
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  test('sends metadata-only report to moderation endpoint', () async {
    await const ModerationApiClient().sendReport(
      baseUri: baseUri,
      identity: identity,
      report: <String, dynamic>{
        'id': 'report-1',
        'type': 'direct_report',
        'reason': 'illegalContent',
        'reporterPeerId': identity.nodeId,
        'reportedPeerId': 'bad-peer',
        'contentEncrypted': true,
        'content': {'text': 'private text', 'sessionKey': 'private key'},
        'history': 'private history',
        'createdAt': '2026-08-24T00:00:00.000Z',
      },
    );

    expect(requests.single['method'], 'POST');
    expect(requests.single['path'], '/moderation/reports');
    final body = Map<String, dynamic>.from(requests.single['body'] as Map);
    expect(body['reason'], 'illegal_content');
    expect(body['reporterPeerId'], identity.nodeId);
    expect(body['reportedPeerId'], 'bad-peer');
    expect(body.containsKey('sig'), isTrue);
    expect(body.containsKey('signingPub'), isTrue);
    expect(body['contentEncrypted'], isFalse);
    expect(body.containsKey('encryptedContent'), isFalse);
    expect(jsonEncode(body), isNot(contains('private')));
    final payload =
        '${body['id']}|${body['from']}|${body['reportedPeerId']}|${body['reason']}|${body['type']}|false|{}|${body['ts']}';
    expect(
      await Ed25519().verify(
        utf8.encode(payload),
        signature: Signature(
          base64Decode(body['sig'] as String),
          publicKey: SimplePublicKey(
            base64Decode(body['signingPub'] as String),
            type: KeyPairType.ed25519,
          ),
        ),
      ),
      isTrue,
    );
  });

  test('fetches status from moderation endpoint', () async {
    final status = await const ModerationApiClient().fetchStatus(
      baseUri: baseUri,
      peerId: 'peer-1',
    );

    expect(requests.single['method'], 'GET');
    expect(requests.single['path'], '/moderation/status');
    expect(requests.single['query'], <String, String>{'peerId': 'peer-1'});
    expect(status?['score'], isA<Map>());
  });
}
