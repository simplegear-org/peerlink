import '../security/account_identity.dart';

const String accountMembershipUpdatesStorageKey =
    'account_membership_updates.v1';

class AccountMembershipUpdatePayload {
  static const String type = 'peerlink_account_membership_update';
  static const int version = 1;
  static const String revokeDevicesAction = 'revokeDevices';
  static const String addDevicesAction = 'addDevices';

  final String updateId;
  final String accountId;
  final String actorDeviceId;
  final String action;
  final List<String> affectedDeviceIds;
  final AccountIdentity accountIdentity;
  final int updatedAtMs;
  final String signature;

  const AccountMembershipUpdatePayload({
    required this.updateId,
    required this.accountId,
    required this.actorDeviceId,
    required this.action,
    required this.affectedDeviceIds,
    required this.accountIdentity,
    required this.updatedAtMs,
    required this.signature,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'updateId': updateId,
      'accountId': accountId,
      'actorDeviceId': actorDeviceId,
      'action': action,
      'affectedDeviceIds': affectedDeviceIds,
      'accountIdentity': accountIdentity.toJson(),
      'updatedAtMs': updatedAtMs,
      'signature': signature,
    };
  }

  factory AccountMembershipUpdatePayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не account membership update PeerLink');
    }
    if (json['version'] != version) {
      throw const FormatException(
        'Неподдерживаемая версия account membership update',
      );
    }
    final rawAccountIdentity = json['accountIdentity'];
    if (rawAccountIdentity is! Map) {
      throw const FormatException(
        'В account membership update нет accountIdentity',
      );
    }
    final rawAffectedDeviceIds = json['affectedDeviceIds'];
    return AccountMembershipUpdatePayload(
      updateId: json['updateId']?.toString().trim() ?? '',
      accountId: json['accountId']?.toString().trim() ?? '',
      actorDeviceId: json['actorDeviceId']?.toString().trim() ?? '',
      action: json['action']?.toString().trim() ?? '',
      affectedDeviceIds: rawAffectedDeviceIds is List
          ? rawAffectedDeviceIds
                .map((item) => item.toString().trim())
                .where((item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
      accountIdentity: AccountIdentity.fromJson(
        Map<String, dynamic>.from(rawAccountIdentity),
      ),
      updatedAtMs: int.tryParse(json['updatedAtMs']?.toString() ?? '') ?? 0,
      signature: json['signature']?.toString().trim() ?? '',
    );
  }
}
