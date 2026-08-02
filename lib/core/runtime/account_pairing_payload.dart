import '../security/account_identity.dart';
import 'server_config_payload.dart';

const String accountPairingIncomingRequestsStorageKey =
    'account_pairing_incoming_requests.v1';
const String accountPairingOutgoingRequestStorageKey =
    'account_pairing_outgoing_request.v1';
const String accountPairingApprovedPayloadStorageKey =
    'account_pairing_approved_payload.v1';
const String accountPairingRejectedPayloadStorageKey =
    'account_pairing_rejected_payload.v1';
const String accountPairingStagedServerConfigStorageKey =
    'account_pairing_staged_server_config.v1';
const String accountPairingActiveSessionsStorageKey =
    'account_pairing_active_sessions.v1';

class AccountPairingPayload {
  static const String type = 'peerlink_account_pairing';
  static const int version = 2;

  final String sessionId;
  final String accountId;
  final String displayName;
  final String targetDeviceId;
  final String targetPeerId;
  final String? targetSigningPublicKey;
  final ServerConfigPayload serverConfig;
  final int createdAtMs;
  final int expiresAtMs;

  const AccountPairingPayload({
    required this.sessionId,
    required this.accountId,
    required this.displayName,
    required this.targetDeviceId,
    required this.targetPeerId,
    required this.targetSigningPublicKey,
    required this.serverConfig,
    required this.createdAtMs,
    required this.expiresAtMs,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'sessionId': sessionId,
      'accountId': accountId,
      'displayName': displayName,
      'targetDeviceId': targetDeviceId,
      'targetPeerId': targetPeerId,
      if (targetSigningPublicKey != null)
        'targetSigningPublicKey': targetSigningPublicKey,
      'servers': serverConfig.toJson(),
      'createdAtMs': createdAtMs,
      'expiresAtMs': expiresAtMs,
    };
  }

  factory AccountPairingPayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не QR привязки устройства PeerLink');
    }
    if (json['version'] != version) {
      throw const FormatException('Неподдерживаемая версия привязки');
    }

    final servers = json['servers'];
    final serverConfig = ServerConfigPayload.fromJson(
      servers is Map
          ? Map<String, dynamic>.from(servers)
          : <String, dynamic>{
              'type': ServerConfigPayload.type,
              'version': ServerConfigPayload.version,
              'bootstrap': const <String>[],
              'relay': const <String>[],
              'turn': const <Map<String, dynamic>>[],
            },
    );

    return AccountPairingPayload(
      sessionId: json['sessionId']?.toString().trim() ?? '',
      accountId: json['accountId']?.toString().trim() ?? '',
      displayName: json['displayName']?.toString().trim() ?? '',
      targetDeviceId: json['targetDeviceId']?.toString().trim() ?? '',
      targetPeerId: json['targetPeerId']?.toString().trim() ?? '',
      targetSigningPublicKey: _nullableTrimmed(json['targetSigningPublicKey']),
      serverConfig: serverConfig,
      createdAtMs: int.tryParse(json['createdAtMs']?.toString() ?? '') ?? 0,
      expiresAtMs: int.tryParse(json['expiresAtMs']?.toString() ?? '') ?? 0,
    );
  }

  bool get isExpired =>
      expiresAtMs > 0 && DateTime.now().millisecondsSinceEpoch > expiresAtMs;
}

class AccountPairingRequestPayload {
  static const String type = 'peerlink_account_pair_request';
  static const int version = 2;

  final String requestId;
  final String sessionId;
  final String targetAccountId;
  final String targetDeviceId;
  final String requesterPeerId;
  final String requesterAccountId;
  final String requesterDeviceId;
  final String requesterDisplayName;
  final String requesterSigningPublicKey;
  final String requesterAgreementPublicKey;
  final String? requesterEndpointId;
  final String? requesterFcmTokenHash;
  final int requestedAtMs;

