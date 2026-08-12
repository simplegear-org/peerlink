import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import 'chat_screen_unread_target_resolver.dart';
import 'chat_screen_viewport_state.dart';

class ChatScreenScrollCoordinator {
  static const int _olderMessagesPrefetchThreshold = 20;
  static const double _scrollToBottomButtonThreshold = 260;
  static const Duration _userScrollAwayHold = Duration(seconds: 2);

  final ScrollController scrollController = ScrollController();
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
  DateTime? _userScrolledAwayUntil;

  ChatScreenScrollCoordinator({
    required this.unreadDividerKey,
    required this.chat,
    required this.controller,
    required this.context,
    required this.isMounted,
    required this.refresh,
    required this.messageKeyFor,
    required this.isInitialUnreadAnchor,
    required this.showPlaceholder,
  }) {
    scrollController.addListener(_handleScroll);
  }

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
    return position.pixels <= threshold;
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

    final firstVisibleIndex = _firstVisibleMessageIndex();
    if (firstVisibleIndex == null ||
        firstVisibleIndex >= _olderMessagesPrefetchThreshold) {
      return;
    }

    developer.log(
      '[chat_ui] loadMore trigger peer=${activeChat.peerId} '
      'firstVisibleIndex=$firstVisibleIndex '
      'loaded=${activeChat.messages.length} '
      'hasMore=${activeChat.hasMoreMessages}',
      name: 'chat',
      level: 900,
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
    if (_isUserScrollAwayActive()) {
      developer.log(
        '[chat_ui] followBottom skipped peer=${chat().peerId} reason=user-scroll-away',
        name: 'chat',
      );
      return;
    }
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

    _updateState(_state.copyWith(isLoadingMore: true));

    try {
      developer.log(
        '[chat_ui] loadMore start peer=${activeChat.peerId} '
        'loaded=${activeChat.messages.length} '
        'hasMore=${activeChat.hasMoreMessages}',
        name: 'chat',
        level: 900,
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
        level: 900,
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
        syncScrollToBottomButton();
      });
    } catch (e, stack) {
      developer.log('[chat_ui] loadMore failed: $e\n$stack', name: 'chat');
    } finally {
      _updateState(_state.copyWith(isLoadingMore: false));
    }
  }

  Future<BuildContext?> resolveMessageContext({
    required String messageId,
    required int targetIndex,
    bool animateScan = true,
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
        : (messages.length - 1 - targetIndex) / (messages.length - 1);
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

    for (var attempt = 0; attempt <= maxAttempts; attempt++) {
      if (!isMounted() || !scrollController.hasClients) {
        return null;
      }
      final candidate = attempt == 0
          ? estimatedTargetOffset
          : animateScan
          ? startOffset + (direction * step * attempt)
          : _nearEstimatedOffset(
              estimatedTargetOffset: estimatedTargetOffset,
              step: step,
              attempt: attempt,
            );
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
        if (animateScan) {
          await scrollController.animateTo(
            clamped,
            duration: const Duration(milliseconds: 80),
            curve: Curves.easeOutCubic,
          );
        } else {
          scrollController.jumpTo(clamped);
        }
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

  Future<bool> jumpToMessage(
    String messageId, {
    bool showErrors = true,
    bool animateScan = true,
    bool animateFinal = true,
  }) async {
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
      if (showErrors) {
        showPlaceholder(strings.sourceMessageNotFoundLocal);
      }
      return false;
    }

    const maxLoadAttempts = 64;
    var loadAttempts = 0;
    while (!ChatScreenUnreadTargetResolver.containsMessage(
          chat().messages,
          messageId,
        ) &&
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
        return false;
      }
      await Future<void>.delayed(Duration.zero);
    }

    while (!ChatScreenUnreadTargetResolver.containsMessage(
          chat().messages,
          messageId,
        ) &&
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
        return false;
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
      if (showErrors) {
        showPlaceholder(strings.sourceMessageNotFoundCurrent);
      }
      return false;
    }

    _updateState(_state.copyWith(isProgrammaticMessageJump: true));
    try {
      final targetContext = await resolveMessageContext(
        messageId: messageId,
        targetIndex: targetIndex,
        animateScan: animateScan,
      );

      if (targetContext == null || !targetContext.mounted) {
        developer.log(
          '[chat_ui] jumpToMessage failed-no-context peer=${chat().peerId} '
          'messageId=$messageId targetIndex=$targetIndex loaded=${chat().messages.length}',
          name: 'chat',
        );
        if (showErrors) {
          showPlaceholder(strings.sourceMessageJumpFailed);
        }
        return false;
      }

      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.35,
        duration: animateFinal
            ? const Duration(milliseconds: 220)
            : Duration.zero,
        curve: Curves.easeOutCubic,
      );

      if (!isMounted()) {
        return false;
      }
      _highlightClearTimer?.cancel();
      _updateState(_state.copyWith(highlightedMessageId: messageId));
      _highlightClearTimer = Timer(const Duration(seconds: 2), () {
        if (!isMounted() || highlightedMessageId != messageId) {
          return;
        }
        _updateState(_state.copyWith(highlightedMessageId: null));
      });
      return true;
    } finally {
      _updateState(_state.copyWith(isProgrammaticMessageJump: false));
    }
  }

  void scheduleInitialViewport() {
    if (initialPositionApplied || initialPositionScheduled || !isMounted()) {
      developer.log(
        '[chat_ui] initialViewport skip peer=${chat().peerId} '
        'applied=$initialPositionApplied scheduled=$initialPositionScheduled '
        'mounted=${isMounted()}',
        name: 'chat',
        level: 900,
      );
      return;
    }
    developer.log(
      '[chat_ui] initialViewport schedule peer=${chat().peerId} '
      'messages=${chat().messages.length} '
      'loaded=${chat().messagesLoaded} '
      'hasMore=${chat().hasMoreMessages}',
      name: 'chat',
      level: 900,
    );
    _updateState(_state.copyWith(initialPositionScheduled: true));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!isMounted() || initialPositionApplied) {
          return;
        }

        final visibleMessages = chat().messages;
        if (visibleMessages.isEmpty) {
          developer.log(
            '[chat_ui] initialViewport wait-empty peer=${chat().peerId}',
            name: 'chat',
            level: 900,
          );
          return;
        }

        final unreadMessageId =
            unreadDividerMessageId ??
            await controller().firstInitialUnreadMessageId(chat().peerId) ??
            firstUnreadMessageId(visibleMessages);
        if (unreadMessageId != null &&
            unreadDividerMessageId != unreadMessageId) {
          _updateState(
            _state.copyWith(unreadDividerMessageId: unreadMessageId),
          );
          await WidgetsBinding.instance.endOfFrame;
        }

        developer.log(
          '[chat_ui] initialViewport peer=${chat().peerId} '
          'mode=${unreadMessageId == null ? "bottom" : "bottomThenUnread"} '
          'messageId=${unreadMessageId ?? ""}',
          name: 'chat',
        );
        await jumpToBottomAfterLayout(settle: true);

        developer.log(
          '[chat_ui] initialViewport applied peer=${chat().peerId} '
          'messages=${chat().messages.length} '
          'nearBottom=${isNearBottom()}',
          name: 'chat',
          level: 900,
        );
        _updateState(_state.copyWith(initialPositionApplied: true));
        var canMarkRead = true;
        if (unreadMessageId != null) {
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 120));
          if (!isMounted()) {
            return;
          }
          canMarkRead = await jumpToMessage(
            unreadMessageId,
            showErrors: false,
            animateScan: false,
            animateFinal: false,
          );
        }
        if (canMarkRead) {
          await safeMarkChatAsRead();
        }
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
    return ChatScreenUnreadTargetResolver.firstUnreadMessageId(
      messages,
      isInitialUnreadAnchor: isInitialUnreadAnchor,
    );
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
    if (notification is UserScrollNotification ||
        notification is ScrollUpdateNotification) {
      _trackUserScrollIntent(notification);
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

  void _trackUserScrollIntent(ScrollNotification notification) {
    if (isProgrammaticMessageJump || !initialPositionApplied) {
      return;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction == ScrollDirection.forward &&
          !isNearBottom(threshold: 24)) {
        _userScrolledAwayUntil = DateTime.now().add(_userScrollAwayHold);
      }
      if (notification.direction == ScrollDirection.reverse &&
          isNearBottom(threshold: 24)) {
        _userScrolledAwayUntil = null;
      }
      return;
    }
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null &&
        (notification.scrollDelta ?? 0) < 0 &&
        !isNearBottom(threshold: 24)) {
      _userScrolledAwayUntil = DateTime.now().add(_userScrollAwayHold);
    }
  }

  void jumpToBottom() {
    unawaited(() async {
      await jumpToBottomAfterLayout();
      syncScrollToBottomButton();
    }());
  }

  Future<void> jumpToBottomAfterLayout({bool settle = false}) async {
    final attempts = settle ? 24 : 4;
    var stableBottomFrames = 0;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 16));
        if (!isMounted() || !scrollController.hasClients) {
          return;
        }
        const target = 0.0;
        final current = scrollController.position.pixels;
        final distance = (current - target).abs();
        developer.log(
          '[chat_ui] jumpToBottom peer=${chat().peerId} '
          'attempt=${attempt + 1}/$attempts current=${current.toStringAsFixed(1)} '
          'target=${target.toStringAsFixed(1)} distance=${distance.toStringAsFixed(1)} '
          'stable=$stableBottomFrames settle=$settle',
          name: 'chat',
          level: 900,
        );
        if (distance > 2) {
          scrollController.jumpTo(target);
          stableBottomFrames = 0;
          continue;
        }
        stableBottomFrames += 1;
        if (!settle || stableBottomFrames >= 2) {
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
    scrollController.removeListener(_handleScroll);
    scrollController.dispose();
    _highlightClearTimer?.cancel();
    _loadMoreNoticeTimer?.cancel();
  }

  void _handleScroll() {
    maybeLoadMoreMessages();
    syncScrollToBottomButton();
  }

  int? _firstVisibleMessageIndex() {
    final messages = chat().messages;
    if (messages.isEmpty) {
      return null;
    }
    final viewport = _viewportGlobalBounds();
    if (viewport == null) {
      return null;
    }
    for (var index = 0; index < messages.length; index++) {
      final bounds = _messageGlobalBounds(messages[index].id);
      if (bounds == null) {
        continue;
      }
      final top = bounds.top - viewport.top;
      final bottom = bounds.bottom - viewport.top;
      if (bottom >= 0 && top <= viewport.height) {
        return index;
      }
    }
    return null;
  }

  Rect? _viewportGlobalBounds() {
    if (scrollController.hasClients) {
      final notificationContext =
          scrollController.position.context.notificationContext;
      final renderObject = notificationContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        final topLeft = renderObject.localToGlobal(Offset.zero);
        return topLeft & renderObject.size;
      }
    }
    final contextObject = context().findRenderObject();
    if (contextObject is RenderBox && contextObject.hasSize) {
      final topLeft = contextObject.localToGlobal(Offset.zero);
      return topLeft & contextObject.size;
    }
    return null;
  }

  Rect? _messageGlobalBounds(String messageId) {
    final messageContext = messageKeyFor(messageId).currentContext;
    final renderObject = messageContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    final topLeft = renderObject.localToGlobal(Offset.zero);
    return topLeft & renderObject.size;
  }

  double _nearEstimatedOffset({
    required double estimatedTargetOffset,
    required double step,
    required int attempt,
  }) {
    final direction = attempt.isOdd ? 1.0 : -1.0;
    final distance = ((attempt + 1) ~/ 2) * step;
    return estimatedTargetOffset + direction * distance;
  }

  bool _isUserScrollAwayActive() {
    final until = _userScrolledAwayUntil;
    if (until == null) {
      return false;
    }
    if (DateTime.now().isBefore(until)) {
      return true;
    }
    _userScrolledAwayUntil = null;
    return false;
  }

  void _updateState(ChatScreenViewportState nextState) {
    final changed = !identical(_state, nextState);
    _state = nextState;
    if (changed && isMounted()) {
      refresh();
    }
  }

  bool _shouldShowScrollToBottomButton() {
    if (!scrollController.hasClients) {
      return false;
    }
    final position = scrollController.position;
    return position.pixels > _scrollToBottomButtonThreshold;
  }
}
