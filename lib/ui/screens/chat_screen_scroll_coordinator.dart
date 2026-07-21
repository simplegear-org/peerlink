import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import 'chat_screen_viewport_state.dart';

class ChatScreenScrollCoordinator {
  static const double _loadMoreThreshold = 120;
  static const double _scrollToBottomButtonThreshold = 260;

  final ScrollController scrollController;
  final GlobalKey unreadDividerKey;
  final Chat Function() chat;
  final ChatController Function() controller;
  final BuildContext Function() context;
  final bool Function() isMounted;
  final void Function() refresh;
  final GlobalKey Function(String messageId) messageKeyFor;
  final bool Function(Message message) isInitialUnreadAnchor;
  final void Function(String message) showPlaceholder;

  ChatScreenViewportState _state = const ChatScreenViewportState();

  Timer? _highlightClearTimer;
  Timer? _loadMoreNoticeTimer;

  ChatScreenScrollCoordinator({
    required this.scrollController,
    required this.unreadDividerKey,
    required this.chat,
    required this.controller,
    required this.context,
    required this.isMounted,
    required this.refresh,
    required this.messageKeyFor,
    required this.isInitialUnreadAnchor,
    required this.showPlaceholder,
  });

  bool get isLoadingMore => _state.isLoadingMore;
  bool get initialPositionApplied => _state.initialPositionApplied;
  bool get initialPositionScheduled => _state.initialPositionScheduled;
  bool get followBottomScheduled => _state.followBottomScheduled;
  bool get markReadScheduled => _state.markReadScheduled;
  bool get isProgrammaticMessageJump => _state.isProgrammaticMessageJump;
  bool get showScrollToBottomButton => _state.showScrollToBottomButton;
  String? get unreadDividerMessageId => _state.unreadDividerMessageId;
  String? get highlightedMessageId => _state.highlightedMessageId;
  int? get lastLoadedOlderCount => _state.lastLoadedOlderCount;

  bool isNearBottom({double threshold = 160}) {
    if (!scrollController.hasClients) {
      return true;
    }
    final position = scrollController.position;
    return position.maxScrollExtent - position.pixels <= threshold;
  }

  void maybeLoadMoreMessages() {
    if (isLoadingMore ||
        isProgrammaticMessageJump ||
        !scrollController.hasClients) {
      return;
    }

    final activeChat = chat();
    if (!activeChat.hasMoreMessages || !activeChat.messagesLoaded) {
      return;
    }

    final position = scrollController.position;
    if (position.extentBefore > _loadMoreThreshold &&
        position.pixels > _loadMoreThreshold) {
      return;
    }

    developer.log(
      '[chat_ui] loadMore trigger peer=${activeChat.peerId} '
      'pixels=${position.pixels.toStringAsFixed(1)} '
      'extentBefore=${position.extentBefore.toStringAsFixed(1)} '
      'max=${position.maxScrollExtent.toStringAsFixed(1)} '
      'loaded=${activeChat.messages.length} '
      'hasMore=${activeChat.hasMoreMessages}',
      name: 'chat',
    );
    unawaited(loadMoreMessages());
  }

  void syncScrollToBottomButton() {
    if (!isMounted()) {
      return;
    }
    final nextValue = _shouldShowScrollToBottomButton();
    if (nextValue == showScrollToBottomButton) {
      return;
    }
    _updateState(_state.copyWith(showScrollToBottomButton: nextValue));
  }

  void scheduleMarkChatAsRead() {
    if (markReadScheduled) {
      return;
    }
    _updateState(_state.copyWith(markReadScheduled: true));
    unawaited(() async {
      try {
        await safeMarkChatAsRead();
      } finally {
        _updateState(_state.copyWith(markReadScheduled: false));
      }
    }());
  }