  const AccountPairingRequestPayload({
    required this.requestId,
    required this.sessionId,
    required this.targetAccountId,
    required this.targetDeviceId,
    required this.requesterPeerId,
    required this.requesterAccountId,
    required this.requesterDeviceId,
    required this.requesterDisplayName,
    required this.requesterSigningPublicKey,
    required this.requesterAgreementPublicKey,
    required this.requesterEndpointId,
    required this.requesterFcmTokenHash,
    required this.requestedAtMs,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'requestId': requestId,
      'sessionId': sessionId,
      'targetAccountId': targetAccountId,
      'targetDeviceId': targetDeviceId,
      'requesterPeerId': requesterPeerId,
      'requesterAccountId': requesterAccountId,
      'requesterDeviceId': requesterDeviceId,
      'requesterDisplayName': requesterDisplayName,
      'requesterSigningPublicKey': requesterSigningPublicKey,
      'requesterAgreementPublicKey': requesterAgreementPublicKey,
      if (requesterEndpointId != null)
        'requesterEndpointId': requesterEndpointId,
      if (requesterFcmTokenHash != null)
        'requesterFcmTokenHash': requesterFcmTokenHash,
      'requestedAtMs': requestedAtMs,
    };
  }

  factory AccountPairingRequestPayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не pairing request PeerLink');
    }
    if (json['version'] != version) {
      throw const FormatException('Неподдерживаемая версия pairing request');
    }
    return AccountPairingRequestPayload(
      requestId: json['requestId']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      targetAccountId: json['targetAccountId']?.toString() ?? '',
      targetDeviceId: json['targetDeviceId']?.toString() ?? '',
      requesterPeerId: json['requesterPeerId']?.toString() ?? '',
      requesterAccountId: json['requesterAccountId']?.toString() ?? '',
      requesterDeviceId: json['requesterDeviceId']?.toString() ?? '',
      requesterDisplayName: json['requesterDisplayName']?.toString() ?? '',
      requesterSigningPublicKey:
          json['requesterSigningPublicKey']?.toString() ?? '',
      requesterAgreementPublicKey:
          json['requesterAgreementPublicKey']?.toString() ?? '',
      requesterEndpointId: _nullableTrimmed(json['requesterEndpointId']),
      requesterFcmTokenHash: _nullableTrimmed(json['requesterFcmTokenHash']),
      requestedAtMs: int.tryParse(json['requestedAtMs']?.toString() ?? '') ?? 0,
    );
  }
}

class AccountPairingApprovalPayload {
  static const String type = 'peerlink_account_pair_approval';
  static const int version = 2;

  final String requestId;
  final String sessionId;
  final AccountIdentity accountIdentity;
  final ServerConfigPayload serverConfig;
  final int approvedAtMs;

  const AccountPairingApprovalPayload({
    required this.requestId,
    required this.sessionId,
    required this.accountIdentity,
    required this.serverConfig,
    required this.approvedAtMs,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'requestId': requestId,
      'sessionId': sessionId,
      'accountIdentity': accountIdentity.toJson(),
      'servers': serverConfig.toJson(),
      'approvedAtMs': approvedAtMs,
    };
  }

  factory AccountPairingApprovalPayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не pairing approval PeerLink');
    }
    if (json['version'] != version) {
      throw const FormatException('Неподдерживаемая версия pairing approval');
    }
    final rawAccount = json['accountIdentity'];
    if (rawAccount is! Map) {
      throw const FormatException('В pairing approval нет accountIdentity');
    }
    final rawServers = json['servers'];
    return AccountPairingApprovalPayload(
      requestId: json['requestId']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      accountIdentity: AccountIdentity.fromJson(
        Map<String, dynamic>.from(rawAccount),
      ),
      serverConfig: ServerConfigPayload.fromJson(
        rawServers is Map
            ? Map<String, dynamic>.from(rawServers)
            : <String, dynamic>{
                'type': ServerConfigPayload.type,
                'version': ServerConfigPayload.version,
                'bootstrap': const <String>[],
                'relay': const <String>[],
                'turn': const <Map<String, dynamic>>[],
              },
      ),
      approvedAtMs: int.tryParse(json['approvedAtMs']?.toString() ?? '') ?? 0,
    );
  }
}

