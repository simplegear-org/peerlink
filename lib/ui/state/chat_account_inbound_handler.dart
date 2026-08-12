import 'dart:convert';

import '../../core/messaging/chat_service.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/storage_service.dart';

class ChatAccountInboundHandler {
  const ChatAccountInboundHandler({
    required NodeFacade facade,
    required SecureStorageBox settingsBox,
  }) : _facade = facade,
       _settingsBox = settingsBox;

  final NodeFacade _facade;
  final SecureStorageBox _settingsBox;

  Future<void> handlePairRequest(
    ChatMessage msg,
    AccountPairingRequestPayload payload,
  ) async {
    final current = _readIncomingAccountPairingRequests();
    final entry = <String, dynamic>{
      'payload': payload.toJson(),
      'sourcePeerId': msg.peerId,
    };
    final updated =
        current
            .where(
              (item) =>
                  (item['payload'] is! Map) ||
                  Map<String, dynamic>.from(
                        item['payload'] as Map,
                      )['requestId'] !=
                      payload.requestId,
            )
            .toList(growable: true)
          ..add(entry);
    await _settingsBox.put(
      accountPairingIncomingRequestsStorageKey,
      jsonEncode(updated),
    );
    AppFileLogger.log(
      'incoming account pairing request requestId=${payload.requestId} source=${msg.peerId}',
      name: 'chat_pairing',
    );
  }

  Future<void> handlePairApproval(
    ChatMessage msg,
    AccountPairingApprovalPayload payload,
  ) async {
    final outgoing = _readOutgoingPairingRequest();
    if (outgoing == null || outgoing.requestId != payload.requestId) {
      return;
    }
    await _settingsBox.put(
      accountPairingApprovedPayloadStorageKey,
      jsonEncode(payload.toJson()),
    );
    AppFileLogger.log(
      'incoming account pairing approval requestId=${payload.requestId} source=${msg.peerId}',
      name: 'chat_pairing',
    );
  }

  Future<void> handlePairRejection(
    ChatMessage msg,
    AccountPairingRejectedPayload payload,
  ) async {
    final outgoing = _readOutgoingPairingRequest();
    if (outgoing == null || outgoing.requestId != payload.requestId) {
      return;
    }
    await _settingsBox.put(
      accountPairingRejectedPayloadStorageKey,
      jsonEncode(payload.toJson()),
    );
    AppFileLogger.log(
      'incoming account pairing rejection requestId=${payload.requestId} source=${msg.peerId}',
      name: 'chat_pairing',
    );
  }

  Future<void> handleMembershipUpdate(
    ChatMessage msg,
    AccountMembershipUpdatePayload payload,
  ) async {
    try {
      await _facade.applyAccountMembershipUpdate(
        incoming: payload.accountIdentity,
        actorDeviceId: payload.actorDeviceId,
        action: payload.action,
        affectedDeviceIds: payload.affectedDeviceIds,
        updatedAtMs: payload.updatedAtMs,
        signature: payload.signature,
      );
      AppFileLogger.log(
        'incoming account membership update applied updateId=${payload.updateId} source=${msg.peerId}',
        name: 'chat_pairing',
      );
      return;
    } catch (error, stackTrace) {
      AppFileLogger.log(
        'incoming account membership update deferred updateId=${payload.updateId} error=$error',
        name: 'chat_pairing',
        stackTrace: stackTrace,
      );
    }
    final current = _readIncomingAccountMembershipUpdates();
    final updated =
        current
            .where((item) => item['updateId']?.toString() != payload.updateId)
            .toList(growable: true)
          ..add(payload.toJson());
    await _settingsBox.put(
      accountMembershipUpdatesStorageKey,
      jsonEncode(updated),
    );
    AppFileLogger.log(
      'incoming account membership update updateId=${payload.updateId} source=${msg.peerId}',
      name: 'chat_pairing',
    );
  }

  AccountPairingRequestPayload? _readOutgoingPairingRequest() {
    final outgoingRaw = _settingsBox.get(
      accountPairingOutgoingRequestStorageKey,
    );
    if (outgoingRaw is! String || outgoingRaw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(outgoingRaw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingRequestPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> _readIncomingAccountPairingRequests() {
    final raw = _settingsBox.get(accountPairingIncomingRequestsStorageKey);
    if (raw is! String || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  List<Map<String, dynamic>> _readIncomingAccountMembershipUpdates() {
    final raw = _settingsBox.get(accountMembershipUpdatesStorageKey);
    if (raw is! String || raw.trim().isEmpty) {
      return <Map<String, dynamic>>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}
