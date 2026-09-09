import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/moderation/application/moderation_policy_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

void main() {
  late StorageService storage;
  late ModerationPolicyService service;

  setUp(() async {
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(
      rootDirectory: Directory.systemTemp.createTempSync(
        'peerlink-policy-test-',
      ),
    );
    service = ModerationPolicyService.forStorage(storage);
  });

  test('moderation policy push stores warning', () async {
    final snapshot = await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'warning',
      'message': 'Warning',
    });

    expect(snapshot, isNotNull);
    expect(snapshot!.isWarning, isTrue);
    expect(service.load().isWarning, isTrue);
  });

  test(
    'warning can be acknowledged until next warning payload changes',
    () async {
      final first = await service.applyPushPayload(<String, dynamic>{
        'type': 'moderation_policy',
        'policyState': 'warning',
        'messageKey': 'moderationWarningMessage',
        'reportCount': '3',
        'reporterCount': '2',
      });
      expect(first!.shouldShowWarningScreen, isTrue);

      final acknowledged = await service.markWarningAcknowledged();
      expect(acknowledged.shouldShowWarningScreen, isFalse);
      expect(service.load().shouldShowWarningScreen, isFalse);

      final repeated = await service.applyPushPayload(<String, dynamic>{
        'type': 'moderation_policy',
        'policyState': 'warning',
        'messageKey': 'moderationWarningMessage',
        'reportCount': '3',
        'reporterCount': '2',
      });
      expect(repeated!.shouldShowWarningScreen, isFalse);

      final changed = await service.applyPushPayload(<String, dynamic>{
        'type': 'moderation_policy',
        'policyState': 'warning',
        'messageKey': 'moderationWarningMessage',
        'reportCount': '4',
        'reporterCount': '3',
      });
      expect(changed!.shouldShowWarningScreen, isTrue);
    },
  );

  test('moderation policy push persists banned state', () async {
    await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'message': 'Blocked',
      'messageKey': 'moderationBanMessage',
      'reportCount': '7',
      'reporterCount': '3',
    });

    final reloaded = ModerationPolicyService.forStorage(storage).load();
    expect(reloaded.isBanned, isTrue);
    expect(reloaded.message, 'Blocked');
    expect(reloaded.messageKey, 'moderationBanMessage');
    expect(reloaded.reportCount, 7);
    expect(reloaded.reporterCount, 3);
    expect(reloaded.signedStatus, isNull);
  });

  test('signed moderation status is verified against trusted key', () async {
    final keys = await Ed25519().newKeyPair();
    final publicKey = await keys.extractPublicKey();
    final signedStatus = await _signedStatus(
      keys,
      peerId: 'peer-1',
      policyState: 'banned',
      reportCount: 7,
    );
    final verifiedService = ModerationPolicyService(
      settingsBox: storage.getSettings(),
      trustedSigningPublicKey: base64Encode(publicKey.bytes),
    );

    final snapshot = await verifiedService.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'reportCount': '7',
      'reporterCount': '3',
      'signedStatus': signedStatus,
    }, expectedPeerId: 'peer-1');

    expect(snapshot, isNotNull);
    expect(snapshot!.isBanned, isTrue);
  });

  test(
    'fake moderation status is rejected when trusted key is pinned',
    () async {
      final trustedKeys = await Ed25519().newKeyPair();
      final trustedPublicKey = await trustedKeys.extractPublicKey();
      final attackerKeys = await Ed25519().newKeyPair();
      final signedStatus = await _signedStatus(
        attackerKeys,
        peerId: 'peer-1',
        policyState: 'banned',
        reportCount: 7,
      );
      final verifiedService = ModerationPolicyService(
        settingsBox: storage.getSettings(),
        trustedSigningPublicKey: base64Encode(trustedPublicKey.bytes),
      );

      final snapshot = await verifiedService.applyPushPayload(<String, dynamic>{
        'type': 'moderation_policy',
        'policyState': 'banned',
        'reportCount': '7',
        'reporterCount': '3',
        'signedStatus': signedStatus,
      }, expectedPeerId: 'peer-1');

      expect(snapshot, isNull);
      expect(verifiedService.load().state, ModerationPolicyState.clear);
    },
  );

  test(
    'unsigned moderation status is rejected when trusted key is pinned',
    () async {
      final trustedKeys = await Ed25519().newKeyPair();
      final trustedPublicKey = await trustedKeys.extractPublicKey();
      final verifiedService = ModerationPolicyService(
        settingsBox: storage.getSettings(),
        trustedSigningPublicKey: base64Encode(trustedPublicKey.bytes),
      );

      final snapshot = await verifiedService.applyPushPayload(<String, dynamic>{
        'type': 'moderation_policy',
        'policyState': 'banned',
        'reportCount': '7',
        'reporterCount': '3',
      }, expectedPeerId: 'peer-1');

      expect(snapshot, isNull);
      expect(verifiedService.load().state, ModerationPolicyState.clear);
    },
  );

  test('signed moderation status for another peer is rejected', () async {
    final keys = await Ed25519().newKeyPair();
    final publicKey = await keys.extractPublicKey();
    final signedStatus = await _signedStatus(
      keys,
      peerId: 'other-peer',
      policyState: 'warning',
      reportCount: 4,
    );
    final verifiedService = ModerationPolicyService(
      settingsBox: storage.getSettings(),
      trustedSigningPublicKey: base64Encode(publicKey.bytes),
    );

    final snapshot = await verifiedService.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'warning',
      'reportCount': '4',
      'reporterCount': '2',
      'signedStatus': signedStatus,
    }, expectedPeerId: 'peer-1');

    expect(snapshot, isNull);
    expect(verifiedService.load().state, ModerationPolicyState.clear);
  });

  test(
    'appeal hides restriction screen but keeps communication blocked',
    () async {
      await service.applyPushPayload(<String, dynamic>{
        'type': 'moderation_policy',
        'policyState': 'banned',
        'action': 'ban',
      });

      final appealed = await service.markAppealSubmitted();

      expect(appealed.isBanned, isTrue);
      expect(appealed.shouldShowRestrictionScreen, isFalse);
      expect(appealed.restrictsOutgoingCommunication, isTrue);
    },
  );

  test('submitted appeal survives restart and status refresh', () async {
    await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'action': 'ban',
      'messageKey': 'moderationBanMessage',
      'reportCount': '7',
      'reporterCount': '3',
    });
    await service.markAppealSubmitted();

    final reloaded = ModerationPolicyService.forStorage(storage);
    expect(reloaded.load().shouldShowRestrictionScreen, isFalse);

    final refreshed = await reloaded.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'action': 'ban',
      'messageKey': 'moderationBanMessage',
      'reportCount': '7',
      'reporterCount': '3',
    });

    expect(refreshed!.isBanned, isTrue);
    expect(refreshed.shouldShowRestrictionScreen, isFalse);
  });

  test('acknowledged warning survives restart and status refresh', () async {
    await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'warning',
      'messageKey': 'moderationWarningMessage',
      'reportCount': '3',
      'reporterCount': '2',
    });
    await service.markWarningAcknowledged();

    final reloaded = ModerationPolicyService.forStorage(storage);
    expect(reloaded.load().shouldShowWarningScreen, isFalse);

    final refreshed = await reloaded.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'warning',
      'messageKey': 'moderationWarningMessage',
      'reportCount': '3',
      'reporterCount': '2',
    });

    expect(refreshed!.isWarning, isTrue);
    expect(refreshed.shouldShowWarningScreen, isFalse);
  });

  test('new ban resets submitted appeal gate', () async {
    await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'action': 'ban',
      'reportCount': '1',
      'reporterCount': '1',
    });
    await service.markAppealSubmitted();

    final snapshot = await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'action': 'ban',
      'reportCount': '2',
      'reporterCount': '2',
    });

    expect(snapshot!.appealSubmitted, isFalse);
    expect(snapshot.shouldShowRestrictionScreen, isTrue);
  });

  test('unban clears persisted ban', () async {
    await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'banned',
      'action': 'ban',
    });
    await service.markAppealSubmitted();

    final snapshot = await service.applyPushPayload(<String, dynamic>{
      'type': 'moderation_policy',
      'policyState': 'clear',
      'action': 'unban',
      'messageKey': 'moderationUnbanMessage',
    });

    expect(snapshot!.state, ModerationPolicyState.clear);
    expect(snapshot.isBanned, isFalse);
    expect(service.load().isBanned, isFalse);
  });

  test('non moderation push is ignored', () async {
    final snapshot = await service.applyPushPayload(<String, dynamic>{
      'type': 'message',
      'policyState': 'banned',
    });

    expect(snapshot, isNull);
    expect(service.load().state, ModerationPolicyState.clear);
  });
}

Future<Map<String, dynamic>> _signedStatus(
  SimpleKeyPair keyPair, {
  required String peerId,
  required String policyState,
  required int reportCount,
}) async {
  const schema = 'peerlink_moderation_status_v1';
  final publicKey = await keyPair.extractPublicKey();
  final issuedAt = DateTime.utc(2026, 8, 27, 12).toIso8601String();
  final payload = <String>[
    schema,
    peerId,
    policyState,
    reportCount.toString(),
    '',
    '',
    issuedAt,
  ].join('|');
  final signature = await Ed25519().sign(
    utf8.encode(payload),
    keyPair: keyPair,
  );
  return <String, dynamic>{
    'schema': schema,
    'peerId': peerId,
    'policyState': policyState,
    'reportCount': reportCount,
    'warningIssuedAt': null,
    'bannedAt': null,
    'issuedAt': issuedAt,
    'signingPub': base64Encode(publicKey.bytes),
    'sig': base64Encode(signature.bytes),
  };
}
