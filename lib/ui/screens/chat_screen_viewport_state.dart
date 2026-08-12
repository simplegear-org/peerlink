class ChatScreenViewportState {
  final bool isLoadingMore;
  final bool initialPositionApplied;
  final bool initialPositionScheduled;
  final bool followBottomScheduled;
  final bool markReadScheduled;
  final bool isProgrammaticMessageJump;
  final bool showScrollToBottomButton;
  final String? unreadDividerMessageId;
  final String? highlightedMessageId;
  final int? lastLoadedOlderCount;

  const ChatScreenViewportState({
    this.isLoadingMore = false,
    this.initialPositionApplied = false,
    this.initialPositionScheduled = false,
    this.followBottomScheduled = false,
    this.markReadScheduled = false,
    this.isProgrammaticMessageJump = false,
    this.showScrollToBottomButton = false,
    this.unreadDividerMessageId,
    this.highlightedMessageId,
    this.lastLoadedOlderCount,
  });

  ChatScreenViewportState copyWith({
    bool? isLoadingMore,
    bool? initialPositionApplied,
    bool? initialPositionScheduled,
    bool? followBottomScheduled,
    bool? markReadScheduled,
    bool? isProgrammaticMessageJump,
    bool? showScrollToBottomButton,
    Object? unreadDividerMessageId = _sentinel,
    Object? highlightedMessageId = _sentinel,
    Object? lastLoadedOlderCount = _sentinel,
  }) {
    return ChatScreenViewportState(
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      initialPositionApplied:
          initialPositionApplied ?? this.initialPositionApplied,
      initialPositionScheduled:
          initialPositionScheduled ?? this.initialPositionScheduled,
      followBottomScheduled:
          followBottomScheduled ?? this.followBottomScheduled,
      markReadScheduled: markReadScheduled ?? this.markReadScheduled,
      isProgrammaticMessageJump:
          isProgrammaticMessageJump ?? this.isProgrammaticMessageJump,
      showScrollToBottomButton:
          showScrollToBottomButton ?? this.showScrollToBottomButton,
      unreadDividerMessageId: unreadDividerMessageId == _sentinel
          ? this.unreadDividerMessageId
          : unreadDividerMessageId as String?,
      highlightedMessageId: highlightedMessageId == _sentinel
          ? this.highlightedMessageId
          : highlightedMessageId as String?,
      lastLoadedOlderCount: lastLoadedOlderCount == _sentinel
          ? this.lastLoadedOlderCount
          : lastLoadedOlderCount as int?,
    );
  }
}

const Object _sentinel = Object();
