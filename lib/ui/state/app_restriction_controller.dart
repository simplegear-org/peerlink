// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../../core/calls/call_models.dart';
import '../../core/node/node_facade.dart';
import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/app_interaction_gate.dart';
import '../../core/runtime/moderation_policy_service.dart';
import '../../core/runtime/storage_service.dart';
import 'settings_controller.dart';

class AppRestrictionController {
  final NodeFacade facade;
  final SettingsController settingsController;
  final ModerationPolicyService _moderationPolicyService;

  late bool _termsAccepted;
  late ModerationPolicySnapshot _moderationPolicy;

  AppRestrictionController({
    required this.facade,
    required this.settingsController,
    required StorageService storage,
  }) : _moderationPolicyService = ModerationPolicyService.forStorage(storage) {
    _termsAccepted = settingsController.isCurrentTermsAccepted;
    _moderationPolicy = _moderationPolicyService.load();
  }

  ModerationPolicySnapshot get moderationPolicy => _moderationPolicy;

  AppInteractionGate get gate => AppInteractionGate(
    termsAccepted: _termsAccepted,
    moderationPolicy: _moderationPolicy,
  );

  Future<void> acceptCurrentTerms() async {
    await settingsController.acceptCurrentTerms();
    _termsAccepted = true;
  }

  Future<void> applyPolicyFromPush(
    ModerationPolicySnapshot snapshot, {
    required CallState callState,
  }) async {
    _moderationPolicy = snapshot;
    await _endCallIfBanned(snapshot, callState: callState);
  }

  Future<bool> refreshModerationStatus({required String reason}) async {
    try {
      final status = await facade.fetchModerationStatus();
      final score = status?['score'];
      if (score is! Map) {
        return false;
      }
      final payload = <String, dynamic>{
        'type': 'moderation_policy',
        'policyState': score['policyState'],
        'messageKey': score['policyState'] == 'banned'
            ? 'moderationBanMessage'
            : score['policyState'] == 'warning'
            ? 'moderationWarningMessage'
            : 'moderationUnbanMessage',
        'reportCount': score['reportCount'],
        'reporterCount': score['reporterCount'],
        if (status?['signedStatus'] != null)
          'signedStatus': status?['signedStatus'],
      };
      final snapshot = await _moderationPolicyService.applyPushPayload(
        payload,
        expectedPeerId: facade.peerId,
      );
      if (snapshot == null) {
        return false;
      }
      _moderationPolicy = snapshot;
      await _endCallIfBanned(snapshot, callState: facade.callState);
      return true;
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[ui] moderation status refresh failed reason=$reason error=$error',
        name: 'ui',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<void> markAppealSubmitted() async {
    _moderationPolicy = await _moderationPolicyService.markAppealSubmitted();
  }

  Future<void> markWarningAcknowledged() async {
    _moderationPolicy = await _moderationPolicyService
        .markWarningAcknowledged();
  }

  bool shouldDropExternalInteraction(String label) {
    final reason = gate.externalInteractionDropReason;
    if (reason == null) {
      return false;
    }
    AppFileLogger.log(
      '[ui] external interaction dropped label=$label reason=$reason',
      name: 'ui',
    );
    return true;
  }

  Future<void> _endCallIfBanned(
    ModerationPolicySnapshot snapshot, {
    required CallState callState,
  }) async {
    if (snapshot.isBanned && callState.isBusy) {
      await facade.endCall();
    }
  }
}
