import 'dart:convert';

import '../../core/runtime/server_config_payload.dart';
import 'qr_payload_encoder.dart';
import 'settings_controller_models.dart';
import 'settings_deep_link_codec.dart';

class SettingsInviteCodec {
  const SettingsInviteCodec._();

  static const String invitePayloadType = 'peerlink_invite';
  static const int invitePayloadVersion = 1;

  static String exportInvitePayload({
    required String peerId,
    required String? endpointId,
    required String? fcmTokenHash,
    required ServerConfigPayload serverConfig,
  }) {
    return jsonEncode(<String, dynamic>{
      'type': invitePayloadType,
      'version': invitePayloadVersion,
      'peer': <String, dynamic>{
        'peerId': peerId,
        'stableUserId': peerId,
        'endpointId': endpointId,
        'fcmTokenHash': fcmTokenHash,
      },
      'servers': serverConfig.toJson(),
      'createdAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static String exportInviteDeepLink(String payloadJson) {
    return QrPayloadEncoder.buildDeepLink(
      scheme: 'peerlink',
      host: 'invite',
      payload: QrPayloadEncoder.encodeToBase64Url(payloadJson),
    );
  }

  static String exportInviteShareLink(String payloadJson, String baseUrl) {
    final baseUri = Uri.parse(baseUrl);
    return baseUri
        .replace(
          queryParameters: <String, String>{
            ...baseUri.queryParameters,
            'payload': QrPayloadEncoder.encodeToBase64Url(payloadJson),
          },
        )
        .toString();
  }

  static PeerLinkInviteImport parseInviteDeepLink(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !SettingsDeepLinkCodec.isInviteUri(uri)) {
      throw const FormatException('Это не приглашение PeerLink');
    }
    final encodedPayload = SettingsDeepLinkCodec.payloadFromUri(uri);
    if (encodedPayload == null || encodedPayload.trim().isEmpty) {
      throw const FormatException('В приглашении нет payload');
    }
    final normalizedPayload = base64Url.normalize(encodedPayload.trim());
    final payloadJson = utf8.decode(base64Url.decode(normalizedPayload));
    return parseInvitePayload(payloadJson);
  }

  static PeerLinkInviteImport parseInvitePayload(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат приглашения PeerLink');
    }
    if (decoded['type'] != invitePayloadType ||
        decoded['version'] != invitePayloadVersion) {
      throw const FormatException('Неподдерживаемое приглашение PeerLink');
    }

    final peer = decoded['peer'];
    if (peer is! Map) {
      throw const FormatException('В приглашении нет peer');
    }
    final peerMap = Map<String, dynamic>.from(peer);
    final invitePeerId =
        peerMap['stableUserId']?.toString().trim().isNotEmpty == true
        ? peerMap['stableUserId'].toString().trim()
        : peerMap['peerId']?.toString().trim();
    if (invitePeerId == null || invitePeerId.isEmpty) {
      throw const FormatException('В приглашении нет Peer ID');
    }

    final servers = decoded['servers'];
    final serverMap = servers is Map
        ? Map<String, dynamic>.from(servers)
        : <String, dynamic>{
            'type': ServerConfigPayload.type,
            'version': ServerConfigPayload.version,
            'bootstrap': const <String>[],
            'relay': const <String>[],
            'turn': const <Map<String, dynamic>>[],
          };
    final serverConfig = ServerConfigPayload.fromJson(serverMap);
    final displayName = peerMap['displayName']?.toString().trim();

    return PeerLinkInviteImport(
      peerId: invitePeerId,
      displayName: displayName?.isNotEmpty == true ? displayName : null,
      serverConfig: serverConfig,
    );
  }
}
