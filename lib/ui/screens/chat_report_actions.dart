// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../../core/runtime/moderation_report_models.dart';
import '../localization/app_strings.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import '../state/chat_controller.dart';
import 'moderation_report_reason_presenter.dart';

class ChatReportActions {
  final ModerationReportReasonPresenter reasonPresenter;

  const ChatReportActions({
    this.reasonPresenter = const ModerationReportReasonPresenter(),
  });

  Future<void> reportUser({
    required BuildContext context,
    required Chat chat,
    required ChatController controller,
  }) async {
    final reason = await showReportReasonSheet(context: context);
    if (reason == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _submitReport(
      context: context,
      chat: chat,
      controller: controller,
      reason: reason,
    );
  }

  Future<void> reportMessage({
    required BuildContext context,
    required Chat chat,
    required ChatController controller,
    required Message message,
  }) async {
    final reason = await showReportReasonSheet(context: context);
    if (reason == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _submitReport(
      context: context,
      chat: chat,
      controller: controller,
      reason: reason,
      selectedMessage: message,
    );
  }

  Future<ModerationReportReason?> showReportReasonSheet({
    required BuildContext context,
  }) {
    return showModalBottomSheet<ModerationReportReason>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: ListView(
              shrinkWrap: true,
              children: reasonPresenter
                  .options(context.strings)
                  .map(
                    (option) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option.label),
                      onTap: () => Navigator.of(context).pop(option.reason),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitReport({
    required BuildContext context,
    required Chat chat,
    required ChatController controller,
    required ModerationReportReason reason,
    Message? selectedMessage,
  }) async {
    try {
      final reportedPeerId = chat.isGroup && selectedMessage != null
          ? (selectedMessage.senderPeerId ?? '').trim()
          : chat.peerId;
      if (reportedPeerId.isEmpty) {
        throw StateError('Reported peer is unknown');
      }
      await controller.reportPeer(
        peerId: reportedPeerId,
        reason: reason,
        selectedMessage: selectedMessage,
        groupId: chat.isGroup ? chat.peerId : null,
      );
      if (selectedMessage != null) {
        await controller.deleteMessage(chat.peerId, selectedMessage.id);
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.reportSent)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.reportFailed(error))),
      );
    }
  }
}
