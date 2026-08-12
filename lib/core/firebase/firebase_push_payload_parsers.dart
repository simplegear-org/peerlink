import 'dart:convert';

import '../runtime/account_membership_update_payload.dart';
import 'firebase_push_payload.dart';

class FirebasePushGroupMembersPayload {
  final Map<String, dynamic> payload;
  final String? sourcePeerId;

  const FirebasePushGroupMembersPayload({
    required this.payload,
    required this.sourcePeerId,
  });
}

class FirebasePushAccountMembershipPayloadParser {
  const FirebasePushAccountMembershipPayloadParser();

  AccountMembershipUpdatePayload? parse(Map<String, dynamic> data) {
    final payload = FirebasePushPayload.fromMap(data);
    if (!payload.isAccountMembershipUpdate) {
      return null;
    }
    final raw = payload.rawAccountMembershipUpdate;
    final map = _decodeMap(raw);
    if (map == null) {
      return null;
    }
    try {
      return AccountMembershipUpdatePayload.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}

class FirebasePushGroupMembersPayloadParser {
  const FirebasePushGroupMembersPayloadParser();

  FirebasePushGroupMembersPayload? parse(Map<String, dynamic> data) {
    final pushPayload = FirebasePushPayload.fromMap(data);
    if (!pushPayload.isGroupMembersUpdate) {
      return null;
    }
    final payload = _decodeMap(pushPayload.rawGroupMembers);
    if (payload == null) {
      return null;
    }
    final sourcePeerId = (payload['senderPeerId'] as String?)?.trim();
    return FirebasePushGroupMembersPayload(
      payload: payload,
      sourcePeerId: sourcePeerId,
    );
  }
}

Map<String, dynamic>? _decodeMap(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}
