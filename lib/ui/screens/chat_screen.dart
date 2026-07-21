import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/runtime/avatar_service.dart';
import '../localization/app_strings.dart';
import '../models/chat.dart';
import '../models/message.dart';
import '../state/chat_controller.dart';
import '../state/chat_controller_models.dart';
import '../state/presence_service.dart';
import 'chat_screen_actions.dart';
import 'chat_screen_app_bar.dart';
import 'chat_screen_audio_actions.dart';
import 'chat_screen_back_swipe_coordinator.dart';
import 'chat_screen_composer_coordinator.dart';
import 'chat_screen_lifecycle.dart';
import 'chat_screen_media_actions.dart';
import 'chat_screen_message_list.dart';
import 'chat_screen_presenter.dart';
import 'chat_screen_scroll_coordinator.dart';
import 'package:peerlink/ui/screens/chat_screen_view.dart';

class ChatScreen extends StatefulWidget {
  final Chat chat;
  final ChatController controller;
  final PresenceService presenceService;
  final AvatarService avatarService;

  const ChatScreen({
    super.key,
    required this.chat,
    required this.controller,
    required this.presenceService,
    required this.avatarService,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  static const int _maxFileSize = 1024 * 1024 * 1024; // 1 GB
  static const double _backSwipeMinDistance = 88;
  static const double _backSwipeFastMinDistance = 48;
  static const double _backSwipeDirectionRatio = 1.15;
  static const double _backSwipeVelocity = 650;

  final TextEditingController textCtrl = TextEditingController();
  final ScrollController scrollCtrl = ScrollController();
  final ChatScreenAudioActions _audioActions = ChatScreenAudioActions();
  final ChatScreenMediaActions _mediaActions = const ChatScreenMediaActions();
  final ChatScreenActions _screenActions = const ChatScreenActions();
  late final ChatScreenBackSwipeCoordinator _backSwipeCoordinator;
  late final ChatScreenComposerCoordinator _composerCoordinator;
  late final ChatScreenScrollCoordinator _scrollCoordinator;
  late final ChatScreenLifecycle _lifecycle;
  late final ChatScreenPresenter _presenter;

  ChatConnectionStatus _status = ChatConnectionStatus.disconnected;
  String? _connectError;
  final GlobalKey _unreadDividerKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  bool get _isGroupChat => widget.chat.isGroup;
  bool get _isGroupOwner =>
      _isGroupChat &&
      widget.chat.ownerPeerId == widget.controller.facade.peerId;
  bool get _isCurrentUserInGroup =>
      !_isGroupChat ||
      widget.chat.memberPeerIds.contains(widget.controller.facade.peerId);

  @override
  void initState() {
    super.initState();
    textCtrl.addListener(_handleDraftChanged);
    scrollCtrl.addListener(_handleScroll);
    _backSwipeCoordinator = ChatScreenBackSwipeCoordinator(
      dismissKeyboardIfInputEmpty: _dismissKeyboardIfInputEmpty,
      pop: () => Navigator.maybePop(context),
    );
    _scrollCoordinator = ChatScreenScrollCoordinator(
      scrollController: scrollCtrl,
      unreadDividerKey: _unreadDividerKey,
      chat: () => widget.chat,
      controller: () => widget.controller,
      context: () => context,
      isMounted: () => mounted,
      refresh: _refreshState,
      messageKeyFor: _messageKeyFor,
      isInitialUnreadAnchor: _isInitialUnreadAnchor,
      showPlaceholder: _showPlaceholder,
    );
    _composerCoordinator = ChatScreenComposerCoordinator(
      textController: textCtrl,
      audioActions: _audioActions,
      mediaActions: _mediaActions,
      controller: () => widget.controller,
      chat: () => widget.chat,
      context: () => context,
      isMounted: () => mounted,
      refresh: _refreshState,
      scrollCoordinator: _scrollCoordinator,
      maxFileSize: _maxFileSize,
      isGroupChat: () => _isGroupChat,
      isCurrentUserInGroup: () => _isCurrentUserInGroup,
      showPlaceholder: _showPlaceholder,
    );
    _presenter = ChatScreenPresenter(
      chat: () => widget.chat,
      controller: () => widget.controller,
      presenceService: () => widget.presenceService,
      strings: () => context.strings,
      connectionStatus: () => _status,
      connectionError: () => _connectError,
      isGroupChat: () => _isGroupChat,
    );
    _status = widget.controller.connectionStatus(widget.chat.peerId);
    _connectError = widget.controller.connectionError(widget.chat.peerId);
    _lifecycle = ChatScreenLifecycle(
      chat: () => widget.chat,
      controller: () => widget.controller,
      presenceService: () => widget.presenceService,
      avatarService: () => widget.avatarService,
      context: () => context,
      isMounted: () => mounted,
      refresh: _refreshState,
      onConnectionSnapshotChanged: _updateConnectionSnapshot,
      scrollCoordinator: _scrollCoordinator,
      isGroupChat: () => _isGroupChat,
    );
    _lifecycle.start();
  }

  /// Обработчик прокрутки для ленивой загрузки
  void _handleScroll() {
    _scrollCoordinator.maybeLoadMoreMessages();
    _scrollCoordinator.syncScrollToBottomButton();
  }

  void _handleBackSwipePointerDown(PointerDownEvent event) {
    _backSwipeCoordinator.handlePointerDown(event);
  }

  void _handleBackSwipePointerMove(PointerEvent event) {
    _backSwipeCoordinator.handlePointerMove(event);
  }

  void _handleBackSwipePointerUp(PointerUpEvent event) {
    _backSwipeCoordinator.handlePointerUp(
      event,
      minDistance: _backSwipeMinDistance,
      fastMinDistance: _backSwipeFastMinDistance,
      directionRatio: _backSwipeDirectionRatio,
      minVelocity: _backSwipeVelocity,
    );
  }

  void _handleBackSwipePointerCancel(PointerCancelEvent event) {
    _backSwipeCoordinator.handlePointerCancel(event);
  }

  void _handleDraftChanged() {
    _composerCoordinator.handleDraftChanged();
  }

  Future<void> _handleVoicePressed() {
    return _audioActions.handleVoicePressed(
      context: context,
      isMounted: () => mounted,
      refresh: _refreshState,
    );
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  bool _isInitialUnreadAnchor(Message message) {
    return widget.controller.isInitialUnreadAnchor(message);
  }

  void _handleSendPressed() {
    _composerCoordinator.handleSendPressed();
  }

  void _setReplyTarget(Message message) {
    _composerCoordinator.setReplyTarget(message);
  }

  void _clearReplyTarget() {
    _composerCoordinator.clearReplyTarget();
  }

  void _handlePickFilePressed() {
    unawaited(_showAttachMenu());
  }

  Future<void> _startCall() async {
    if (_isGroupChat) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.groupCallsUnsupported)),
      );
      return;
    }
    try {
      await widget.controller.startCall(widget.chat.peerId);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.startCallError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final visibleMessages = widget.chat.messages;

    return Scaffold(
      appBar: ChatScreenAppBar(
        chat: widget.chat,
        avatarService: widget.avatarService,
        isGroupChat: _isGroupChat,
        isGroupOwner: _isGroupOwner,
        canAddChatContact: _presenter.canAddChatContact,
        subtitle: _isGroupChat
            ? strings.groupMembers(widget.chat.memberPeerIds.length)
            : _presenter.statusLabel(),
        onCallPressed: _isGroupChat
            ? null
            : () {
                unawaited(_startCall());
              },
        onAddContactPressed: _showAddContactDialog,
        onAddParticipantsPressed: _showAddParticipantsSheet,
        onRemoveParticipantsPressed: _showRemoveParticipantsSheet,
        onRenameGroupPressed: _showRenameGroupDialog,
        onSetAvatarPressed: _pickAndSetGroupAvatar,
        onDeleteChatPressed: _confirmDeleteChat,
      ),
      body: Column(
        children: [
          Expanded(
            child: ChatScreenMessageList(
              theme: Theme.of(context),
              strings: strings,
              scrollController: scrollCtrl,
              visibleMessages: visibleMessages,
              isLoadingMore: _scrollCoordinator.isLoadingMore,
              hasMoreMessages: widget.chat.hasMoreMessages,
              lastLoadedOlderCount: _scrollCoordinator.lastLoadedOlderCount,
              unreadDividerMessageId: _scrollCoordinator.unreadDividerMessageId,
              highlightedMessageId: _scrollCoordinator.highlightedMessageId,
              unreadDividerKey: _unreadDividerKey,
              messageKeyFor: _messageKeyFor,
              onPointerDown: _handleBackSwipePointerDown,
              onPointerMove: _handleBackSwipePointerMove,
              onPointerUp: _handleBackSwipePointerUp,
              onPointerCancel: _handleBackSwipePointerCancel,
              onScrollNotification: _handleMessageListScrollNotification,
              onScrollToBottomPressed: () {
                unawaited(_scrollCoordinator.handleScrollToBottomPressed());
              },
              senderLabelFor: _presenter.senderLabelFor,
              onReplySwipeFor: (message) =>
                  () => _setReplyTarget(message),
              onReplyTapFor: (message) => message.replyToMessageId == null
                  ? null
                  : () {
                      unawaited(
                        _scrollCoordinator.jumpToMessage(
                          message.replyToMessageId!,
                        ),
                      );
                    },
              onTapFor: (message) =>
                  message.kind == MessageKind.file && !message.isAudio
                  ? () {
                      _handleFileTap(message);
                    }
                  : null,
              onLongPressFor: (message) =>
                  message.isActiveOutgoingTransfer ||
                      !message.isQueuedOutgoingTransfer
                  ? () {
                      _confirmDeleteMessage(message);
                    }
                  : null,
              onQueueCancelFor: (message) => message.isQueuedOutgoingTransfer
                  ? () {
                      unawaited(
                        widget.controller.cancelFileTransfer(
                          widget.chat.peerId,
                          message.id,
                        ),
                      );
                    }
                  : null,
              showScrollToBottomButton:
                  _scrollCoordinator.showScrollToBottomButton,
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: _buildComposer(),
          ),
        ],
      ),
    );
  }

  void _dismissKeyboardIfInputEmpty() {
    if (textCtrl.text.trim().isNotEmpty) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void dispose() {
    _scrollCoordinator.dispose();
    _lifecycle.dispose();
    textCtrl.removeListener(_handleDraftChanged);
    textCtrl.dispose();
    scrollCtrl.removeListener(_handleScroll);
    scrollCtrl.dispose();
    unawaited(_audioActions.dispose());
    super.dispose();
  }

  bool _handleMessageListScrollNotification(ScrollNotification notification) {
    return _scrollCoordinator.handleMessageListScrollNotification(notification);
  }

  void _refreshState() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  void _updateConnectionSnapshot(
    ChatConnectionStatus status,
    String? connectError,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = status;
      _connectError = connectError;
    });
  }

