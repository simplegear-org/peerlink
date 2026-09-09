// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/moderation/application/access_policy_api.dart';
import 'package:peerlink/features/moderation/application/moderation_reports_api.dart';
import 'package:peerlink/features/moderation/domain/moderation_report_models.dart';
import 'package:peerlink/features/chat/application/chat_safety_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';

abstract interface class ChatSafetyApi {
  bool isPeerBlocked(String peerId);

  bool isChatVisible(Chat chat);

  List<Message> visibleMessages(Chat chat);

  Message? visiblePreview(Chat chat);

  Future<void> blockAndReport(
    String peerId, {
    required ModerationReportReason reason,
    String? groupId,
  });

  Future<void> unblock(String peerId);

  Future<void> reportPeer({
    required String peerId,
    required ModerationReportReason reason,
    Message? selectedMessage,
    String? groupId,
  });
}

final class ChatControllerSafetyApi implements ChatSafetyApi {
  const ChatControllerSafetyApi({
    required AccessPolicyApi accessControl,
    required ModerationReportsApi moderationReports,
    required ChatSafetyService safetyService,
  }) : _accessControl = accessControl,
       _moderationReports = moderationReports,
       _safetyService = safetyService;

  final AccessPolicyApi _accessControl;
  final ModerationReportsApi _moderationReports;
  final ChatSafetyService _safetyService;

  @override
  bool isPeerBlocked(String peerId) => _accessControl.isBlocked(peerId);

  @override
  bool isChatVisible(Chat chat) => _safetyService.isChatVisible(chat);

  @override
  List<Message> visibleMessages(Chat chat) =>
      _safetyService.visibleMessages(chat);

  @override
  Message? visiblePreview(Chat chat) => _safetyService.visiblePreview(chat);

  @override
  Future<void> blockAndReport(
    String peerId, {
    required ModerationReportReason reason,
    String? groupId,
  }) => _safetyService.blockAndReport(peerId, reason: reason, groupId: groupId);

  @override
  Future<void> unblock(String peerId) => _safetyService.unblock(peerId);

  @override
  Future<void> reportPeer({
    required String peerId,
    required ModerationReportReason reason,
    Message? selectedMessage,
    String? groupId,
  }) {
    return _moderationReports.createDirectReport(
      reportedPeerId: peerId,
      reason: reason,
      selectedMessage: selectedMessage == null
          ? null
          : ModerationReportedMessageMetadata(
              messageId: selectedMessage.id,
              senderPeerId:
                  (selectedMessage.senderPeerId ?? selectedMessage.peerId)
                      .trim(),
              incoming: selectedMessage.incoming,
              timestamp: selectedMessage.timestamp,
              kind: selectedMessage.kind.name,
              mimeType: selectedMessage.kind == MessageKind.file
                  ? selectedMessage.mimeType
                  : null,
              fileSizeBytes: selectedMessage.kind == MessageKind.file
                  ? selectedMessage.fileSizeBytes
                  : null,
            ),
      groupId: groupId,
    );
  }
}
