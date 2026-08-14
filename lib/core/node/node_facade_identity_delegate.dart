// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../security/account_identity.dart';
import '../security/identity_service.dart';

class NodeFacadeIdentityDelegate {
  NodeFacadeIdentityDelegate(this._identity);

  final IdentityService _identity;

  String get peerId => _identity.nodeId;
  String get accountId => _identity.accountId;
  String get activeAccountId => _identity.activeAccountId;
  String get homeAccountId => _identity.homeAccountId;
  String get deviceId => _identity.deviceId;
  AccountIdentity get accountIdentity => _identity.accountIdentity;
  String? get endpointId => _identity.endpointId;
  String? get fcmTokenHash => _identity.fcmTokenHash;
  Map<String, dynamic> get identityBundleV3Json =>
      _identity.identityBundleV3Json;

  Future<AccountIdentity> mergeAccountIdentity(AccountIdentity incoming) {
    return _identity.mergeAccountIdentity(incoming);
  }

  Future<AccountIdentity> resetToNewLocalAccount() {
    return _identity.resetToNewLocalAccount();
  }

  Future<void> clearPersistedIdentity({required bool preserveDeviceKeys}) {
    return _identity.clearPersistedIdentity(
      preserveDeviceKeys: preserveDeviceKeys,
    );
  }

  Future<AccountIdentity> issueApprovedPairingAccountIdentity({
    required AccountDeviceIdentity requestedDevice,
    required String sessionId,
  }) {
    return _identity.issueApprovedPairingAccountIdentity(
      requestedDevice: requestedDevice,
      sessionId: sessionId,
    );
  }

  Future<AccountIdentity> applyApprovedPairingAccountIdentity({
    required AccountIdentity incoming,
    required String expectedSessionId,
    required String expectedAccountId,
  }) {
    return _identity.applyApprovedPairingAccountIdentity(
      incoming: incoming,
      expectedSessionId: expectedSessionId,
      expectedAccountId: expectedAccountId,
    );
  }

  Future<AccountIdentity> issueRevokedAccountIdentity({
    required Iterable<String> revokedDeviceIds,
  }) {
    return _identity.issueRevokedAccountIdentity(
      revokedDeviceIds: revokedDeviceIds,
    );
  }

  Future<String> signAccountMembershipUpdate({
    required AccountIdentity identity,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
  }) {
    return _identity.signAccountMembershipUpdate(
      identity: identity,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
    );
  }

  Future<AccountIdentity> applyAccountMembershipUpdate({
    required AccountIdentity incoming,
    required String actorDeviceId,
    required String action,
    required Iterable<String> affectedDeviceIds,
    required int updatedAtMs,
    required String signature,
  }) {
    return _identity.applyAccountMembershipUpdate(
      incoming: incoming,
      actorDeviceId: actorDeviceId,
      action: action,
      affectedDeviceIds: affectedDeviceIds,
      updatedAtMs: updatedAtMs,
      signature: signature,
    );
  }
}
