// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import 'package:peerlink/core/security/identity_service.dart';

class ModerationApiClient {
  static const _connectTimeout = Duration(seconds: 10);
  static const _requestTimeout = Duration(seconds: 20);
  static const Set<String> _allowedPaths = <String>{
    '/moderation/reports',
    '/moderation/appeals',
  };

  const ModerationApiClient();

  Future<void> sendReport({
    required Uri baseUri,
    required IdentityService identity,
    required Map<String, dynamic> report,
  }) async {
    final requestId = _normalizeShortString(report['id'], maxLength: 256);
    final reporterPeerId = _normalizeShortString(
      report['reporterPeerId'],
      maxLength: 128,
    );
    final reportedPeerId = _normalizeShortString(
      report['reportedPeerId'],
      maxLength: 128,
    );
    final reason = _normalizeModerationReason(report['reason']);
    final type =
        _normalizeShortString(report['type'], maxLength: 64) ?? 'direct_report';
    if (requestId == null ||
        reporterPeerId == null ||
        reportedPeerId == null ||
        reason == null ||
        reporterPeerId != identity.nodeId) {
      throw ArgumentError.value(report, 'report', 'invalid moderation report');
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    // Metadata-only even when replaying legacy outbox entries.
    const contentEncrypted = false;
    final payloadToSign =
        '$requestId|$reporterPeerId|$reportedPeerId|$reason|'
        '$type|$contentEncrypted|{}|$ts';
    final sig = await _sign(identity, payloadToSign);
    final signingPub = base64Encode(identity.signingPublicKey.bytes);
    await _postJson(baseUri, '/moderation/reports', <String, dynamic>{
      'id': requestId,
      'from': reporterPeerId,
      'ts': ts,
      'sig': sig,
      'signingPub': signingPub,
      'type': type,
      'reason': reason,
      'reporterPeerId': reporterPeerId,
      'reportedPeerId': reportedPeerId,
      'contentEncrypted': contentEncrypted,
      if (report['createdAt'] != null) 'createdAt': report['createdAt'],
    });
  }

  Future<void> sendAppeal({
    required Uri baseUri,
    required IdentityService identity,
    required String text,
  }) async {
    final normalizedText = _normalizeShortString(text, maxLength: 4096);
    if (normalizedText == null) {
      throw ArgumentError.value(text, 'text', 'invalid moderation appeal');
    }
    final peerId = identity.nodeId;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final requestId = _requestId('appeal');
    final payloadToSign = '$requestId|$peerId|$peerId|$normalizedText|$ts';
    final sig = await _sign(identity, payloadToSign);
    final signingPub = base64Encode(identity.signingPublicKey.bytes);
    await _postJson(baseUri, '/moderation/appeals', <String, dynamic>{
      'id': requestId,
      'from': peerId,
      'ts': ts,
      'sig': sig,
      'signingPub': signingPub,
      'peerId': peerId,
      'text': normalizedText,
    });
  }

  Future<Map<String, dynamic>?> fetchStatus({
    required Uri baseUri,
    required String peerId,
  }) async {
    final normalizedPeerId = _normalizeShortString(peerId, maxLength: 128);
    if (normalizedPeerId == null) {
      return null;
    }
    final uri = baseUri.replace(
      path: baseUri.resolve('/moderation/status').path,
      queryParameters: <String, String>{'peerId': normalizedPeerId},
    );
    final client = HttpClient();
    if (uri.scheme.toLowerCase() == 'https') {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }
    try {
      final request = await client.getUrl(uri).timeout(_connectTimeout);
      final response = await request.close().timeout(_requestTimeout);
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'moderation api status=${response.statusCode} path=/moderation/status body=${body.substring(0, body.length > 400 ? 400 : body.length)}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _postJson(
    Uri baseUri,
    String path,
    Map<String, dynamic> payload,
  ) async {
    if (!_allowedPaths.contains(path)) {
      throw ArgumentError.value(
        path,
        'path',
        'unsupported moderation endpoint',
      );
    }
    final uri = baseUri.resolve(path);
    final client = HttpClient();
    if (uri.scheme.toLowerCase() == 'https') {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }
    try {
      final request = await client.postUrl(uri).timeout(_connectTimeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_requestTimeout);
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'moderation api status=${response.statusCode} path=$path body=${body.substring(0, body.length > 400 ? 400 : body.length)}',
          uri: uri,
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _sign(IdentityService identity, String payload) async {
    final signature = await Ed25519().sign(
      utf8.encode(payload),
      keyPair: identity.signingKeyPair,
    );
    return base64Encode(signature.bytes);
  }

  String? _normalizeShortString(dynamic value, {required int maxLength}) {
    if (value == null) {
      return null;
    }
    final normalized = value.toString().trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized.length > maxLength
        ? normalized.substring(0, maxLength)
        : normalized;
  }

  String? _normalizeModerationReason(dynamic value) {
    final normalized = _normalizeShortString(value, maxLength: 64);
    if (normalized == null) {
      return null;
    }
    switch (normalized) {
      case 'illegalContent':
      case 'illegalcontent':
        return 'illegal_content';
      case 'abusiveBehavior':
      case 'abusivebehavior':
        return 'abusive_behavior';
      default:
        return normalized;
    }
  }

  String _requestId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = now.toRadixString(16).substring(0, 8);
    return 'moderation:$prefix:$now:$random';
  }
}
