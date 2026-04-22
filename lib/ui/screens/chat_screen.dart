import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:record/record.dart';

import '../models/chat.dart';
import '../models/message.dart';
import '../state/avatar_service.dart';
import '../state/chat_controller.dart';
import '../state/presence_service.dart';
import 'package:peerlink/ui/screens/chat_screen_view.dart';
import 'avatar_crop_screen.dart';
import 'chat_screen_media_actions.dart';
import 'chat_screen_helpers.dart';
import 'chat_screen_unread_divider.dart';
import '../theme/app_theme.dart';
import '../widgets/message_bubble.dart';
import '../widgets/peer_avatar.dart';

enum _MessageAction { addContact, deleteLocal, deleteEveryone }

enum _AttachAction {
  gallery,
  file,
  location,
}

enum _ChatMenuAction {
  addParticipants,
  removeParticipants,
  renameGroup,
  setAvatar,
  deleteChat,
}

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
  static const double _loadMoreThreshold = 120;
  final TextEditingController textCtrl = TextEditingController();
  final ScrollController scrollCtrl = ScrollController();
  final AudioRecorder _audioRecorder = AudioRecorder();
  final ChatScreenMediaActions _mediaActions = const ChatScreenMediaActions();

  ChatConnectionStatus _status = ChatConnectionStatus.disconnected;
  String? _connectError;
  bool _isLoadingMore = false;
  bool _isSendingText = false;
  bool _isRecordingVoice = false;
  bool _initialPositionApplied = false;
  String? _unreadDividerMessageId;
  String? _recordingPath;
  String? _stoppedRecordingPath;
  Message? _replyToMessage;
  String? _highlightedMessageId;
  Timer? _highlightClearTimer;
  int? _lastLoadedOlderCount;
  Timer? _loadMoreNoticeTimer;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  Timer? _presenceRefreshTimer;
  final GlobalKey _unreadDividerKey = GlobalKey();
  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<String>? _presenceSubscription;
  StreamSubscription<String>? _avatarSubscription;
  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};
  bool get _isGroupChat => widget.chat.isGroup;
  bool get _isGroupOwner =>
      _isGroupChat && widget.chat.ownerPeerId == widget.controller.facade.peerId;
  bool get _isCurrentUserInGroup =>
      !_isGroupChat || widget.chat.memberPeerIds.contains(widget.controller.facade.peerId);


  @override
  void initState() {
    super.initState();
    textCtrl.addListener(_handleDraftChanged);
    scrollCtrl.addListener(_handleScroll);
    _status = widget.controller.connectionStatus(widget.chat.peerId);
    _connectError = widget.controller.connectionError(widget.chat.peerId);

    _statusSubscription = widget.controller.connectionStatusStream.listen(
      (peerId) {
        try {
          if (peerId != widget.chat.peerId || !mounted) {
            return;
          }
          setState(() {
            _status = widget.controller.connectionStatus(peerId);
            _connectError = widget.controller.connectionError(peerId);
          });
        } catch (e, stack) {
          developer.log('[chat_ui] status listener failed: $e\n$stack', name: 'chat');
        }
      },
    );

    _messageSubscription = widget.controller.messageUpdatesStream.listen(
      (peerId) {
        try {
          if (peerId != widget.chat.peerId || !mounted) {
            return;
          }
          setState(() {});
          if (_initialPositionApplied) {
            unawaited(_safeMarkChatAsRead());
          } else {
            _scheduleInitialViewport();
          }
        } catch (e, stack) {
          developer.log('[chat_ui] message listener failed: $e\n$stack', name: 'chat');
        }
      },
    );

    unawaited(widget.controller.ensureChatLoaded(widget.chat.peerId));

    if (!_isGroupChat) {
      _presenceSubscription = widget.presenceService.updatesStream.listen((peerId) {
        if (peerId != widget.chat.peerId || !mounted) {
          return;
        }
        setState(() {});
      });
      _avatarSubscription = widget.avatarService.updatesStream.listen((peerId) {
        if (peerId != widget.chat.peerId || !mounted) {
          return;
        }
        setState(() {});
      });
      _presenceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _scheduleInitialViewport();
    });
  }

  /// Обработчик прокрутки для ленивой загрузки
  void _handleScroll() {
    _maybeLoadMoreMessages();
  }

  void _maybeLoadMoreMessages() {
    if (_isLoadingMore || !scrollCtrl.hasClients) {
      return;
    }

    final chat = widget.chat;
    if (!chat.hasMoreMessages || !chat.messagesLoaded) {
      return;
    }

    final position = scrollCtrl.position;
    if (position.extentBefore <= _loadMoreThreshold ||
        position.pixels <= _loadMoreThreshold) {
      developer.log(
        '[chat_ui] loadMore trigger peer=${widget.chat.peerId} '
        'pixels=${position.pixels.toStringAsFixed(1)} '
        'extentBefore=${position.extentBefore.toStringAsFixed(1)} '
        'max=${position.maxScrollExtent.toStringAsFixed(1)} '
        'loaded=${widget.chat.messages.length} '
        'hasMore=${widget.chat.hasMoreMessages}',
        name: 'chat',
      );
      unawaited(_loadMoreMessages());
    }
  }

  /// Загружает больше сообщений
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;

    final previousLoadedCount = widget.chat.messages.length;
    final previousPixels = scrollCtrl.hasClients ? scrollCtrl.position.pixels : 0.0;
    final previousMaxScrollExtent = scrollCtrl.hasClients
        ? scrollCtrl.position.maxScrollExtent
        : 0.0;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      developer.log(
        '[chat_ui] loadMore start peer=${widget.chat.peerId} '
        'loaded=${widget.chat.messages.length} '
        'hasMore=${widget.chat.hasMoreMessages}',
        name: 'chat',
      );
      final loaded = await widget.controller.loadMoreMessages(widget.chat.peerId);
      final addedCount = widget.chat.messages.length - previousLoadedCount;
      developer.log(
        '[chat_ui] loadMore result peer=${widget.chat.peerId} '
        'loadedResult=$loaded '
        'added=$addedCount '
        'loadedNow=${widget.chat.messages.length} '
        'hasMoreNow=${widget.chat.hasMoreMessages}',
        name: 'chat',
      );
      if (loaded && mounted) {
        _loadMoreNoticeTimer?.cancel();
        setState(() {
          _lastLoadedOlderCount = addedCount > 0 ? addedCount : null;
        });
        if (addedCount > 0) {
          _loadMoreNoticeTimer = Timer(const Duration(seconds: 2), () {
            if (!mounted) {
              return;
            }
            setState(() {
              _lastLoadedOlderCount = null;
            });
          });
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            if (scrollCtrl.hasClients) {
              final newMaxScrollExtent = scrollCtrl.position.maxScrollExtent;
              final delta = newMaxScrollExtent - previousMaxScrollExtent;
              final targetOffset = (previousPixels + delta).clamp(
                0.0,
                newMaxScrollExtent,
              );
              scrollCtrl.jumpTo(targetOffset);
              _maybeLoadMoreMessages();
            }
          } catch (e, stack) {
            developer.log('[chat_ui] loadMore scroll restore failed: $e\n$stack', name: 'chat');
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to load more messages: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  Future<void> _send() async {
    if (_isGroupChat && !_isCurrentUserInGroup) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Вы больше не участник этого чата.')),
        );
      }
      return;
    }

    // If we have a stopped recording, send it
    if (_stoppedRecordingPath != null) {
      await _sendVoiceRecording();
      return;
    }

    if (_isSendingText) {
      return;
    }

    final text = textCtrl.text.trim();
    if (text.isEmpty) {
      return;
    }

    textCtrl.clear();
    if (mounted) {
      setState(() {
        _isSendingText = true;
      });
    }

    try {
      await widget.controller.sendMessage(
        widget.chat.peerId,
        text,
        replyTo: _replyToMessage,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSendingText = false;
        });
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {});
    _clearReplyTarget();
    _jumpToBottom();
  }

  void _handleDraftChanged() {
    try {
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (e, stack) {
      developer.log('[chat_ui] draft listener failed: $e\n$stack', name: 'chat');
    }
  }

  Future<void> _handleVoicePressed() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    try {
      final hasPermission = await _audioRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону.')),
        );
        return;
      }

      final path =
          '${Directory.systemTemp.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_isRecordingVoice) {
          return;
        }
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      });

      if (!mounted) {
        return;
      }
      setState(() {
        _isRecordingVoice = true;
        _recordingPath = path;
        _recordingDuration = Duration.zero;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось начать запись: $e')),
      );
    }
  }

  Future<void> _stopVoiceRecording() async {
    _recordingTimer?.cancel();
    _recordingTimer = null;

    try {
      final stoppedPath = await _audioRecorder.stop();
      final recordedPath = stoppedPath ?? _recordingPath;

      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _recordingPath = null;
          _stoppedRecordingPath = recordedPath;
        });
      }

      if (recordedPath == null || recordedPath.isEmpty) {
        return;
      }

      final file = File(recordedPath);
      if (!await file.exists()) {
        return;
      }

      final size = await file.length();
      if (size <= 0) {
        try {
          await file.delete();
        } catch (_) {
          // Ignore cleanup failure for empty recording.
        }
        if (mounted) {
          setState(() {
            _stoppedRecordingPath = null;
          });
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isRecordingVoice = false;
          _recordingPath = null;
          _stoppedRecordingPath = null;
        });
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось остановить запись: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _recordingDuration = Duration.zero;
        });
      } else {
        _recordingDuration = Duration.zero;
      }
    }
  }

  Future<void> _sendVoiceRecording() async {
    final recordedPath = _stoppedRecordingPath;
    if (recordedPath == null || recordedPath.isEmpty) {
      return;
    }

    final file = File(recordedPath);
    if (!await file.exists()) {
      if (mounted) {
        setState(() {
          _stoppedRecordingPath = null;
        });
      }
      return;
    }

    try {
      final size = await file.length();
      final fileName = 'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await widget.controller.sendFile(
        widget.chat.peerId,
        fileName: fileName,
        filePath: recordedPath,
        fileSizeBytes: size,
        mimeType: 'audio/mp4',
        replyTo: _replyToMessage,
      );

      if (mounted) {
        setState(() {
          _stoppedRecordingPath = null;
        });
      }
      _clearReplyTarget();
      _jumpToBottom();
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить голосовое: $e')),
      );
    }
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  Future<BuildContext?> _resolveMessageContext({
    required String messageId,
    required int targetIndex,
  }) async {
    final targetKey = _messageKeyFor(messageId);
    BuildContext? targetContext = targetKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      return targetContext;
    }

    if (!scrollCtrl.hasClients || widget.chat.messages.isEmpty) {
      return null;
    }

    Future<void> waitForLayout() async {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }

    final ratio = widget.chat.messages.length <= 1
        ? 0.0
        : targetIndex / (widget.chat.messages.length - 1);
    final position = scrollCtrl.position;
    final targetOffset = position.maxScrollExtent * ratio;
    final viewport = position.viewportDimension;
    final candidateOffsets = <double>[
      targetOffset,
      targetOffset - (viewport * 0.5),
      targetOffset + (viewport * 0.5),
      targetOffset - viewport,
      targetOffset + viewport,
      targetOffset - (viewport * 1.5),
      targetOffset + (viewport * 1.5),
      targetOffset - (viewport * 2),
      targetOffset + (viewport * 2),
      0,
      position.maxScrollExtent,
    ];

    for (final candidate in candidateOffsets) {
      if (!mounted || !scrollCtrl.hasClients) {
        return null;
      }
      final clamped = candidate.clamp(0.0, scrollCtrl.position.maxScrollExtent);
      developer.log(
        '[chat_ui] jumpToMessage probe peer=${widget.chat.peerId} '
        'messageId=$messageId targetIndex=$targetIndex offset=$clamped',
        name: 'chat',
      );
      scrollCtrl.jumpTo(clamped);
      await waitForLayout();
      targetContext = targetKey.currentContext;
      if (targetContext != null && targetContext.mounted) {
        return targetContext;
      }
    }

    if (!mounted) {
      return null;
    }
    setState(() {});
    await waitForLayout();
    targetContext = targetKey.currentContext;
    if (targetContext != null && targetContext.mounted) {
      return targetContext;
    }

    return null;
  }

  Future<void> _jumpToMessage(String messageId) async {
    final targetOffsetFromNewest = await widget.controller.messageOffsetFromNewest(
      widget.chat.peerId,
      messageId,
    );
    developer.log(
      '[chat_ui] jumpToMessage start peer=${widget.chat.peerId} '
      'messageId=$messageId loaded=${widget.chat.messages.length} '
      'hasMore=${widget.chat.hasMoreMessages} targetOffset=$targetOffsetFromNewest',
      name: 'chat',
    );

    if (targetOffsetFromNewest == null) {
      _showPlaceholder('Исходное сообщение не найдено в локальной истории.');
      return;
    }

    const maxLoadAttempts = 64;
    var loadAttempts = 0;
    while (!widget.chat.messages.any((message) => message.id == messageId) &&
        widget.chat.hasMoreMessages &&
        widget.chat.messages.length <= targetOffsetFromNewest &&
        loadAttempts < maxLoadAttempts) {
      developer.log(
        '[chat_ui] jumpToMessage loading older peer=${widget.chat.peerId} '
        'messageId=$messageId attempt=${loadAttempts + 1} '
        'loaded=${widget.chat.messages.length} targetOffset=$targetOffsetFromNewest',
        name: 'chat',
      );
      await _loadMoreMessages();
      loadAttempts++;
      if (!mounted) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }

    while (!widget.chat.messages.any((message) => message.id == messageId) &&
        widget.chat.hasMoreMessages &&
        loadAttempts < maxLoadAttempts) {
      developer.log(
        '[chat_ui] jumpToMessage fallback loading peer=${widget.chat.peerId} '
        'messageId=$messageId attempt=${loadAttempts + 1} '
        'loaded=${widget.chat.messages.length}',
        name: 'chat',
      );
      await _loadMoreMessages();
      loadAttempts++;
      if (!mounted) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }

    final targetIndex = widget.chat.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (targetIndex == -1) {
      developer.log(
        '[chat_ui] jumpToMessage failed-not-loaded peer=${widget.chat.peerId} '
        'messageId=$messageId loaded=${widget.chat.messages.length} '
        'hasMore=${widget.chat.hasMoreMessages} attempts=$loadAttempts '
        'targetOffset=$targetOffsetFromNewest',
        name: 'chat',
      );
      _showPlaceholder('Исходное сообщение не найдено в текущей истории.');
      return;
    }

    final targetContext = await _resolveMessageContext(
      messageId: messageId,
      targetIndex: targetIndex,
    );

    if (targetContext == null || !targetContext.mounted) {
      developer.log(
        '[chat_ui] jumpToMessage failed-no-context peer=${widget.chat.peerId} '
        'messageId=$messageId targetIndex=$targetIndex loaded=${widget.chat.messages.length}',
        name: 'chat',
      );
      _showPlaceholder('Не удалось перейти к исходному сообщению.');
      return;
    }

    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.35,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );

    if (!mounted) {
      return;
    }
    _highlightClearTimer?.cancel();
    setState(() {
      _highlightedMessageId = messageId;
    });
    _highlightClearTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      setState(() {
        if (_highlightedMessageId == messageId) {
          _highlightedMessageId = null;
        }
      });
    });
  }

  void _scheduleInitialViewport() {
    if (_initialPositionApplied || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted || _initialPositionApplied) {
          return;
        }

        final visibleMessages = widget.chat.messages;
        if (visibleMessages.isEmpty) {
          return;
        }

        _unreadDividerMessageId ??= _firstUnreadMessageId(visibleMessages);
        if (_unreadDividerMessageId == null) {
          _jumpToBottom();
        } else {
          final dividerContext = _unreadDividerKey.currentContext;
          if (dividerContext != null) {
            await Scrollable.ensureVisible(
              dividerContext,
              alignment: 0.5,
              duration: Duration.zero,
            );
          } else if (scrollCtrl.hasClients && visibleMessages.isNotEmpty) {
            final targetIndex = visibleMessages.indexWhere(
              (message) => message.id == _unreadDividerMessageId,
            );
            final safeIndex = targetIndex == -1 ? 0 : targetIndex;
            final ratio = visibleMessages.length <= 1
                ? 0.0
                : safeIndex / (visibleMessages.length - 1);
            final offset = scrollCtrl.position.maxScrollExtent * ratio;
            scrollCtrl.jumpTo(
              offset.clamp(0.0, scrollCtrl.position.maxScrollExtent),
            );
          }
        }

        _initialPositionApplied = true;
        await _safeMarkChatAsRead();
      } catch (e, stack) {
        developer.log('[chat_ui] initial viewport failed: $e\n$stack', name: 'chat');
      }
    });
  }

  Future<void> _safeMarkChatAsRead() async {
    try {
      await widget.controller.markChatAsRead(widget.chat.peerId);
    } catch (e, stack) {
      developer.log('[chat_ui] markChatAsRead failed: $e\n$stack', name: 'chat');
    }
  }

  String? _firstUnreadMessageId(List<Message> messages) {
    for (final message in messages) {
      if (message.incoming && !message.isRead) {
        return message.id;
      }
    }
    return null;
  }

  String _shortPeerId(String peerId) {
    if (peerId.length <= 8) {
      return peerId;
    }
    return '${peerId.substring(0, 4)}...${peerId.substring(peerId.length - 4)}';
  }

  String? _senderLabelFor(Message message) {
    if (!_isGroupChat || !message.incoming) {
      return null;
    }
    final senderPeerId = message.senderPeerId;
    if (senderPeerId == null || senderPeerId.trim().isEmpty) {
      return null;
    }
    final contactName = widget.controller.contactNameForPeer(senderPeerId);
    if (contactName != null && contactName.trim().isNotEmpty) {
      return contactName;
    }
    return _shortPeerId(senderPeerId);
  }

  void _handleSendPressed() {
    unawaited(_send());
  }

  void _setReplyTarget(Message message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _replyToMessage = message;
    });
  }

  void _clearReplyTarget() {
    if (!mounted) {
      return;
    }
    setState(() {
      _replyToMessage = null;
    });
  }

  String? _replySenderLabelFor(Message message) {
    if (!message.incoming) {
      return 'Вы';
    }
    if (_isGroupChat) {
      return _senderLabelFor(message) ??
          _shortPeerId(message.senderPeerId ?? message.peerId);
    }
    return widget.chat.name;
  }

  String _replyPreviewFor(Message message) {
    if (message.kind == MessageKind.file) {
      if (message.isAudio) {
        return 'Голосовое сообщение';
      }
      if (message.isImage) {
        return 'Фото';
      }
      if (message.isVideo) {
        return 'Видео';
      }
      return message.fileName?.trim().isNotEmpty == true
          ? message.fileName!
          : 'Файл';
    }
    final text = message.text.trim();
    if (text.isEmpty) {
      return 'Сообщение';
    }
    return text;
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
        const SnackBar(content: Text('Групповые звонки пока не поддерживаются.')),
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
        SnackBar(content: Text('Не удалось начать звонок: $e')),
      );
    }
  }

  Future<void> _pickAndSetGroupAvatar() async {
    if (!_isGroupOwner || !_isGroupChat) {
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final selected = result.files.first;
    Uint8List? bytes = selected.bytes;
    if (bytes == null || bytes.isEmpty) {
      final path = selected.path;
      if (path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      }
    }
    if (!mounted || bytes == null || bytes.isEmpty) {
      return;
    }

    final cropped = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => AvatarCropScreen(sourceBytes: bytes!),
      ),
    );
    if (!mounted || cropped == null || cropped.isEmpty) {
      return;
    }

    try {
      await widget.controller.setGroupAvatar(
        groupId: widget.chat.peerId,
        bytes: cropped,
        mimeType: _mimeTypeForPath(selected.name),
      );
      if (!mounted) {
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Аватар чата обновлен')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить аватар: $error')),
      );
    }
  }

  String _mimeTypeForPath(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<Message> messages = widget.chat.messages;
    final List<Message> visibleMessages = messages;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            PeerAvatar(
              peerId: widget.chat.peerId,
              displayName: widget.chat.name,
              avatarService: widget.avatarService,
              imagePath: _isGroupChat ? widget.chat.avatarPath : null,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.chat.name),
                  Text(
                    _isGroupChat
                        ? 'Участников: ${widget.chat.memberPeerIds.length}'
                        : _statusLabel(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          ],
        ),
        actions: [
          if (!_isGroupChat)
            IconButton(
              icon: const Icon(Icons.call_rounded),
              onPressed: () {
                unawaited(_startCall());
              },
            ),
          PopupMenuButton<_ChatMenuAction>(
            onSelected: (action) {
              switch (action) {
                case _ChatMenuAction.addParticipants:
                  unawaited(_showAddParticipantsSheet());
                  break;
                case _ChatMenuAction.removeParticipants:
                  unawaited(_showRemoveParticipantsSheet());
                  break;
                case _ChatMenuAction.renameGroup:
                  unawaited(_showRenameGroupDialog());
                  break;
                case _ChatMenuAction.setAvatar:
                  unawaited(_pickAndSetGroupAvatar());
                  break;
                case _ChatMenuAction.deleteChat:
                  unawaited(_confirmDeleteChat());
                  break;
              }
            },
            itemBuilder: (context) => [
              if (_isGroupOwner)
                const PopupMenuItem(
                  value: _ChatMenuAction.addParticipants,
                  child: Text('Добавить участников'),
                ),
              if (_isGroupOwner)
                const PopupMenuItem(
                  value: _ChatMenuAction.removeParticipants,
                  child: Text('Удалить участников'),
                ),
              if (_isGroupOwner)
                const PopupMenuItem(
                  value: _ChatMenuAction.renameGroup,
                  child: Text('Сменить имя чата'),
                ),
              if (_isGroupOwner)
                const PopupMenuItem(
                  value: _ChatMenuAction.setAvatar,
                  child: Text('Добавить аватар'),
                ),
              const PopupMenuItem(
                value: _ChatMenuAction.deleteChat,
                child: Text('Удалить диалог'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _dismissKeyboardIfInputEmpty(),
              child: Stack(
                children: [
                  NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.axis == Axis.vertical) {
                        if (_lastLoadedOlderCount != null &&
                            notification is ScrollUpdateNotification &&
                            notification.metrics.axisDirection == AxisDirection.down) {
                          setState(() {
                            _lastLoadedOlderCount = null;
                          });
                        }
                        _maybeLoadMoreMessages();
                      }
                      return false;
                    },
                    child: ListView(
                      controller: scrollCtrl,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                      children: [
                    if (!_isLoadingMore &&
                        widget.chat.hasMoreMessages &&
                        visibleMessages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.paper.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.stroke,
                              ),
                            ),
                            child: Text(
                              'Прокрутите выше, чтобы загрузить предыдущие сообщения',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isLoadingMore)
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
                          if (_unreadDividerMessageId != null &&
                              _unreadDividerMessageId == message.id)
                            KeyedSubtree(
                              key: _unreadDividerKey,
                              child: const ChatScreenUnreadDivider(),
                            ),
                            KeyedSubtree(
                            key: _messageKeyFor(message.id),
                            child: MessageBubble(
                              message: message,
                              senderLabel: _senderLabelFor(message),
                              onReplySwipe: () => _setReplyTarget(message),
                              onReplyTap: message.replyToMessageId == null
                                  ? null
                                  : () => unawaited(
                                        _jumpToMessage(message.replyToMessageId!),
                                      ),
                              isHighlighted: _highlightedMessageId == message.id,
                              onTap: message.kind == MessageKind.file && !message.isAudio
                                  ? () {
                                    _handleFileTap(message);
                                  }
                                : null,
                              onLongPress: message.isActiveOutgoingTransfer ||
                                      !message.isQueuedOutgoingTransfer
                                  ? () {
                                      _confirmDeleteMessage(message);
                                    }
                                  : null,
                              onQueueCancel: message.isQueuedOutgoingTransfer
                                  ? () {
                                      unawaited(
                                        widget.controller.cancelFileTransfer(
                                          widget.chat.peerId,
                                          message.id,
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      ],
                    ),
                  ),
                  if (_lastLoadedOlderCount != null)
                    Positioned(
                      top: 8,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: AnimatedOpacity(
                            opacity: _lastLoadedOlderCount == null ? 0 : 1,
                            duration: const Duration(milliseconds: 180),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accent.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Загружено $_lastLoadedOlderCount предыдущих сообщений',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!widget.chat.hasMoreMessages && visibleMessages.isNotEmpty)
                    Positioned(
                      top: _lastLoadedOlderCount != null ? 42 : 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.paper.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Это самые первые сообщения',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppTheme.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
    _recordingTimer?.cancel();
    _highlightClearTimer?.cancel();
    _loadMoreNoticeTimer?.cancel();
    textCtrl.removeListener(_handleDraftChanged);
    textCtrl.dispose();
    scrollCtrl.removeListener(_handleScroll);
    scrollCtrl.dispose();
    _statusSubscription?.cancel();
    _messageSubscription?.cancel();
    _presenceSubscription?.cancel();
    _avatarSubscription?.cancel();
    _presenceRefreshTimer?.cancel();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }

  Future<void> _confirmDeleteMessage(Message message) async {
    if (message.isPendingOutgoingTransfer) {
      final shouldCancel = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (context) {
          final theme = Theme.of(context);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Отменить отправку',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Файл будет снят с очереди отправки.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cancel_outlined),
                    title: const Text('Отменить отправку'),
                    onTap: () {
                      Navigator.of(context).pop(true);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.close_rounded),
                    title: const Text('Отмена'),
                    onTap: () {
                      Navigator.of(context).pop(false);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (shouldCancel == true) {
        unawaited(
          widget.controller.cancelFileTransfer(widget.chat.peerId, message.id),
        );
      }
      return;
    }

    final senderPeerId = (message.senderPeerId ?? message.peerId).trim();
    final canAddContact = message.incoming &&
        senderPeerId.isNotEmpty &&
        widget.controller.contactNameForPeer(senderPeerId) == null;

    final action = await showModalBottomSheet<_MessageAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        final canDeleteEverywhere = !message.incoming;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Удалить сообщение',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Удалите сообщение только у себя или попросите собеседника убрать его тоже.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 18),
                if (canAddContact)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_add_alt_1_rounded),
                    title: const Text('Добавить контакт'),
                    onTap: () {
                      Navigator.of(context).pop(_MessageAction.addContact);
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Удалить только у себя'),
                  onTap: () {
                    Navigator.of(context).pop(_MessageAction.deleteLocal);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_rounded),
                  title: const Text('Удалить у всех'),
                  enabled: canDeleteEverywhere,
                  subtitle: canDeleteEverywhere
                      ? null
                      : const Text('Только автор может удалить у собеседника'),
                  onTap: canDeleteEverywhere
                      ? () {
                          Navigator.of(context).pop(_MessageAction.deleteEveryone);
                        }
                      : null,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Отмена'),
                  onTap: () {
                    Navigator.of(context).pop(null);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    if (action == _MessageAction.addContact) {
      await _showAddContactDialog(senderPeerId);
      return;
    }

    await _removeMessage(widget.chat.peerId, message.id);
    if (action == _MessageAction.deleteEveryone) {
      unawaited(
        widget.controller.requestDeleteForEveryone(widget.chat.peerId, message.id),
      );
    }
  }

  Future<void> _showAddContactDialog(String peerId) async {
    final nameCtrl = TextEditingController();
    final enteredName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Добавить контакт'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Имя контакта',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(nameCtrl.text.trim()),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );

    final name = enteredName?.trim() ?? '';
    if (name.isEmpty) {
      return;
    }
    await widget.controller.addOrUpdateContact(peerId: peerId, name: name);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Контакт "$name" добавлен.')),
    );
  }

  Future<void> _showAddParticipantsSheet() async {
    if (!_isGroupChat || !_isGroupOwner) {
      return;
    }

    final available = widget.controller
        .getContacts()
        .where((contact) => !widget.chat.memberPeerIds.contains(contact.peerId))
        .toList(growable: false);
    if (available.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет контактов для добавления.')),
      );
      return;
    }

    final selectedPeerIds = <String>{};
    final toAdd = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Добавить участников',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: available.length,
                        itemBuilder: (context, index) {
                          final contact = available[index];
                          final selected = selectedPeerIds.contains(contact.peerId);
                          return CheckboxListTile(
                            value: selected,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(contact.name),
                            subtitle: Text(contact.shortId()),
                            onChanged: (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selectedPeerIds.add(contact.peerId);
                                } else {
                                  selectedPeerIds.remove(contact.peerId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: selectedPeerIds.isEmpty
                                ? null
                                : () => Navigator.pop(
                                      context,
                                      selectedPeerIds.toList(growable: false),
                                    ),
                            child: const Text('Добавить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (toAdd == null || toAdd.isEmpty) {
      return;
    }
    await widget.controller.addGroupParticipants(
      groupId: widget.chat.peerId,
      participantPeerIds: toAdd,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Участники добавлены.')),
    );
  }

  Future<void> _showRenameGroupDialog() async {
    if (!_isGroupChat || !_isGroupOwner) {
      return;
    }
    final ctrl = TextEditingController(text: widget.chat.name);
    final nextName = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Сменить имя чата'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Имя чата',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    final name = nextName?.trim() ?? '';
    if (name.isEmpty || name == widget.chat.name) {
      return;
    }
    await widget.controller.renameGroupChat(
      groupId: widget.chat.peerId,
      newName: name,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _showRemoveParticipantsSheet() async {
    if (!_isGroupChat || !_isGroupOwner) {
      return;
    }

    final removablePeerIds = widget.chat.memberPeerIds
        .where((peerId) =>
            peerId != widget.controller.facade.peerId &&
            peerId != widget.chat.ownerPeerId)
        .toList(growable: false);
    if (removablePeerIds.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет участников для удаления.')),
      );
      return;
    }

    final selected = <String>{};
    final toRemove = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Удалить участников',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 280,
                      child: ListView.builder(
                        itemCount: removablePeerIds.length,
                        itemBuilder: (context, index) {
                          final peerId = removablePeerIds[index];
                          final name = widget.controller.contactNameForPeer(peerId) ??
                              _shortPeerId(peerId);
                          final checked = selected.contains(peerId);
                          return CheckboxListTile(
                            value: checked,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text(name),
                            subtitle: Text(_shortPeerId(peerId)),
                            onChanged: (value) {
                              setLocalState(() {
                                if (value == true) {
                                  selected.add(peerId);
                                } else {
                                  selected.remove(peerId);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: selected.isEmpty
                                ? null
                                : () => Navigator.pop(
                                      context,
                                      selected.toList(growable: false),
                                    ),
                            child: const Text('Удалить'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (toRemove == null || toRemove.isEmpty) {
      return;
    }
    await widget.controller.removeGroupParticipants(
      groupId: widget.chat.peerId,
      participantPeerIds: toRemove,
    );
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Участники удалены.')),
    );
  }

  Future<void> _handleFileTap(Message message) {
    return _mediaActions.handleFileTap(
      context: context,
      chat: widget.chat,
      controller: widget.controller,
      message: message,
    );
  }

  Future<void> _confirmDeleteChat() async {
    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Удалить диалог',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Весь диалог будет удалён локально, включая медиафайлы.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.muted,
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_forever_rounded),
                  title: const Text('Удалить диалог'),
                  onTap: () {
                    Navigator.of(context).pop(true);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Отмена'),
                  onTap: () {
                    Navigator.of(context).pop(false);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldDelete == true) {
      await widget.controller.deleteChat(widget.chat.peerId);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _showAttachMenu() async {
    final action = await showModalBottomSheet<_AttachAction>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('Галерея'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachAction.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.attach_file_rounded),
                  title: const Text('Файл'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachAction.file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Геопозиция'),
                  onTap: () {
                    Navigator.of(context).pop(_AttachAction.location);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded),
                  title: const Text('Отмена'),
                  onTap: () {
                    Navigator.of(context).pop(null);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == _AttachAction.gallery) {
      await _pickAndSendGalleryMedia();
      return;
    }

    if (action == _AttachAction.file) {
      _showPlaceholder('Отправка файлов будет подключена следующим шагом.');
      return;
    }

    if (action == _AttachAction.location) {
      _showPlaceholder('Геопозиция будет подключена следующим шагом.');
      return;
    }
  }

  void _showPlaceholder(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _removeMessage(String peerId, String messageId) async {
    await widget.controller.deleteMessage(peerId, messageId);
  }

  Future<void> _pickAndSendGalleryMedia() async {
    await _mediaActions.pickAndSendGalleryMedia(
      context: context,
      controller: widget.controller,
      peerId: widget.chat.peerId,
      maxFileSize: _maxFileSize,
      showPlaceholder: _showPlaceholder,
      replyTo: _replyToMessage,
    );
    _clearReplyTarget();
  }

  String _statusLabel() => ChatScreenHelpers.statusLabel(
    _status,
    _connectError,
    isPeerOnline: widget.presenceService.isPeerOnline(widget.chat.peerId),
    lastSeenAt: widget.presenceService.peerLastSeenAt(widget.chat.peerId),
    fallbackLastSeenAt: _fallbackLastSeenFromMessages(),
  );

  DateTime? _fallbackLastSeenFromMessages() {
    for (var i = widget.chat.messages.length - 1; i >= 0; i--) {
      final message = widget.chat.messages[i];
      if (message.incoming) {
        return message.timestamp;
      }
    }
    final preview = widget.chat.previewMessage;
    if (preview != null && preview.incoming) {
      return preview.timestamp;
    }
    return null;
  }

  Widget _buildComposer() {
    return ChatComposer(
      textController: textCtrl,
      isSendingText: _isSendingText,
      isRecordingVoice: _isRecordingVoice,
      hasStoppedRecording: _stoppedRecordingPath != null,
      recordingDuration: _recordingDuration,
      replySenderLabel:
          _replyToMessage == null ? null : _replySenderLabelFor(_replyToMessage!),
      replyTextPreview:
          _replyToMessage == null ? null : _replyPreviewFor(_replyToMessage!),
      onAttachPressed: _handlePickFilePressed,
      onVoicePressed: _handleVoicePressed,
      onSendPressed: _handleSendPressed,
      onCancelReply: _clearReplyTarget,
    );
  }

  void _jumpToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (!scrollCtrl.hasClients) {
          return;
        }
        scrollCtrl.jumpTo(scrollCtrl.position.maxScrollExtent);
      } catch (e, stack) {
        developer.log('[chat_ui] jumpToBottom failed: $e\n$stack', name: 'chat');
      }
    });
  }

}