  void scheduleFollowBottomAndRead() {
    if (followBottomScheduled) {
      return;
    }
    _updateState(_state.copyWith(followBottomScheduled: true));
    unawaited(() async {
      try {
        await jumpToBottomAfterLayout(settle: true);
        if (!isMounted()) {
          return;
        }
        if (isNearBottom()) {
          scheduleMarkChatAsRead();
        }
        syncScrollToBottomButton();
      } finally {
        _updateState(_state.copyWith(followBottomScheduled: false));
      }
    }());
  }

  Future<void> loadMoreMessages() async {
    if (isLoadingMore) {
      return;
    }

    final activeChat = chat();
    final previousLoadedCount = activeChat.messages.length;
    final previousPixels = scrollController.hasClients
        ? scrollController.position.pixels
        : 0.0;
    final previousMaxScrollExtent = scrollController.hasClients
        ? scrollController.position.maxScrollExtent
        : 0.0;

    _updateState(_state.copyWith(isLoadingMore: true));

    try {
      developer.log(
        '[chat_ui] loadMore start peer=${activeChat.peerId} '
        'loaded=${activeChat.messages.length} '
        'hasMore=${activeChat.hasMoreMessages}',
        name: 'chat',
      );
      final loaded = await controller().loadMoreMessages(activeChat.peerId);
      final updatedChat = chat();
      final addedCount = updatedChat.messages.length - previousLoadedCount;
      developer.log(
        '[chat_ui] loadMore result peer=${updatedChat.peerId} '
        'loadedResult=$loaded '
        'added=$addedCount '
        'loadedNow=${updatedChat.messages.length} '
        'hasMoreNow=${updatedChat.hasMoreMessages}',
        name: 'chat',
      );
      if (!loaded || !isMounted()) {
        return;
      }

      _loadMoreNoticeTimer?.cancel();
      _updateState(
        _state.copyWith(
          lastLoadedOlderCount: addedCount > 0 ? addedCount : null,
        ),
      );
      if (addedCount > 0) {
        _loadMoreNoticeTimer = Timer(const Duration(seconds: 2), () {
          if (!isMounted()) {
            return;
          }
          _updateState(_state.copyWith(lastLoadedOlderCount: null));
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (!scrollController.hasClients) {
            return;
          }
          final newMaxScrollExtent = scrollController.position.maxScrollExtent;
          final delta = newMaxScrollExtent - previousMaxScrollExtent;
          final targetOffset = (previousPixels + delta).clamp(
            0.0,
            newMaxScrollExtent,
          );
          scrollController.jumpTo(targetOffset);
          maybeLoadMoreMessages();
          syncScrollToBottomButton();
        } catch (e, stack) {
          developer.log(
            '[chat_ui] loadMore scroll restore failed: $e\n$stack',
            name: 'chat',
          );
        }
      });
    } catch (_) {
      // Diagnostics disabled.
    } finally {
      _updateState(_state.copyWith(isLoadingMore: false));
    }
  }

  Future<BuildContext?> resolveMessageContext({
    required String messageId,
    required int targetIndex,
  }) async {
    final targetKey = messageKeyFor(messageId);
    BuildContext? targetContext = targetKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      return targetContext;
    }

    if (!scrollController.hasClients || chat().messages.isEmpty) {
      return null;
    }

