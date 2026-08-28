// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../../core/runtime/moderation_report_models.dart';
import '../localization/app_strings.dart';

class ModerationReportReasonOption {
  final ModerationReportReason reason;
  final String label;

  const ModerationReportReasonOption({
    required this.reason,
    required this.label,
  });
}

class ModerationReportReasonPresenter {
  const ModerationReportReasonPresenter();

  List<ModerationReportReasonOption> options(AppStrings strings) {
    return <ModerationReportReasonOption>[
      ModerationReportReasonOption(
        reason: ModerationReportReason.spam,
        label: strings.reportReasonSpam,
      ),
      ModerationReportReasonOption(
        reason: ModerationReportReason.harassment,
        label: strings.reportReasonHarassment,
      ),
      ModerationReportReasonOption(
        reason: ModerationReportReason.threats,
        label: strings.reportReasonThreats,
      ),
      ModerationReportReasonOption(
        reason: ModerationReportReason.illegalContent,
        label: strings.reportReasonIllegalContent,
      ),
      ModerationReportReasonOption(
        reason: ModerationReportReason.other,
        label: strings.reportReasonOther,
      ),
    ];
  }
}
