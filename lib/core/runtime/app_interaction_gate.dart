// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'moderation_policy_service.dart';

class AppInteractionGate {
  final bool termsAccepted;
  final ModerationPolicySnapshot moderationPolicy;

  const AppInteractionGate({
    required this.termsAccepted,
    required this.moderationPolicy,
  });

  bool get shouldShowTermsGate => !termsAccepted;

  bool get shouldShowModerationGate =>
      moderationPolicy.shouldShowRestrictionScreen ||
      moderationPolicy.shouldShowWarningScreen;

  bool get canHandleExternalInteraction =>
      termsAccepted && !moderationPolicy.isBanned;

  String? get externalInteractionDropReason {
    if (!termsAccepted) {
      return 'terms_not_accepted';
    }
    if (moderationPolicy.isBanned) {
      return 'account_banned';
    }
    return null;
  }
}
