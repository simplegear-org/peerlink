import 'dart:convert';

import '../../core/messaging/chat_service.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';

class ChatAccountPayloadDecoder {
  const ChatAccountPayloadDecoder._();

  static AccountPairingRequestPayload? decodePairRequest(ChatMessage msg) {
    return _decode(
      msg,
      expectedKind: 'accountPairRequest',
      fromJson: AccountPairingRequestPayload.fromJson,
    );
  }

  static AccountPairingApprovalPayload? decodePairApproval(ChatMessage msg) {
    return _decode(
      msg,
      expectedKind: 'accountPairApproval',
      fromJson: AccountPairingApprovalPayload.fromJson,
    );
  }

  static AccountPairingRejectedPayload? decodePairRejection(ChatMessage msg) {
    return _decode(
      msg,
      expectedKind: 'accountPairRejection',
      fromJson: AccountPairingRejectedPayload.fromJson,
    );
  }

  static AccountMembershipUpdatePayload? decodeMembershipUpdate(
    ChatMessage msg,
  ) {
    return _decode(
      msg,
      expectedKind: 'accountMembershipUpdate',
      fromJson: AccountMembershipUpdatePayload.fromJson,
    );
  }

  static T? _decode<T>(
    ChatMessage msg, {
    required String expectedKind,
    required T Function(Map<String, dynamic> json) fromJson,
  }) {
    if (msg.kind != expectedKind || msg.text.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(msg.text);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}
