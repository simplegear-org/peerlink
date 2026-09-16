import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/core/security/peer_identity_bundle_v3.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';
import 'package:peerlink/features/invites/application/invite_api.dart';
import 'package:peerlink/features/invites/domain/invite_manifest.dart';
import 'package:peerlink/features/invites/infrastructure/invite_manifest_client.dart';

void main() {
  final now = DateTime.utc(2026, 9, 10, 12);

  Map<String, dynamic> manifest({
    int version = InviteManifest.supportedVersion,
    String expiration = '2026-09-11T12:00:00Z',
    String? username = 'Vladimir',
    Map<String, dynamic>? servers,
  }) {
    const peerId = 'peer-a';
    final inviter = <String, dynamic>{
      'peerId': peerId,
      'identityBundle': const PeerIdentityBundleV3(
        peerId: peerId,
        signingPublicKey: 'signing',
        agreementPublicKey: 'agreement',
        signature: 'signature',
      ).toJson(),
    };
    if (username != null) inviter['username'] = username;
    final result = <String, dynamic>{
      'version': version,
      'inviteId': 'invite-123',
      'expiration': expiration,
      'inviter': inviter,
    };
    if (servers != null) result['servers'] = servers;
    return result;
  }

  test('accepts a valid manifest with optional metadata omitted', () {
    final invite = InviteManifest.fromJson(manifest(username: null), now: now);

    expect(invite.inviteId, 'invite-123');
    expect(invite.peerId, 'peer-a');
    expect(invite.username, isNull);
    expect(invite.serverConfig.bootstrap, isEmpty);
  });

  test('rejects expired and unsupported manifests', () {
    expect(
      () => InviteManifest.fromJson(
        manifest(expiration: '2026-09-10T12:00:00Z'),
        now: now,
      ),
      throwsFormatException,
    );
    expect(
      () => InviteManifest.fromJson(manifest(version: 2), now: now),
      throwsFormatException,
    );
  });

  test('rejects identity mismatch and malformed display/server metadata', () {
    final mismatched = manifest();
    final inviter = Map<String, dynamic>.from(mismatched['inviter'] as Map);
    inviter['peerId'] = 'peer-b';
    mismatched['inviter'] = inviter;

    expect(
      () => InviteManifest.fromJson(mismatched, now: now),
      throwsFormatException,
    );
    final numericUsername = manifest();
    (numericUsername['inviter'] as Map<String, dynamic>)['username'] = 42;
    expect(
      () => InviteManifest.fromJson(numericUsername, now: now),
      throwsFormatException,
    );
    final malformedServers = manifest();
    malformedServers['servers'] = 'bad';
    expect(
      () => InviteManifest.fromJson(malformedServers, now: now),
      throwsFormatException,
    );
  });

  test(
    'creates a signed manifest and returns only a short invite URL',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      server.listen((request) async {
        expect(request.method, 'POST');
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body['version'], InviteManifest.supportedVersion);
        expect(body['manifestSignature'], 'signed-manifest');
        final inviter = body['inviter'] as Map;
        expect(inviter['peerId'], 'peer-local');
        expect(inviter['username'], 'Vladimir');
        expect((body['servers'] as Map)['bootstrap'], <String>['https://boot']);
        request.response
          ..statusCode = HttpStatus.created
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(<String, String>{'token': 'abcdefghijklmnopqrstuv'}),
          );
        await request.response.close();
      });

      final client = InviteManifestClient(
        baseUri: Uri.parse(
          'http://${server.address.address}:${server.port}/invites',
        ),
      );
      final url = await client.create(
        InviteCreateRequest(
          peerId: 'peer-local',
          identityBundle: const <String, dynamic>{'type': 'test'},
          sign: (manifest) async {
            expect(manifest['manifestSignature'], isNull);
            return 'signed-manifest';
          },
          username: ' Vladimir ',
          serverConfig: const ServerConfigPayload(
            bootstrap: <String>['https://boot'],
            relay: <String>[],
            turn: <TurnServerConfig>[],
            push: <String>[],
          ),
        ),
      );

      expect(url, 'https://simplegear.org/i/abcdefghijklmnopqrstuv');
    },
  );
}
