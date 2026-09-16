// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:peerlink/features/invites/application/invite_api.dart';
import 'package:peerlink/features/invites/domain/invite_manifest.dart';

class InviteManifestClient implements InviteApi {
  static const _baseUrl = String.fromEnvironment(
    'PEERLINK_INVITE_API_BASE_URL',
    defaultValue: 'https://tangash.org/invites',
  );

  InviteManifestClient({
    HttpClient Function()? httpClientFactory,
    DateTime Function()? now,
    Uri? baseUri,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _now = now ?? DateTime.now,
       _baseUri = baseUri ?? Uri.parse(_baseUrl);

  final HttpClient Function() _httpClientFactory;
  final DateTime Function() _now;
  final Uri _baseUri;

  @override
  Future<InviteManifest> resolve(String token) async {
    if (!InviteManifest.isValidToken(token)) {
      throw const FormatException('Недопустимый токен приглашения');
    }
    final client = _httpClientFactory();
    try {
      final uri = _baseUri.replace(
        pathSegments: <String>[..._baseUri.pathSegments, token],
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw InviteResolveException(
          'Приглашение недоступно или истекло',
          retryable:
              response.statusCode == HttpStatus.requestTimeout ||
              response.statusCode == HttpStatus.tooManyRequests ||
              response.statusCode >= HttpStatus.internalServerError,
        );
      }
      final body = await utf8.decoder.bind(response).join();
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Неверный manifest приглашения');
      }
      return InviteManifest.fromJson(
        Map<String, dynamic>.from(decoded),
        now: _now(),
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<String> create(InviteCreateRequest request) async {
    final normalizedPeerId = request.peerId.trim();
    if (normalizedPeerId.isEmpty) {
      throw const FormatException('Нет Peer ID для приглашения');
    }
    final manifest = <String, dynamic>{
      'version': InviteManifest.supportedVersion,
      'inviter': <String, dynamic>{
        'peerId': normalizedPeerId,
        'identityBundle': request.identityBundle,
        if (request.username?.trim().isNotEmpty == true)
          'username': request.username!.trim(),
      },
      if (request.serverConfig != null)
        'servers': request.serverConfig!.toJson(),
    };
    manifest['manifestSignature'] = await request.sign(manifest);
    final client = _httpClientFactory();
    try {
      final request = await client
          .postUrl(_baseUri)
          .timeout(const Duration(seconds: 8));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(manifest));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.created) {
        throw InviteResolveException(
          'Не удалось создать приглашение',
          retryable:
              response.statusCode == HttpStatus.requestTimeout ||
              response.statusCode == HttpStatus.tooManyRequests ||
              response.statusCode >= HttpStatus.internalServerError,
        );
      }
      final decoded = jsonDecode(await utf8.decoder.bind(response).join());
      final token = decoded is Map ? decoded['token'] : null;
      if (token is! String || !InviteManifest.isValidToken(token)) {
        throw const FormatException(
          'Сервер вернул некорректный token приглашения',
        );
      }
      return 'https://simplegear.org/i/$token';
    } finally {
      client.close(force: true);
    }
  }
}