    Future<void> waitForLayout() async {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    final messages = chat().messages;
    final ratio = messages.length <= 1
        ? 0.0
        : targetIndex / (messages.length - 1);
    final position = scrollController.position;
    final estimatedTargetOffset = position.maxScrollExtent * ratio;
    final viewport = position.viewportDimension > 0
        ? position.viewportDimension
        : 600.0;
    final step = viewport * 0.85;
    final startOffset = position.pixels;
    final direction = estimatedTargetOffset < startOffset ? -1.0 : 1.0;
    final maxAttempts = ((position.maxScrollExtent / step).ceil() + 3)
        .clamp(8, 80)
        .toInt();

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!isMounted() || !scrollController.hasClients) {
        return null;
      }
      final candidate = startOffset + (direction * step * attempt);
      final clamped = candidate.clamp(
        0.0,
        scrollController.position.maxScrollExtent,
      );
      developer.log(
        '[chat_ui] jumpToMessage scan peer=${chat().peerId} '
        'messageId=$messageId targetIndex=$targetIndex '
        'attempt=$attempt/$maxAttempts offset=$clamped '
        'estimated=$estimatedTargetOffset direction=$direction',
        name: 'chat',
      );
      final distance = (scrollController.position.pixels - clamped).abs();
      if (distance > 1) {
        await scrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOutCubic,
        );
      }
      await waitForLayout();
      targetContext = targetKey.currentContext;
      if (targetContext != null && targetContext.mounted) {
        return targetContext;
      }
      if (clamped <= 0 ||
          clamped >= scrollController.position.maxScrollExtent) {
        break;
      }
    }

    if (!isMounted()) {
      return null;
    }
    refresh();
    await waitForLayout();
    targetContext = targetKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      return targetContext;
    }

    return null;
  }

  Future<void> jumpToMessage(String messageId) async {
    final strings = context().strings;
    final activeChat = chat();
    final targetOffsetFromNewest = await controller().messageOffsetFromNewest(
      activeChat.peerId,
      messageId,
    );
    developer.log(
      '[chat_ui] jumpToMessage start peer=${activeChat.peerId} '
      'messageId=$messageId loaded=${activeChat.messages.length} '
      'hasMore=${activeChat.hasMoreMessages} targetOffset=$targetOffsetFromNewest',
      name: 'chat',
    );

    if (targetOffsetFromNewest == null) {
      showPlaceholder(strings.sourceMessageNotFoundLocal);
      return;
    }

    const maxLoadAttempts = 64;
    var loadAttempts = 0;
    while (!_containsMessage(messageId) &&
        chat().hasMoreMessages &&
        chat().messages.length <= targetOffsetFromNewest &&
        loadAttempts < maxLoadAttempts) {
      developer.log(
        '[chat_ui] jumpToMessage loading older peer=${chat().peerId} '
        'messageId=$messageId attempt=${loadAttempts + 1} '
        'loaded=${chat().messages.length} targetOffset=$targetOffsetFromNewest',
        name: 'chat',
      );
      await loadMoreMessages();
      loadAttempts++;
      if (!isMounted()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }

    while (!_containsMessage(messageId) &&
        chat().hasMoreMessages &&
        loadAttempts < maxLoadAttempts) {
      developer.log(
        '[chat_ui] jumpToMessage fallback loading peer=${chat().peerId} '
        'messageId=$messageId attempt=${loadAttempts + 1} '
        'loaded=${chat().messages.length}',
        name: 'chat',
      );
      await loadMoreMessages();
      loadAttempts++;
      if (!isMounted()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }

    final targetIndex = chat().messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (targetIndex == -1) {
      developer.log(
        '[chat_ui] jumpToMessage failed-not-loaded peer=${chat().peerId} '
        'messageId=$messageId loaded=${chat().messages.length} '
        'hasMore=${chat().hasMoreMessages} attempts=$loadAttempts '
        'targetOffset=$targetOffsetFromNewest',
        name: 'chat',
      );
      showPlaceholder(strings.sourceMessageNotFoundCurrent);
      return;
    }

    _updateState(_state.copyWith(isProgrammaticMessageJump: true));
    try {
      final targetContext = await resolveMessageContext(
        messageId: messageId,
        targetIndex: targetIndex,
      );

      if (targetContext == null || !targetContext.mounted) {
        developer.log(
          '[chat_ui] jumpToMessage failed-no-context peer=${chat().peerId} '
          'messageId=$messageId targetIndex=$targetIndex loaded=${chat().messages.length}',
          name: 'chat',
        );
        showPlaceholder(strings.sourceMessageJumpFailed);
        return;
      }

      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );

      if (!isMounted()) {
        return;
      }
      _highlightClearTimer?.cancel();
      _updateState(_state.copyWith(highlightedMessageId: messageId));
      _highlightClearTimer = Timer(const Duration(seconds: 2), () {
        if (!isMounted() || highlightedMessageId != messageId) {
          return;
        }
        _updateState(_state.copyWith(highlightedMessageId: null));
      });
    } finally {
      _updateState(_state.copyWith(isProgrammaticMessageJump: false));
    }
  }

  void scheduleInitialViewport() {
    if (initialPositionApplied || initialPositionScheduled || !isMounted()) {
      return;
    }
    _updateState(_state.copyWith(initialPositionScheduled: true));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!isMounted() || initialPositionApplied) {
          return;
        }

        final visibleMessages = chat().messages;
        if (visibleMessages.isEmpty) {
          return;
        }

        final unreadMessageId =
            unreadDividerMessageId ?? firstUnreadMessageId(visibleMessages);
        var positioned = false;
        if (unreadMessageId == null) {
          developer.log(
            '[chat_ui] initialViewport peer=${chat().peerId} mode=bottom',
            name: 'chat',
          );
          await jumpToBottomAfterLayout(settle: true);
          positioned = true;
        } else {
          positioned = await scrollToInitialUnread(unreadMessageId);
        }

        if (!positioned) {
          return;
        }

        _updateState(_state.copyWith(initialPositionApplied: true));
        await safeMarkChatAsRead();
        syncScrollToBottomButton();
      } catch (e, stack) {
        developer.log(
          '[chat_ui] initial viewport failed: $e\n$stack',
          name: 'chat',
        );
      } finally {
        if (!initialPositionApplied) {
          _updateState(_state.copyWith(initialPositionScheduled: false));
        }
      }
    });
  }

  Future<bool> scrollToInitialUnread(String unreadMessageId) async {
    if (unreadDividerMessageId != unreadMessageId) {
      if (!isMounted()) {
        return false;
      }
      _updateState(_state.copyWith(unreadDividerMessageId: unreadMessageId));
    }

    var attempts = 24;
    var computedAttempts = false;
    for (var attempt = 0; attempt < attempts; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!isMounted()) {
        return false;
      }

      final dividerContext = unreadDividerKey.currentContext;
      if (dividerContext != null && dividerContext.mounted) {
        developer.log(
          '[chat_ui] initialViewport peer=${chat().peerId} mode=firstUnread '
          'messageId=$unreadMessageId via=divider attempt=${attempt + 1}/$attempts',
          name: 'chat',
        );
        await Scrollable.ensureVisible(
          dividerContext,
          alignment: 0.5,
          duration: Duration.zero,
        );
        return true;
      }

      final targetIndex = chat().messages.indexWhere(
        (message) => message.id == unreadMessageId,
      );
      if (targetIndex == -1) {
        developer.log(
          '[chat_ui] initialViewport peer=${chat().peerId} mode=firstUnread '
          'messageId=$unreadMessageId via=missing loaded=${chat().messages.length}',
          name: 'chat',
        );
        return false;
      }

      final targetContext = messageKeyFor(unreadMessageId).currentContext;
      if (targetContext != null && targetContext.mounted) {
        developer.log(
          '[chat_ui] initialViewport peer=${chat().peerId} mode=firstUnread '
          'messageId=$unreadMessageId via=message attempt=${attempt + 1}/$attempts',
          name: 'chat',
        );
        await Scrollable.ensureVisible(
          targetContext,
          alignment: 0.35,
          duration: Duration.zero,
        );
        return true;
      }

      if (!scrollController.hasClients || chat().messages.isEmpty) {
        continue;
      }

      final position = scrollController.position;
      final viewport = position.viewportDimension > 0
          ? position.viewportDimension
          : 600.0;
      final step = viewport * 0.85;
      if (!computedAttempts) {
        attempts = ((position.maxScrollExtent / step).ceil() + 4)
            .clamp(24, 80)
            .toInt();
        computedAttempts = true;
      }

      final ratio = chat().messages.length <= 1
          ? 0.0
          : targetIndex / (chat().messages.length - 1);
      final estimatedOffset = position.maxScrollExtent * ratio;
      final scanOffset = position.maxScrollExtent - step * (attempt - 1);
      final offset = attempt == 0 ? estimatedOffset : scanOffset;
      final clampedOffset = offset.clamp(0.0, position.maxScrollExtent);
      developer.log(
        '[chat_ui] initialViewport peer=${chat().peerId} mode=firstUnread '
        'messageId=$unreadMessageId via=probe attempt=${attempt + 1}/$attempts '
        'targetIndex=$targetIndex offset=$clampedOffset',
        name: 'chat',
      );
      scrollController.jumpTo(clampedOffset);
    }

    developer.log(
      '[chat_ui] initialViewport peer=${chat().peerId} mode=firstUnread '
      'messageId=$unreadMessageId via=failed loaded=${chat().messages.length}',
      name: 'chat',
    );
    return false;
  }

  Future<void> safeMarkChatAsRead() async {
    try {
      await controller().markChatAsRead(chat().peerId);
    } catch (e, stack) {
      developer.log(
        '[chat_ui] markChatAsRead failed: $e\n$stack',
        name: 'chat',
      );
    }
  }

  String? firstUnreadMessageId(List<Message> messages) {
    for (final message in messages) {
      if (isInitialUnreadAnchor(message)) {
        return message.id;
      }
    }
    return null;
  }

  String? firstUnreadMessageIdForManualJump() {
    return firstUnreadMessageId(chat().messages);
  }

  Future<void> handleScrollToBottomPressed() async {
    final unreadMessageId = firstUnreadMessageIdForManualJump();
    if (unreadMessageId != null) {
      await jumpToMessage(unreadMessageId);
    } else {
      await jumpToBottomAfterLayout(settle: true);
    }
    if (!isMounted()) {
      return;
    }
    if (isNearBottom()) {
      scheduleMarkChatAsRead();
    }
    syncScrollToBottomButton();
  }

  bool handleMessageListScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (lastLoadedOlderCount != null &&
        notification is ScrollUpdateNotification &&
        notification.metrics.axisDirection == AxisDirection.down) {
      _updateState(_state.copyWith(lastLoadedOlderCount: null));
    }
    maybeLoadMoreMessages();
    if (initialPositionApplied && isNearBottom()) {
      scheduleMarkChatAsRead();
    }
    return false;
  }

  void jumpToBottom() {
    unawaited(() async {
      await jumpToBottomAfterLayout();
      syncScrollToBottomButton();
    }());
  }

  Future<void> jumpToBottomAfterLayout({bool settle = false}) async {
    final attempts = settle ? 24 : 4;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!isMounted() || !scrollController.hasClients) {
          return;
        }
        final target = scrollController.position.maxScrollExtent;
        developer.log(
          '[chat_ui] jumpToBottom peer=${chat().peerId} '
          'attempt=${attempt + 1}/$attempts target=$target settle=$settle',
          name: 'chat',
        );
        scrollController.jumpTo(target);
        if (!settle && (scrollController.position.pixels - target).abs() < 2) {
          return;
        }
      } catch (e, stack) {
        developer.log(
          '[chat_ui] jumpToBottom failed: $e\n$stack',
          name: 'chat',
        );
      }
    }
  }

  void dispose() {
    _highlightClearTimer?.cancel();
    _loadMoreNoticeTimer?.cancel();
  }

  void _updateState(ChatScreenViewportState nextState) {
    final changed = !identical(_state, nextState);
    _state = nextState;
    if (changed && isMounted()) {
      refresh();
    }
  }

  bool _containsMessage(String messageId) {
    return chat().messages.any((message) => message.id == messageId);
  }

  bool _shouldShowScrollToBottomButton() {
    if (!scrollController.hasClients) {
      return false;
    }
    final position = scrollController.position;
    return position.maxScrollExtent - position.pixels >
        _scrollToBottomButtonThreshold;
  }
}
