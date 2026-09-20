// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/features/moderation/application/access_policy_api.dart';
import 'package:peerlink/features/moderation/application/moderation_reports_api.dart';
import 'package:peerlink/features/moderation/domain/moderation_report_models.dart';
import '../domain/chat.dart';
import '../domain/message.dart';

/// Application integration; persistence and delivery remain with their owners.
class ChatSafetyService {
  const ChatSafetyService({
    required this.accessControl,
    required this.reports,
    required this.chats,
    required this.notifyMessageUpdated,
    required this.syncPushPolicy,
    required this.log,
  });

  final AccessPolicyApi accessControl;
  final ModerationReportsApi reports;
  final Iterable<Chat> Function() chats;
  final void Function(String peerId) notifyMessageUpdated;
  final Future<void> Function(String reason) syncPushPolicy;
  final void Function(String message) log;

  Future<void> blockAndReport(
    String peerId, {
    required ModerationReportReason reason,
    String? groupId,
  }) async {
    if (peerId.trim().isEmpty) throw ArgumentError.value(peerId, 'peerId');
    await accessControl.blockPeer(peerId, reason: reason.name);
    _notifyVisibilityChanged(peerId);
    unawaited(_sync('block_peer'));
    await reports.createDirectReport(
      reportedPeerId: peerId,
      reason: reason,
      groupId: groupId,
    );
  }

  Future<void> unblock(String peerId) async {
    await accessControl.unblockPeer(peerId);
    _notifyVisibilityChanged(peerId);
    await _sync('unblock_peer');
  }

  Future<void> _sync(String reason) async {
    try {
      await syncPushPolicy(reason);
    } catch (error) {
      log('access policy sync deferred: $error');
    }
  }

  void _notifyVisibilityChanged(String peerId) {
    notifyMessageUpdated(peerId);
    for (final chat in chats()) {
      if (chat.isGroup) notifyMessageUpdated(chat.peerId);
    }
  }

  bool isChatVisible(Chat chat) =>
      chat.isGroup || !accessControl.isBlocked(chat.peerId);

  bool isMessageVisible(Chat chat, Message message) =>
      isChatVisible(chat) &&
      (!chat.isGroup ||
          !accessControl.isBlocked(message.senderPeerId ?? message.peerId));

  List<Message> visibleMessages(Chat chat) => chat.messages
      .where((message) => isMessageVisible(chat, message))
      .toList(growable: false);

  Message? visiblePreview(Chat chat) {
    for (final message in chat.messages.reversed) {
      if (isMessageVisible(chat, message)) return message;
    }
    final preview = chat.previewMessage;
    return preview != null && isMessageVisible(chat, preview) ? preview : null;
  }
}
