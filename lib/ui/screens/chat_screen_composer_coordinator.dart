import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import 'chat_screen_audio_actions.dart';
import 'chat_screen_media_actions.dart';
import 'chat_screen_scroll_coordinator.dart';

class ChatScreenComposerCoordinator {
  final TextEditingController textController;
  final ChatScreenAudioActions audioActions;
  final ChatScreenMediaActions mediaActions;
  final ChatController Function() controller;
  final Chat Function() chat;
  final BuildContext Function() context;
  final bool Function() isMounted;
  final void Function() refresh;
  final ChatScreenScrollCoordinator scrollCoordinator;
  final int maxFileSize;
  final bool Function() isGroupChat;
  final bool Function() isCurrentUserInGroup;
  final void Function(String message) showPlaceholder;

  bool isSendingText = false;
  Message? replyToMessage;

  ChatScreenComposerCoordinator({
    required this.textController,
    required this.audioActions,
    required this.mediaActions,
    required this.controller,
    required this.chat,
    required this.context,
    required this.isMounted,
    required this.refresh,
    required this.scrollCoordinator,
    required this.maxFileSize,
    required this.isGroupChat,
    required this.isCurrentUserInGroup,
    required this.showPlaceholder,
  });

  void handleDraftChanged() {
    try {
      if (!isMounted()) {
        return;
      }
      refresh();
    } catch (e, stack) {
      developer.log(
        '[chat_ui] draft listener failed: $e\n$stack',
        name: 'chat',
      );
    }
  }

  void handleSendPressed() {
    unawaited(send());
  }

  void setReplyTarget(Message message) {
    if (!isMounted()) {
      return;
    }
    replyToMessage = message;
    refresh();
  }

  void clearReplyTarget() {
    if (!isMounted()) {
      return;
    }
    replyToMessage = null;
    refresh();
  }

  Future<void> send() async {
    if (isGroupChat() && !isCurrentUserInGroup()) {
      if (isMounted() && context().mounted) {
        ScaffoldMessenger.of(context()).showSnackBar(
          SnackBar(content: Text(context().strings.notGroupMember)),
        );
      }
      return;
    }

    if (audioActions.hasStoppedRecording) {
      await audioActions.sendVoiceRecording(
        context: context(),
        isMounted: isMounted,
        refresh: refresh,
        controller: controller(),
        peerId: chat().peerId,
        replyTo: replyToMessage,
        clearReplyTarget: clearReplyTarget,
        jumpToBottom: scrollCoordinator.jumpToBottom,
      );
      return;
    }

    if (isSendingText) {
      return;
    }

    final text = textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    textController.clear();
    isSendingText = true;
    if (isMounted()) {
      refresh();
    }

    try {
      await controller().sendMessage(
        chat().peerId,
        text,
        replyTo: replyToMessage,
      );
    } finally {
      isSendingText = false;
      if (isMounted()) {
        refresh();
      }
    }

    if (!isMounted()) {
      return;
    }
    clearReplyTarget();
    scrollCoordinator.jumpToBottom();
  }

  Future<void> pickAndSendGalleryMedia() async {
    await mediaActions.pickAndSendGalleryMedia(
      context: context(),
      controller: controller(),
      peerId: chat().peerId,
      maxFileSize: maxFileSize,
      showPlaceholder: showPlaceholder,
      replyTo: replyToMessage,
    );
    clearReplyTarget();
  }
}
