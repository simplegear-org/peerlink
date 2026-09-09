// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/moderation/domain/moderation_report_models.dart';

abstract interface class ModerationReportsApi {
  Future<Map<String, dynamic>> createDirectReport({
    required String reportedPeerId,
    required ModerationReportReason reason,
    ModerationReportedMessageMetadata? selectedMessage,
    DateTime? createdAt,
    String? groupId,
  });

  Future<void> retryPendingReports();
}
