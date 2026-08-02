import '../../core/runtime/account_pairing_payload.dart';
import '../../core/runtime/server_config_payload.dart';

enum ServerConfigImportMode { replace, merge }

enum SettingsServerState { connected, connecting, unavailable, paused }

class ServerConfigImportPreview {
  final int bootstrapTotal;
  final int relayTotal;
  final int turnTotal;
  final int pushTotal;
  final int bootstrapNew;
  final int relayNew;
  final int turnNew;
  final int pushNew;

  const ServerConfigImportPreview({
    required this.bootstrapTotal,
    required this.relayTotal,
    required this.turnTotal,
    required this.pushTotal,
    required this.bootstrapNew,
    required this.relayNew,
    required this.turnNew,
    required this.pushNew,
  });
}

class IncomingAccountPairingRequest {
  final AccountPairingRequestPayload payload;
  final String sourcePeerId;

  const IncomingAccountPairingRequest({
    required this.payload,
    required this.sourcePeerId,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'payload': payload.toJson(),
      'sourcePeerId': sourcePeerId,
    };
  }

  factory IncomingAccountPairingRequest.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    if (rawPayload is! Map) {
      throw const FormatException('Входящий pairing request поврежден');
    }
    return IncomingAccountPairingRequest(
      payload: AccountPairingRequestPayload.fromJson(
        Map<String, dynamic>.from(rawPayload),
      ),
      sourcePeerId: json['sourcePeerId']?.toString() ?? '',
    );
  }
}

class PeerLinkInviteImport {
  final String peerId;
  final String? displayName;
  final ServerConfigPayload serverConfig;

  const PeerLinkInviteImport({
    required this.peerId,
    required this.serverConfig,
    this.displayName,
  });
}
