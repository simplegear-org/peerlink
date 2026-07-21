import 'package:flutter/material.dart';

import '../localization/app_strings.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import 'chat_screen_unread_divider.dart';

class ChatScreenMessageList extends StatelessWidget {
  final ThemeData theme;
  final AppStrings strings;
  final ScrollController scrollController;
  final List<Message> visibleMessages;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final int? lastLoadedOlderCount;
  final String? unreadDividerMessageId;
  final String? highlightedMessageId;
  final GlobalKey unreadDividerKey;
  final GlobalKey Function(String messageId) messageKeyFor;
  final void Function(PointerDownEvent event) onPointerDown;
  final void Function(PointerEvent event) onPointerMove;
  final void Function(PointerUpEvent event) onPointerUp;
  final void Function(PointerCancelEvent event) onPointerCancel;
  final bool Function(ScrollNotification notification) onScrollNotification;
  final VoidCallback onScrollToBottomPressed;
  final String? Function(Message message) senderLabelFor;
  final VoidCallback? Function(Message message) onReplySwipeFor;
  final VoidCallback? Function(Message message) onReplyTapFor;
  final VoidCallback? Function(Message message) onTapFor;
  final VoidCallback? Function(Message message) onLongPressFor;
  final VoidCallback? Function(Message message) onQueueCancelFor;
  final bool showScrollToBottomButton;

  const ChatScreenMessageList({
    super.key,
    required this.theme,
    required this.strings,
    required this.scrollController,
    required this.visibleMessages,
    required this.isLoadingMore,
    required this.hasMoreMessages,
    required this.lastLoadedOlderCount,
    required this.unreadDividerMessageId,
    required this.highlightedMessageId,
    required this.unreadDividerKey,
    required this.messageKeyFor,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerUp,
    required this.onPointerCancel,
    required this.onScrollNotification,
    required this.onScrollToBottomPressed,
    required this.senderLabelFor,
    required this.onReplySwipeFor,
    required this.onReplyTapFor,
    required this.onTapFor,
    required this.onLongPressFor,
    required this.onQueueCancelFor,
    required this.showScrollToBottomButton,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: onPointerDown,
      onPointerMove: onPointerMove,
      onPointerUp: onPointerUp,
      onPointerCancel: onPointerCancel,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: onScrollNotification,
            child: ListView(
              controller: scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              children: [
                if (!isLoadingMore &&
                    hasMoreMessages &&
                    visibleMessages.isNotEmpty)
                  _TopHint(theme: theme, text: strings.scrollUpToLoadOlder),
                if (isLoadingMore)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final message in visibleMessages)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (unreadDividerMessageId == message.id)
                        KeyedSubtree(
                          key: unreadDividerKey,
                          child: const ChatScreenUnreadDivider(),
                        ),
                      KeyedSubtree(
                        key: messageKeyFor(message.id),
                        child: MessageBubble(
                          message: message,
                          senderLabel: senderLabelFor(message),
                          onReplySwipe: onReplySwipeFor(message),
                          onReplyTap: onReplyTapFor(message),
                          isHighlighted: highlightedMessageId == message.id,
                          onTap: onTapFor(message),
                          onLongPress: onLongPressFor(message),
                          onQueueCancel: onQueueCancelFor(message),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (lastLoadedOlderCount != null)
            _LoadedOlderBanner(theme: theme, count: lastLoadedOlderCount!),
          if (!hasMoreMessages && visibleMessages.isNotEmpty)
            _FirstMessagesBanner(
              theme: theme,
              text: strings.firstMessages,
              top: lastLoadedOlderCount != null ? 42 : 8,
            ),
          _ScrollToBottomButton(
            show: showScrollToBottomButton,
            onTap: onScrollToBottomPressed,
          ),
        ],
      ),
    );
  }
}

class _TopHint extends StatelessWidget {
  final ThemeData theme;
  final String text;

  const _TopHint({required this.theme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.paper.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.stroke),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppTheme.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadedOlderBanner extends StatelessWidget {
  final ThemeData theme;
  final int count;

  const _LoadedOlderBanner({required this.theme, required this.count});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 180),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                context.strings.loadedOlderMessages(count),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FirstMessagesBanner extends StatelessWidget {
  final ThemeData theme;
  final String text;
  final double top;

  const _FirstMessagesBanner({
    required this.theme,
    required this.text,
    required this.top,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.paper.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.muted),
          ),
        ),
      ),
    );
  }
}

class _ScrollToBottomButton extends StatelessWidget {
  final bool show;
  final VoidCallback onTap;

  const _ScrollToBottomButton({required this.show, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedScale(
            scale: show ? 1 : 0.88,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: Material(
              color: AppTheme.accent,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.24),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: const SizedBox(
                  width: 46,
                  height: 46,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
