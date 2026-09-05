import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/account_pairing_payload.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/core/security/account_identity.dart';
import 'package:peerlink/core/turn/turn_server_config.dart';

void main() {
  test(
    'AccountPairingPayload preserves session metadata and server config',
    () {
      const turnServer = TurnServerConfig(
        url: 'turn:example.org:3478?transport=tcp',
        username: 'user',
        password: 'secret',
        priority: 42,
      );
      final payload = AccountPairingPayload(
        sessionId: 'session-1',
        accountId: 'account-1',
        displayName: 'Alice',
        targetDeviceId: 'device-1',
        targetPeerId: 'peer-1',
        targetSigningPublicKey: 'signing-1',
        serverConfig: const ServerConfigPayload(
          bootstrap: <String>['wss://signal.example.org'],
          relay: <String>['https://relay.example.org'],
          turn: <TurnServerConfig>[turnServer],
          push: <String>['https://push.example.org:445'],
        ),
        createdAtMs: 100,
        expiresAtMs: 200,
      );

      final restored = AccountPairingPayload.fromJson(payload.toJson());

      expect(restored.sessionId, 'session-1');
      expect(restored.accountId, 'account-1');
      expect(restored.displayName, 'Alice');
      expect(restored.targetDeviceId, 'device-1');
      expect(restored.targetPeerId, 'peer-1');
      expect(restored.targetSigningPublicKey, 'signing-1');
      expect(restored.serverConfig.bootstrap, const <String>[
        'wss://signal.example.org',
      ]);
      expect(restored.serverConfig.relay, const <String>[
        'https://relay.example.org',
      ]);
      expect(restored.serverConfig.turn.single.url, turnServer.url);
      expect(restored.serverConfig.turn.single.username, turnServer.username);
      expect(restored.serverConfig.turn.single.password, turnServer.password);
      expect(restored.serverConfig.turn.single.priority, turnServer.priority);
      expect(restored.serverConfig.push, const <String>[
        'https://push.example.org:445',
      ]);
      expect(restored.createdAtMs, 100);
      expect(restored.expiresAtMs, 200);
    },
  );

  test('AccountPairingPayload allows empty server config', () {
    final restored = AccountPairingPayload.fromJson(<String, dynamic>{
      'type': AccountPairingPayload.type,
      'version': AccountPairingPayload.version,
      'sessionId': 'session-1',
      'accountId': 'account-1',
      'displayName': 'Alice',
      'targetDeviceId': 'device-1',
      'targetPeerId': 'peer-1',
      'createdAtMs': 100,
      'expiresAtMs': 200,
    });

    expect(restored.serverConfig.bootstrap, isEmpty);
    expect(restored.serverConfig.relay, isEmpty);
    expect(restored.serverConfig.turn, isEmpty);
    expect(restored.serverConfig.push, isEmpty);
  });

  test('AccountPairingApprovalPayload preserves account identity snapshot', () {
    final approval = AccountPairingApprovalPayload(
      requestId: 'pair:1',
      sessionId: 'session-1',
      accountIdentity: AccountIdentity(
        accountId: 'account-1',
        displayName: 'Alice',
        devices: <AccountDeviceIdentity>[
          AccountDeviceIdentity(
            deviceId: 'device-1',
            peerId: 'device-1',
            approvedByDeviceId: 'device-owner',
            approvedAtMs: 123,
            enrollmentSessionId: 'session-1',
            membershipSignature: 'sig',
            createdAtMs: 10,
            updatedAtMs: 20,
          ),
        ],
      ),
      serverConfig: const ServerConfigPayload(
        bootstrap: <String>['wss://signal.example.org'],
        relay: <String>['https://relay.example.org'],
        turn: <TurnServerConfig>[],
        push: <String>['https://push.example.org:445'],
      ),
      approvedAtMs: 300,
    );

    final restored = AccountPairingApprovalPayload.fromJson(approval.toJson());

    expect(restored.requestId, 'pair:1');
    expect(restored.sessionId, 'session-1');
    expect(restored.accountIdentity.accountId, 'account-1');
    expect(restored.accountIdentity.devices.single.membershipSignature, 'sig');
    expect(restored.serverConfig.bootstrap, const <String>[
      'wss://signal.example.org',
    ]);
  });

  test('PendingAccountPairingRequest preserves payload and timestamp', () {
    final pending = PendingAccountPairingRequest(
      payload: const AccountPairingPayload(
        sessionId: 'session-2',
        accountId: 'account-2',
        displayName: 'Alice',
        targetDeviceId: 'device-2',
        targetPeerId: 'peer-2',
        targetSigningPublicKey: 'signing-2',
        serverConfig: ServerConfigPayload(
          bootstrap: <String>['wss://signal.example.org'],
          relay: <String>['https://relay.example.org'],
          turn: <TurnServerConfig>[],
          push: <String>['https://push.example.org:445'],
        ),
        createdAtMs: 200,
        expiresAtMs: 300,
      ),
      scannedAtMs: 400,
    );

    final restored = PendingAccountPairingRequest.fromJson(pending.toJson());

    expect(restored.payload.accountId, 'account-2');
    expect(restored.payload.serverConfig.bootstrap, const <String>[
      'wss://signal.example.org',
    ]);
    expect(restored.scannedAtMs, 400);
  });
}
