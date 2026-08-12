import 'dart:async';
import 'package:peerlink/core/runtime/diagnostic_log.dart' as developer;

import 'package:flutter/material.dart';

import '../../core/runtime/avatar_service.dart';
import '../models/chat.dart';
import '../state/chat_controller.dart';
import '../state/chat_controller_models.dart';
import '../state/presence_service.dart';
import 'chat_screen_scroll_coordinator.dart';

class ChatScreenLifecycle {
  final Chat Function() chat;
  final ChatController Function() controller;
  final PresenceService Function() presenceService;
  final AvatarService Function() avatarService;
  final BuildContext Function() context;
  final bool Function() isMounted;
  final void Function() refresh;
  final void Function(ChatConnectionStatus status, String? connectError)
  onConnectionSnapshotChanged;
  final ChatScreenScrollCoordinator scrollCoordinator;
  final bool Function() isGroupChat;

  StreamSubscription<String>? _statusSubscription;
  StreamSubscription<String>? _messageSubscription;
  StreamSubscription<String>? _presenceSubscription;
  StreamSubscription<String>? _avatarSubscription;
  Timer? _presenceRefreshTimer;

  ChatScreenLifecycle({
    required this.chat,
    required this.controller,
    required this.presenceService,
    required this.avatarService,
    required this.context,
    required this.isMounted,
    required this.refresh,
    required this.onConnectionSnapshotChanged,
    required this.scrollCoordinator,
    required this.isGroupChat,
  });

  void start() {
    developer.log(
      '[chat_ui] lifecycle start peer=${chat().peerId} '
      'messages=${chat().messages.length} loaded=${chat().messagesLoaded}',
      name: 'chat',
      level: 900,
    );
    _bindConnectionUpdates();
    _bindMessageUpdates();
    _scheduleInitialLoad();
    _bindPresenceAndAvatarUpdates();
    _scheduleInitialViewport();
  }

  void dispose() {
    developer.log(
      '[chat_ui] lifecycle dispose peer=${chat().peerId} '
      'messages=${chat().messages.length} loaded=${chat().messagesLoaded}',
      name: 'chat',
      level: 900,
    );
    _statusSubscription?.cancel();
    _messageSubscription?.cancel();
    _presenceSubscription?.cancel();
    _avatarSubscription?.cancel();
    _presenceRefreshTimer?.cancel();
  }

  void _bindConnectionUpdates() {
    _statusSubscription = controller().connectionStatusStream.listen((peerId) {
      try {
        if (peerId != chat().peerId || !isMounted()) {
          return;
        }
        onConnectionSnapshotChanged(
          controller().connectionStatus(peerId),
          controller().connectionError(peerId),
        );
      } catch (e, stack) {
        developer.log(
          '[chat_ui] status listener failed: $e\n$stack',
          name: 'chat',
        );
      }
    });
  }

  void _bindMessageUpdates() {
    _messageSubscription = controller().messageUpdatesStream.listen((peerId) {
      try {
        if (peerId != chat().peerId || !isMounted()) {
          return;
        }
        if (!controller().chats.containsKey(chat().peerId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (isMounted()) {
              Navigator.of(context()).maybePop();
            }
          });
          return;
        }

        final wasNearBottom = scrollCoordinator.isNearBottom();
        developer.log(
          '[chat_ui] message-update peer=${chat().peerId} '
          'messages=${chat().messages.length} wasNearBottom=$wasNearBottom '
          'initialApplied=${scrollCoordinator.initialPositionApplied}',
          name: 'chat',
          level: 900,
        );
        refresh();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          scrollCoordinator.syncScrollToBottomButton();
        });

        if (scrollCoordinator.initialPositionApplied) {
          if (wasNearBottom) {
            scrollCoordinator.scheduleFollowBottomAndRead();
          } else {
            developer.log(
              '[chat_ui] message update no auto-read peer=${chat().peerId} '
              'reason=not-at-bottom',
              name: 'chat',
            );
          }
        } else {
          scrollCoordinator.scheduleInitialViewport();
        }
      } catch (e, stack) {
        developer.log(
          '[chat_ui] message listener failed: $e\n$stack',
          name: 'chat',
        );
      }
    });
  }

  void _scheduleInitialLoad() {
    unawaited(() async {
      final stopwatch = Stopwatch()..start();
      developer.log(
        '[chat_ui] initial-load start peer=${chat().peerId}',
        name: 'chat',
        level: 900,
      );
      await controller().ensureChatLoaded(chat().peerId);
      developer.log(
        '[chat_ui] initial-load done peer=${chat().peerId} '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'messages=${chat().messages.length} loaded=${chat().messagesLoaded}',
        name: 'chat',
        level: 900,
      );
      if (!isMounted()) {
        return;
      }
      scrollCoordinator.scheduleInitialViewport();
    }());
  }

  void _bindPresenceAndAvatarUpdates() {
    if (isGroupChat()) {
      return;
    }

    _presenceSubscription = presenceService().updatesStream.listen((peerId) {
      if (peerId != chat().peerId || !isMounted()) {
        return;
      }
      refresh();
    });
    _avatarSubscription = avatarService().updatesStream.listen((peerId) {
      if (peerId != chat().peerId || !isMounted()) {
        return;
      }
      refresh();
    });
    _presenceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!isMounted()) {
        return;
      }
      refresh();
    });
  }

  void _scheduleInitialViewport() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!isMounted()) {
        return;
      }
      scrollCoordinator.scheduleInitialViewport();
    });
  }
}
