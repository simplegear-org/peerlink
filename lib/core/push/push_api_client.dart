import 'dart:convert';
import 'dart:io';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:cryptography/cryptography.dart';

import '../runtime/app_file_logger.dart';
import '../security/identity_service.dart';
import '../turn/turn_server_config.dart';

class PushServersMetadata {
  final List<String> bootstrap;
  final List<String> relay;
  final List<String> push;
  final List<TurnServerConfig> turn;

  const PushServersMetadata({
    required this.bootstrap,
    required this.relay,
    required this.push,
    required this.turn,
  });
}

class PushDeliveryOptions {
  final bool standard;
  final bool voip;

  const PushDeliveryOptions({
    this.standard = true,
    this.voip = false,
  });
}

class PushApiClient {
  static const _connectTimeout = Duration(seconds: 10);
  static const _requestTimeout = Duration(seconds: 20);
  static const Set<String> _allowedPaths = <String>{
    '/devices/register',
    '/devices/unregister',
    '/events/push',
  };

  PushApiClient();

  Future<void> registerDevice({
    required Uri baseUri,
    required IdentityService identity,
    required String userId,
    required String deviceId,
    required String messageToken,
    required String messageProvider,
    String? voipToken,
    required String platform,
    required String appVersion,
    String? bearerToken,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final requestId = _requestId('register');
    final trimmedAppVersion = appVersion.trim();
    final trimmedVoipToken = (voipToken ?? '').trim();
    final payloadToSign =
        '$requestId|$userId|$deviceId|$messageToken|$messageProvider|'
        '$trimmedVoipToken|$platform|$trimmedAppVersion|$ts';
    final sig = await _sign(identity, payloadToSign);
    final signingPub = base64Encode(identity.signingPublicKey.bytes);
    await _postJson(baseUri, '/devices/register', <String, dynamic>{
      'id': requestId,
      'from': userId,
      'ts': ts,
      'sig': sig,
      'signingPub': signingPub,
      'userId': userId,
      'deviceId': deviceId,
      'messageToken': messageToken,
      'messageProvider': messageProvider,
      if (trimmedVoipToken.isNotEmpty) 'voipToken': trimmedVoipToken,
      'platform': platform,
      'appVersion': trimmedAppVersion,
    }, bearerToken: bearerToken);
  }

  Future<void> unregisterDevice({
    required Uri baseUri,
    required IdentityService identity,
    required String userId,
    required String deviceId,
    required String token,
    String? bearerToken,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final requestId = _requestId('unregister');
    final payloadToSign = '$requestId|$userId|$deviceId|$token|$ts';
    final sig = await _sign(identity, payloadToSign);
    final signingPub = base64Encode(identity.signingPublicKey.bytes);
    await _postJson(baseUri, '/devices/unregister', <String, dynamic>{
      'id': requestId,
      'from': userId,
      'ts': ts,
      'sig': sig,
      'signingPub': signingPub,
      'userId': userId,
      'deviceId': deviceId,
      'token': token,
    }, bearerToken: bearerToken);
  }

  Future<void> sendPushEvent({
    required Uri baseUri,
    required IdentityService identity,
    required String senderUserId,
    required List<String> recipientUserIds,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? notification,
    PushDeliveryOptions delivery = const PushDeliveryOptions(),
    String? bearerToken,
  }) async {
    final normalizedSenderUserId = senderUserId.trim();
    if (normalizedSenderUserId.isEmpty) {
      return;
    }
    if (recipientUserIds.isEmpty) {
      return;
    }
    final normalizedRecipients =
        recipientUserIds
            .map((item) => item.trim())
            .where(
              (item) => item.isNotEmpty && item != normalizedSenderUserId,
            )
            .toSet()
            .toList(growable: false)
          ..sort();
    if (normalizedRecipients.isEmpty) {
      return;
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    final requestId = _requestId('push');
    final normalizedPayload = _normalizeJsonMap(payload);
    if (normalizedPayload.isEmpty) {
      return;
    }
    final transportPayload = _encodePushPayloadForTransport(normalizedPayload);
    if (transportPayload.isEmpty) {
      return;
    }
    final normalizedNotification = _normalizeNotification(notification);
    final sig = await _sign(
      identity,
      _pushEventSignaturePayload(
        requestId: requestId,
        senderUserId: normalizedSenderUserId,
        recipients: normalizedRecipients,
        payload: transportPayload,
        notification: normalizedNotification,
        delivery: delivery,
        ts: ts,
      ),
    );
    final signingPub = base64Encode(identity.signingPublicKey.bytes);
    final requestPayload = <String, dynamic>{
      'id': requestId,
      'from': normalizedSenderUserId,
      'ts': ts,
      'sig': sig,
      'signingPub': signingPub,
      'senderUserId': normalizedSenderUserId,
      'recipientUserIds': normalizedRecipients,
      'payload': transportPayload,
      'delivery': <String, dynamic>{
        'standard': delivery.standard,
        'voip': delivery.voip,
      },
      if (normalizedNotification?.isNotEmpty ?? false)
        'notification': normalizedNotification,
    };
    await _postJson(
      baseUri,
      '/events/push',
      requestPayload,
      bearerToken: bearerToken,
    );
  }

  String _pushEventSignaturePayload({
    required String requestId,
    required String senderUserId,
    required List<String> recipients,
    required Map<String, dynamic> payload,
    required Map<String, dynamic>? notification,
    required PushDeliveryOptions delivery,
    required int ts,
  }) {
    final recipientsPart = recipients.join(',');
    final payloadPart = jsonEncode(_sortJsonValue(payload));
    final notificationPart = jsonEncode(
      notification ?? const <String, dynamic>{},
    );
    return '$requestId|$senderUserId|$recipientsPart|$payloadPart|'
        '$notificationPart|${delivery.standard}|${delivery.voip}|$ts';
  }

  Future<void> _postJson(
    Uri baseUri,
    String path,
    Map<String, dynamic> payload, {
    String? bearerToken,
  }) async {
    if (!_allowedPaths.contains(path)) {
      throw ArgumentError.value(path, 'path', 'unsupported push endpoint');
    }
    final uri = baseUri.resolve(path);
    _logOutgoingPush(uri: uri, path: path, payload: payload);
    final client = HttpClient();
    if (uri.scheme.toLowerCase() == 'https') {
      client.badCertificateCallback = (cert, host, port) => host == uri.host;
    }
    try {
      final request = await client.postUrl(uri).timeout(_connectTimeout);
      request.headers.contentType = ContentType.json;
      final normalizedBearer = bearerToken?.trim();
      if (normalizedBearer != null && normalizedBearer.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $normalizedBearer',
        );
      }
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(_requestTimeout);
      final body = await utf8.decodeStream(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'push api status=${response.statusCode} path=$path body=${body.substring(0, body.length > 400 ? 400 : body.length)}',
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

  Map<String, dynamic> _normalizeJsonMap(Map<String, dynamic> input) {
    final normalized = <String, dynamic>{};
    input.forEach((key, value) {
      final trimmedKey = key.trim();
      if (trimmedKey.isEmpty || value == null) {
        return;
      }
      normalized[trimmedKey] = _normalizeJsonValue(value);
    });
    return Map<String, dynamic>.from(_sortJsonValue(normalized) as Map);
  }

  Map<String, dynamic>? _normalizeNotification(Map<String, dynamic>? input) {
    if (input == null) {
      return null;
    }
    final title = _normalizeShortString(input['title'], maxLength: 128);
    final body = _normalizeShortString(input['body'], maxLength: 512);
    if (title == null && body == null) {
      return null;
    }
    final normalized = <String, dynamic>{};
    if (title != null) {
      normalized['title'] = title;
    }
    if (body != null) {
      normalized['body'] = body;
    }
    return normalized;
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

  Map<String, dynamic> _encodePushPayloadForTransport(
    Map<String, dynamic> payload,
  ) {
    final encoded = <String, dynamic>{};
    payload.forEach((key, value) {
      final transportValue = _encodePushPayloadValueForTransport(value);
      if (transportValue == null) {
        return;
      }
      encoded[key] = transportValue;
    });
    return encoded;
  }

  dynamic _encodePushPayloadValueForTransport(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    if (value is num || value is bool) {
      return value.toString();
    }
    if (value is Map || value is List) {
      return jsonEncode(_sortJsonValue(value));
    }
    return value.toString();
  }

  dynamic _normalizeJsonValue(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      return _normalizeJsonMap(
        value.map(
          (key, item) => MapEntry(key.toString(), _normalizeJsonValue(item)),
        ),
      );
    }
    if (value is Iterable) {
      return value.map(_normalizeJsonValue).toList(growable: false);
    }
    if (value is num || value is bool || value is String) {
      return value;
    }
    if (value is TurnServerConfig) {
      return _normalizeJsonValue(value.toJson());
    }
    return value.toString();
  }

  dynamic _sortJsonValue(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((item) => item.toString()).toList()..sort();
      final sorted = <String, dynamic>{};
      for (final key in keys) {
        sorted[key] = _sortJsonValue(value[key]);
      }
      return sorted;
    }
    if (value is List) {
      return value.map(_sortJsonValue).toList(growable: false);
    }
    return value;
  }

  String _requestId(String prefix) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = now.toRadixString(16).substring(0, 8);
    return 'push:$prefix:$now:$random';
  }

  void _logOutgoingPush({
    required Uri uri,
    required String path,
    required Map<String, dynamic> payload,
  }) {
    final safePayload = Map<String, dynamic>.from(payload);
    if (safePayload.containsKey('sig')) {
      safePayload['sig'] = '<redacted>';
    }
    if (safePayload.containsKey('signingPub')) {
      safePayload['signingPub'] = '<redacted>';
    }
    final encoded = jsonEncode(safePayload);
    final truncated = encoded.length > 4000
        ? '${encoded.substring(0, 4000)}...(truncated)'
        : encoded;
    developer.log(
      '[push][outgoing] path=$path url=${uri.toString()} payload=$truncated',
      name: 'PushApiClient',
    );
    AppFileLogger.log(
      '[push][outgoing] path=$path url=${uri.toString()} payload=$truncated',
      name: 'PushApiClient',
    );
  }
}
