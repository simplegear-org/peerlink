// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

enum ModerationReportReason { spam, harassment, threats, illegalContent, other }

class ModerationReportedMessageMetadata {
  final String messageId;
  final String senderPeerId;
  final bool incoming;
  final DateTime timestamp;
  final String kind;
  final String? mimeType;
  final int? fileSizeBytes;

  const ModerationReportedMessageMetadata({
    required this.messageId,
    required this.senderPeerId,
    required this.incoming,
    required this.timestamp,
    required this.kind,
    this.mimeType,
    this.fileSizeBytes,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'messageId': messageId,
      'senderPeerId': senderPeerId.trim(),
      'incoming': incoming,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'kind': kind,
      if (mimeType != null) 'mimeType': mimeType,
      if (fileSizeBytes != null) 'fileSizeBytes': fileSizeBytes,
    };
  }
}