class AccountPairingRejectedPayload {
  static const String type = 'peerlink_account_pair_rejection';
  static const int version = 2;

  final String requestId;
  final String sessionId;
  final int rejectedAtMs;

  const AccountPairingRejectedPayload({
    required this.requestId,
    required this.sessionId,
    required this.rejectedAtMs,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'requestId': requestId,
      'sessionId': sessionId,
      'rejectedAtMs': rejectedAtMs,
    };
  }

  factory AccountPairingRejectedPayload.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не pairing rejection PeerLink');
    }
    if (json['version'] != version) {
      throw const FormatException('Неподдерживаемая версия pairing rejection');
    }
    return AccountPairingRejectedPayload(
      requestId: json['requestId']?.toString() ?? '',
      sessionId: json['sessionId']?.toString() ?? '',
      rejectedAtMs: int.tryParse(json['rejectedAtMs']?.toString() ?? '') ?? 0,
    );
  }
}

class AccountPairingStagedServerConfig {
  static const String type = 'peerlink_account_pair_staged_servers';
  static const int version = 1;

  final ServerConfigPayload previousServerConfig;
  final ServerConfigPayload stagedServerConfig;
  final int stagedAtMs;

  const AccountPairingStagedServerConfig({
    required this.previousServerConfig,
    required this.stagedServerConfig,
    required this.stagedAtMs,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'previousServerConfig': previousServerConfig.toJson(),
      'stagedServerConfig': stagedServerConfig.toJson(),
      'stagedAtMs': stagedAtMs,
    };
  }

  factory AccountPairingStagedServerConfig.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException(
        'Это не временная server-конфигурация pairing',
      );
    }
    if (json['version'] != version) {
      throw const FormatException(
        'Неподдерживаемая версия временной server-конфигурации pairing',
      );
    }
    final previous = json['previousServerConfig'];
    final staged = json['stagedServerConfig'];
    if (previous is! Map || staged is! Map) {
      throw const FormatException(
        'В временной server-конфигурации pairing нет server payload',
      );
    }
    return AccountPairingStagedServerConfig(
      previousServerConfig: ServerConfigPayload.fromJson(
        Map<String, dynamic>.from(previous),
      ),
      stagedServerConfig: ServerConfigPayload.fromJson(
        Map<String, dynamic>.from(staged),
      ),
      stagedAtMs: int.tryParse(json['stagedAtMs']?.toString() ?? '') ?? 0,
    );
  }
}

class PendingAccountPairingRequest {
  static const String type = 'peerlink_pending_account_pairing';
  static const int version = 1;

  final AccountPairingPayload payload;
  final int scannedAtMs;

  const PendingAccountPairingRequest({
    required this.payload,
    required this.scannedAtMs,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'type': type,
      'version': version,
      'payload': payload.toJson(),
      'scannedAtMs': scannedAtMs,
    };
  }

  factory PendingAccountPairingRequest.fromJson(Map<String, dynamic> json) {
    if (json['type'] != type) {
      throw const FormatException('Это не pending-привязка устройства');
    }
    if (json['version'] != version) {
      throw const FormatException('Неподдерживаемая версия pending-привязки');
    }

    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('В pending-привязке нет payload');
    }

    return PendingAccountPairingRequest(
      payload: AccountPairingPayload.fromJson(
        Map<String, dynamic>.from(rawPayload),
      ),
      scannedAtMs: int.tryParse(json['scannedAtMs']?.toString() ?? '') ?? 0,
    );
  }
}

String? _nullableTrimmed(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
