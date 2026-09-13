// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/core/security/peer_identity_bundle_v3.dart';

typedef InviteManifestSigner =
    Future<String> Function(Map<String, dynamic> manifest);

/// Validated canonical representation of a resolved short invite.
class InviteManifest {
  static const int supportedVersion = 1;

  InviteManifest({
    required this.inviteId,
    required this.version,
    required this.expiresAt,
    required this.peerId,
    required this.identityBundleV3,
    required this.serverConfig,
    this.username,
  });

  final String inviteId;
  final int version;
  final DateTime expiresAt;
  final String peerId;
  final String? username;
  final Map<String, dynamic> identityBundleV3;
  final ServerConfigPayload serverConfig;

  factory InviteManifest.fromJson(Map<String, dynamic> json, {DateTime? now}) {
    final version = json['version'];
    if (version is! int || version != supportedVersion) {
      throw const FormatException('Неподдерживаемая версия приглашения');
    }
    final inviteId = json['inviteId'];
    if (inviteId is! String ||
        inviteId.trim().isEmpty ||
        inviteId.length > 128) {
      throw const FormatException('В приглашении нет корректного inviteId');
    }
    final expiration = json['expiration'];
    final expiresAt = expiration is String
        ? DateTime.tryParse(expiration)?.toUtc()
        : null;
    if (expiresAt == null) {
      throw const FormatException(
        'В приглашении нет корректного срока действия',
      );
    }
    if (!expiresAt.isAfter((now ?? DateTime.now()).toUtc())) {
      throw const FormatException('Срок действия приглашения истёк');
    }
    final inviter = json['inviter'];
    if (inviter is! Map) {
      throw const FormatException('В приглашении нет пригласившего');
    }
    final inviterMap = Map<String, dynamic>.from(inviter);
    final rawPeerId = inviterMap['peerId'];
    final peerId = rawPeerId is String ? rawPeerId.trim() : '';
    final bundle = inviterMap['identityBundle'];
    if (peerId.isEmpty || bundle is! Map) {
      throw const FormatException('В приглашении нет проверяемой identity');
    }
    final identityBundle = Map<String, dynamic>.from(bundle);
    final parsedBundle = PeerIdentityBundleV3.fromJson(identityBundle);
    if (parsedBundle == null || parsedBundle.peerId != peerId) {
      throw const FormatException(
        'Identity приглашения не соответствует Peer ID',
      );
    }
    final rawUsername = inviterMap['username'];
    if (rawUsername != null && rawUsername is! String) {
      throw const FormatException('Недопустимое имя пригласившего');
    }
    final username = _validateUsername(rawUsername as String?);
    final servers = json['servers'];
    if (servers != null && servers is! Map) {
      throw const FormatException('Недопустимые servers приглашения');
    }
    return InviteManifest(
      inviteId: inviteId.trim(),
      version: version,
      expiresAt: expiresAt,
      peerId: peerId,
      username: username,
      identityBundleV3: identityBundle,
      serverConfig: ServerConfigPayload.fromJson(
        servers is Map
            ? Map<String, dynamic>.from(servers)
            : <String, dynamic>{
                'type': ServerConfigPayload.type,
                'version': ServerConfigPayload.version,
                'bootstrap': const <String>[],
                'relay': const <String>[],
                'turn': const <Map<String, dynamic>>[],
                'push': const <String>[],
              },
      ),
    );
  }

  static String? _validateUsername(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return null;
    if (normalized.length > 64 ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(normalized)) {
      throw const FormatException('Недопустимое имя пригласившего');
    }
    return normalized;
  }
}

class InviteManifestClient {
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

  Future<InviteManifest> resolve(String token) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(token)) {
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

  Future<String> create({
    required String peerId,
    required Map<String, dynamic> identityBundle,
    required InviteManifestSigner sign,
    String? username,
    ServerConfigPayload? servers,
  }) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      throw const FormatException('Нет Peer ID для приглашения');
    }
    final manifest = <String, dynamic>{
      'version': InviteManifest.supportedVersion,
      'inviter': <String, dynamic>{
        'peerId': normalizedPeerId,
        'identityBundle': identityBundle,
        if (username?.trim().isNotEmpty == true) 'username': username!.trim(),
      },
      if (servers != null) 'servers': servers.toJson(),
    };
    manifest['manifestSignature'] = await sign(manifest);
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
      if (token is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{22,128}$').hasMatch(token)) {
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

class InviteResolveException implements Exception {
  const InviteResolveException(this.message, {required this.retryable});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}
