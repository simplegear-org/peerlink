import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'account_identity.dart';

class IdentityMembershipCrypto {
  final Ed25519 _algorithm;

  const IdentityMembershipCrypto({required Ed25519 algorithm})
    : _algorithm = algorithm;

  Future<String> createMembershipSignature({
    required String accountId,
    required AccountDeviceIdentity device,
    required String approvedByDeviceId,
    required int approvedAtMs,
    required String sessionId,
    required SimpleKeyPair signerKeyPair,
  }) async {
    final signature = await _algorithm.sign(
      membershipPayloadBytes(
        accountId: accountId,
        device: device,
        approvedByDeviceId: approvedByDeviceId,
        approvedAtMs: approvedAtMs,
        sessionId: sessionId,
      ),
      keyPair: signerKeyPair,
    );
    return base64Encode(signature.bytes);
  }

  Future<bool> verifyMembershipSignature({
    required String accountId,
    required AccountDeviceIdentity device,
    required String approvedByDeviceId,
    required int approvedAtMs,
    required String sessionId,
    required String membershipSignature,
    required String signerPublicKeyBase64,
  }) async {
    try {
      return _algorithm.verify(
        membershipPayloadBytes(
          accountId: accountId,
          device: device,
          approvedByDeviceId: approvedByDeviceId,
          approvedAtMs: approvedAtMs,
          sessionId: sessionId,
        ),
        signature: Signature(
          base64Decode(membershipSignature),
          publicKey: SimplePublicKey(
            base64Decode(signerPublicKeyBase64),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required SimpleKeyPair signerKeyPair,
  }) async {
    final signature = await _algorithm.sign(
      accountMembershipUpdatePayloadBytes(
        identity: identity,
        actorDeviceId: actorDeviceId,
        action: action,
        affectedDeviceIds: affectedDeviceIds,
        updatedAtMs: updatedAtMs,
      ),
      keyPair: signerKeyPair,
    );
    return base64Encode(signature.bytes);
  }

  Future<bool> verifyAccountMembershipUpdateSignature({
    required AccountIdentity identity,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
    required String signerPublicKeyBase64,
  }) async {
    try {
      return _algorithm.verify(
        accountMembershipUpdatePayloadBytes(
          identity: identity,
          actorDeviceId: actorDeviceId,
          action: action,
          affectedDeviceIds: affectedDeviceIds,
          updatedAtMs: updatedAtMs,
        ),
        signature: Signature(
          base64Decode(signature),
          publicKey: SimplePublicKey(
            base64Decode(signerPublicKeyBase64),
            type: KeyPairType.ed25519,
          ),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  List<int> membershipPayloadBytes({
    required String accountId,
    required AccountDeviceIdentity device,
    required String approvedByDeviceId,
    required int approvedAtMs,
    required String sessionId,
  }) {
    return utf8.encode(
      jsonEncode(<String, dynamic>{
        'v': 1,
        'type': 'peerlink_account_device_membership',
        'accountId': accountId.trim(),
        'deviceId': device.deviceId,
        'peerId': device.peerId,
        'signingPublicKey': device.signingPublicKey ?? '',
        'agreementPublicKey': device.agreementPublicKey ?? '',
        'endpointId': device.endpointId ?? '',
        'fcmTokenHash': device.fcmTokenHash ?? '',
        'approvedByDeviceId': approvedByDeviceId.trim(),
        'approvedAtMs': approvedAtMs,
        'sessionId': sessionId.trim(),
      }),
    );
  }

  List<int> accountMembershipUpdatePayloadBytes({
    required AccountIdentity identity,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) {
    final normalizedAffectedDeviceIds =
        affectedDeviceIds
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false)
          ..sort();
    return utf8.encode(
      jsonEncode(<String, dynamic>{
        'v': 1,
        'type': 'peerlink_account_membership_update',
        'accountId': identity.accountId.trim(),
        'actorDeviceId': actorDeviceId.trim(),
        'action': action.trim(),
        'affectedDeviceIds': normalizedAffectedDeviceIds,
        'updatedAtMs': updatedAtMs,
        'accountIdentity': identity.toJson(),
      }),
    );
  }
}