  Future<void> _confirmDeleteMessage(Message message) async {
    await _screenActions.confirmDeleteMessage(
      context: context,
      controller: widget.controller,
      chat: widget.chat,
      message: message,
      shortPeerId: _presenter.shortPeerId,
      showAddContactDialog: _showAddContactDialog,
      saveMediaToGallery: _saveMediaToGallery,
      removeMessage: _removeMessage,
    );
  }

  Future<void> _showAddContactDialog(String peerId) async {
    await _screenActions.showAddContactDialog(
      context: context,
      controller: widget.controller,
      peerId: peerId,
    );
  }

  Future<void> _showAddParticipantsSheet() async {
    if (!_isGroupChat || !_isGroupOwner) {
      return;
    }
    await _screenActions.showAddParticipantsSheet(
      context: context,
      controller: widget.controller,
      chat: widget.chat,
    );
    _refreshState();
  }

  Future<void> _showRenameGroupDialog() async {
    if (!_isGroupChat || !_isGroupOwner) {
      return;
    }
    await _screenActions.showRenameGroupDialog(
      context: context,
      controller: widget.controller,
      chat: widget.chat,
    );
    _refreshState();
  }

  Future<void> _showRemoveParticipantsSheet() async {
    if (!_isGroupChat || !_isGroupOwner) {
      return;
    }
    await _screenActions.showRemoveParticipantsSheet(
      context: context,
      controller: widget.controller,
      chat: widget.chat,
      shortPeerId: _presenter.shortPeerId,
    );
    _refreshState();
  }

  Future<void> _handleFileTap(Message message) async {
    try {
      await _mediaActions.handleFileTap(
        context: context,
        chat: widget.chat,
        controller: widget.controller,
        message: message,
      );
    } catch (error, stackTrace) {
      developer.log(
        'file tap failed messageId=${message.id} error=$error',
        name: 'chat',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.downloadError)));
    }
  }

  Future<void> _confirmDeleteChat() async {
    await _screenActions.confirmDeleteChat(
      context: context,
      controller: widget.controller,
      chat: widget.chat,
      isGroupOwner: _isGroupOwner,
    );
  }

  Future<void> _showAttachMenu() async {
    final strings = context.strings;
    final action = await _screenActions.showAttachMenu(context: context);
    if (action == ChatAttachAction.gallery) {
      await _pickAndSendGalleryMedia();
      return;
    }
    if (action == ChatAttachAction.paste) {
      await _pasteFromClipboard();
      return;
    }
    if (action == ChatAttachAction.file) {
      _showPlaceholder(strings.fileSendingPlaceholder);
      return;
    }
    if (action == ChatAttachAction.location) {
      _showPlaceholder(strings.locationPlaceholder);
      return;
    }
  }

  void _showPlaceholder(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _removeMessage(String peerId, String messageId) async {
    await widget.controller.deleteMessage(peerId, messageId);
  }

  Future<void> _pickAndSendGalleryMedia() async {
    await _composerCoordinator.pickAndSendGalleryMedia();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) {
      return;
    }
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.clipboardEmpty)));
      return;
    }
    final current = textCtrl.value;
    final selection = current.selection;
    final start = selection.isValid ? selection.start : current.text.length;
    final end = selection.isValid ? selection.end : current.text.length;
    final normalizedStart = start < 0 ? current.text.length : start;
    final normalizedEnd = end < 0 ? current.text.length : end;
    final newText = current.text.replaceRange(
      normalizedStart,
      normalizedEnd,
      text,
    );
    final offset = normalizedStart + text.length;
    textCtrl.value = current.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: offset),
      composing: TextRange.empty,
    );
  }

  Future<void> _saveMediaToGallery(Message message) async {
    try {
      await _mediaActions.saveMediaToGallery(
        context: context,
        chat: widget.chat,
        controller: widget.controller,
        message: message,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.strings.savedToGallery)));
    } catch (error, stackTrace) {
      developer.log(
        'save media failed messageId=${message.id} error=$error',
        name: 'chat',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.saveMediaError(error))),
      );
    }
  }

  Widget _buildComposer() {
    return ChatComposer(
      textController: textCtrl,
      isSendingText: _composerCoordinator.isSendingText,
      isRecordingVoice: _audioActions.isRecordingVoice,
      hasStoppedRecording: _audioActions.hasStoppedRecording,
      recordingDuration: _audioActions.recordingDuration,
      replySenderLabel: _composerCoordinator.replyToMessage == null
          ? null
          : _presenter.replySenderLabelFor(
              _composerCoordinator.replyToMessage!,
            ),
      replyTextPreview: _composerCoordinator.replyToMessage == null
          ? null
          : _presenter.replyPreviewFor(_composerCoordinator.replyToMessage!),
      onAttachPressed: _handlePickFilePressed,
      onVoicePressed: _handleVoicePressed,
      onSendPressed: _handleSendPressed,
      onCancelReply: _clearReplyTarget,
    );
  }

  Future<void> _pickAndSetGroupAvatar() async {
    if (!_isGroupOwner || !_isGroupChat) {
      return;
    }
    await _screenActions.pickAndSetGroupAvatar(
      context: context,
      controller: widget.controller,
      groupId: widget.chat.peerId,
      selectedFileNameFallback: widget.chat.name,
      refresh: _refreshState,
    );
  }
}
