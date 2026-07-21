import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/calls/call_models.dart';
import '../core/firebase/firebase_push_payload.dart';
import '../core/notification/app_badge_service.dart';
import '../core/runtime/deep_link_service.dart';
import '../core/runtime/ios_callkit_service.dart';
import 'screens/contacts_screen.dart';
import 'screens/call_screen.dart';
import 'screens/chats_screen.dart';
import 'screens/calls_screen.dart';
import 'screens/settings_screen.dart';
import 'localization/app_strings.dart';
import 'models/contact.dart';
import 'state/chat_controller.dart';
import 'state/calls_controller.dart';
import 'state/contacts_controller.dart';
import 'state/app_appearance_controller.dart';
import 'state/app_locale_controller.dart';
import 'state/presence_service.dart';
import 'state/settings_controller.dart';
import 'state/ui_app_controller.dart';

import '../core/runtime/call_log_repository.dart';
import '../core/runtime/contacts_repository.dart';
import '../core/node/node_facade.dart';
import '../core/runtime/avatar_service.dart';
import '../core/runtime/storage_service.dart';
import '../core/runtime/self_hosted_deploy_service.dart';
import '../core/firebase/firebase_messaging_service.dart';

class UiApp extends StatefulWidget {
  final NodeFacade facade;
  final StorageService storage;
  final AppAppearanceController appearanceController;
  final AppLocaleController localeController;

  const UiApp({
    super.key,
    required this.facade,
    required this.storage,
    required this.appearanceController,
    required this.localeController,
  });

  @override
  State<UiApp> createState() => _UiAppState();
}

class _UiAppState extends State<UiApp> with WidgetsBindingObserver {
  int index = 0;
  late final ChatController _chatController;
  late final CallsController _callsController;
  late final ContactsController _contactsController;
  late final SettingsController _settingsController;
  late final SelfHostedDeployService _selfHostedDeployService;
  late final AvatarService _avatarService;
  late final AppBadgeService _appBadgeService;
  late final PresenceService _presenceService;
  late final UiAppController _appController;
  late final ContactsRepository _contactsRepository;
  late final CallLogRepository _callLogRepository;
  late final StreamSubscription<CallState> _callStateSubscription;
  StreamSubscription<String>? _deepLinkSubscription;
  StreamSubscription<String>? _chatUpdatesSubscription;
  StreamSubscription<void>? _openCallScreenSubscription;
  CallState _callState = CallState.idle;
  Route<void>? _callRoute;
  String? _lastRecordedCallId;
  String? _lastCallUiPresentedAckCallId;
  int _callsRefreshVersion = 0;
  int _missedCallsBadgeCount = 0;
  final Set<String> _handledDeepLinks = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppFileLogger.log('[ui] UiApp.initState');
    _appBadgeService = AppBadgeService(storage: widget.storage);
    _avatarService = AvatarService(
      facade: widget.facade,
      storage: widget.storage,
    );
    _chatController = ChatController(
      widget.facade,
      storage: widget.storage,
      avatarService: _avatarService,
      onUnreadBadgeCountChanged: (unreadCount) {
        _updateAppIconBadge(unreadMessagesOverride: unreadCount);
      },
    );
    FirebaseMessagingService.onGroupMembersUpdateFromPush =
        (payload, {String? sourcePeerId}) {
          return _chatController.applyGroupMembersUpdateFromPush(
            payload,
            sourcePeerId: sourcePeerId,
          );
        };
    FirebaseMessagingService.onPushOpened = (data, {required source}) async {
      if (!mounted) {
        return;
      }
      final pushPayload = FirebasePushPayload.fromMap(data);
      if (pushPayload.isCallInvite) {
        if (pushPayload.hasPeerAndCallId) {
          await widget.facade.presentIncomingCallFromPush(
            peerId: pushPayload.callPeerId,
            callId: pushPayload.callId,
            mediaType: pushPayload.callMediaType,
          );
          if (!mounted) {
            return;
          }
          setState(() {
            index = 2;
          });
          unawaited(_refreshMissedCallsBadge(markSeen: true));
          unawaited(_syncCallRoute(widget.facade.callState));
        }
        return;
      }
      if (pushPayload.isCallEnd && pushPayload.hasPeerAndCallId) {
        await widget.facade.endCallFromRemotePush(
          peerId: pushPayload.callPeerId,
          callId: pushPayload.callId,
        );
        return;
      }
      await _pollRelayForOpenedPush(pushPayload, source: source);
      if (source == 'foreground') {
        return;
      }
      setState(() {
        index = 1;
      });
    };
    _contactsRepository = ContactsRepository(storage: widget.storage);
    _callLogRepository = CallLogRepository(storage: widget.storage);
    _callsController = CallsController(repository: _callLogRepository);
    _contactsController = ContactsController(repository: _contactsRepository);
    _contactsController.loadIntoMemory();
    _settingsController = SettingsController(
      facade: widget.facade,
      storage: widget.storage,
    );
    _selfHostedDeployService = SelfHostedDeployService();
    _presenceService = PresenceService(facade: widget.facade);
    _appController = UiAppController(
      contactsRepository: _contactsRepository,
      callLogRepository: _callLogRepository,
      contactsController: _contactsController,
    );
    _callState = widget.facade.callState;
    unawaited(_refreshMissedCallsBadge(markSeen: index == 2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_settingsController.initialize());
      unawaited(_handleInitialDeepLink());
      unawaited(_syncCallRoute(_callState));
      unawaited(FirebaseMessagingService.consumePendingOpenedPushIfAny());
    });
    _deepLinkSubscription = DeepLinkService.instance.links.listen(
      (link) => unawaited(_handleDeepLink(link)),
      onError: (error, stackTrace) {
        AppFileLogger.log(
          '[ui] deepLink stream error=$error',
          name: 'ui',
          stackTrace: stackTrace is StackTrace ? stackTrace : null,
        );
      },
    );
    _openCallScreenSubscription = IosCallkitService.instance.onOpenCallScreen
        .listen((_) {
          if (!mounted) {
            return;
          }
          setState(() {
            index = 2;
          });
          unawaited(_refreshMissedCallsBadge(markSeen: true));
          unawaited(_syncCallRoute(_callState));
        });
    _callStateSubscription = widget.facade.callStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      _callState = state;
      unawaited(_syncCallRoute(state));
      unawaited(_maybeRecordCall(state));
      if (state.phase == CallPhase.failed && state.error != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error!)));
      }
    });
    _chatUpdatesSubscription = _chatController.messageUpdatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      _updateAppIconBadge();
      setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FirebaseMessagingService.onGroupMembersUpdateFromPush = null;
    FirebaseMessagingService.onPushOpened = null;
    final route = _callRoute;
    if (route != null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.removeRoute(route);
      _callRoute = null;
    }
    _callStateSubscription.cancel();
    unawaited(_chatUpdatesSubscription?.cancel());
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_openCallScreenSubscription?.cancel());
    unawaited(_avatarService.dispose());
    unawaited(_presenceService.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        IosCallkitService.instance.refreshVoipRegistration(reason: 'resume'),
      );
      unawaited(FirebaseMessagingService.consumePendingOpenedPushIfAny());
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      ContactsScreen(
        controller: _chatController,
        contactsController: _contactsController,
        settingsController: _settingsController,
        presenceService: _presenceService,
        avatarService: _avatarService,
      ),
      ChatsScreen(
        controller: _chatController,
        presenceService: _presenceService,
        avatarService: _avatarService,
      ),
      CallsScreen(
        facade: widget.facade,
        controller: _chatController,
        callsController: _callsController,
        refreshVersion: _callsRefreshVersion,
        presenceService: _presenceService,
        avatarService: _avatarService,
        onHistoryChanged: _handleCallsHistoryChanged,
      ),
      SettingsScreen(
        controller: _settingsController,
        avatarService: _avatarService,
        chatController: _chatController,
        selfHostedDeployService: _selfHostedDeployService,
        appearanceController: widget.appearanceController,
        localeController: widget.localeController,
      ),
    ];
    final strings = context.strings;
    final totalUnread = _chatController.unreadMessagesCount();

    return Scaffold(
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: 74,
        onDestinationSelected: (i) {
          setState(() {
            index = i;
          });
          if (i == 2) {
            unawaited(_refreshMissedCallsBadge(markSeen: true));
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.people),
            label: strings.contacts,
          ),
          NavigationDestination(
            icon: totalUnread > 0
                ? Badge(
                    label: Text(
                      totalUnread > 99 ? '99+' : totalUnread.toString(),
                    ),
                    child: const Icon(Icons.chat),
                  )
                : const Icon(Icons.chat),
            label: strings.chats,
          ),
          NavigationDestination(
            icon: _missedCallsBadgeCount > 0
                ? Badge(
                    label: Text(
                      _missedCallsBadgeCount > 99
                          ? '99+'
                          : _missedCallsBadgeCount.toString(),
                    ),
                    child: const Icon(Icons.call),
                  )
                : const Icon(Icons.call),
            label: strings.calls,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: strings.settings,
          ),
        ],
      ),
    );
  }

  Future<void> _syncCallRoute(CallState state) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = _callRoute;
    final shouldAcknowledgeCallUiPresented =
        state.direction == CallDirection.incoming &&
        (state.phase == CallPhase.connecting ||
            state.phase == CallPhase.active);
    final normalizedCallId = (state.callId ?? '').trim();
    final canAckCurrentCall =
        shouldAcknowledgeCallUiPresented &&
        normalizedCallId.isNotEmpty &&
        normalizedCallId != _lastCallUiPresentedAckCallId;

    if (state.isBusy) {
      if (route != null) {
        if (canAckCurrentCall) {
          _lastCallUiPresentedAckCallId = normalizedCallId;
          unawaited(
            IosCallkitService.instance.notifyCallUiPresented(state.callId),
          );
        }
        return;
      }
      final nextRoute = PageRouteBuilder<void>(
        settings: const RouteSettings(name: 'active_call'),
        opaque: true,
        fullscreenDialog: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return PopScope(
            canPop: false,
            child: _GlobalCallScreen(
              facade: widget.facade,
              appController: _appController,
              contactsController: _contactsController,
            ),
          );
        },
      );

      _callRoute = nextRoute;
      navigator.push(nextRoute).whenComplete(() {
        if (identical(_callRoute, nextRoute)) {
          _callRoute = null;
        }
      });
      if (canAckCurrentCall) {
        _lastCallUiPresentedAckCallId = normalizedCallId;
        unawaited(
          IosCallkitService.instance.notifyCallUiPresented(state.callId),
        );
      }
      return;
    }

    if (route != null) {
      try {
        navigator.removeRoute(route);
      } catch (_) {
        // Route may already be gone if the navigator was rebuilt.
      }
      _callRoute = null;
    }
    if (state.phase == CallPhase.idle) {
      _lastCallUiPresentedAckCallId = null;
    }
  }

  Future<void> _maybeRecordCall(CallState next) async {
    final callId = next.callId;
    final isTerminal =
        next.phase == CallPhase.ended || next.phase == CallPhase.failed;
    if (!isTerminal || callId == null || callId.isEmpty) {
      return;
    }
    if (_lastRecordedCallId == callId) {
      return;
    }

    final peerId = next.peerId;
    final direction = next.direction;
    if (peerId == null || peerId.isEmpty || direction == null) {
      return;
    }

    _lastRecordedCallId = callId;
    await _appController.recordCall(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _callsRefreshVersion++;
    });
    await _refreshMissedCallsBadge(markSeen: index == 2);
  }

  Future<void> _handleCallsHistoryChanged() async {
    await _refreshMissedCallsBadge(markSeen: index == 2);
  }

  Future<void> _refreshMissedCallsBadge({required bool markSeen}) async {
    if (markSeen) {
      await _callsController.markMissedCallsSeenNow();
    }
    final count = await _callsController.loadMissedCallsBadgeCount();
    if (!mounted) {
      return;
    }
    setState(() {
      _missedCallsBadgeCount = count;
    });
    _updateAppIconBadge(missedCallsOverride: count);
  }

  void _updateAppIconBadge({
    int? missedCallsOverride,
    int? unreadMessagesOverride,
  }) {
    final missedCalls = missedCallsOverride ?? _missedCallsBadgeCount;
    final unreadMessages =
        unreadMessagesOverride ?? _chatController.unreadMessagesCount();
    unawaited(
      _appBadgeService.syncFromUi(
        unreadMessages: unreadMessages,
        missedCalls: missedCalls,
      ),
    );
  }

  Future<void> _pollRelayForOpenedPush(
    FirebasePushPayload pushPayload, {
    required String source,
  }) async {
    final hintedRelayServers = pushPayload.relayServers;
    if (hintedRelayServers.isNotEmpty) {
      try {
        await widget.facade.pollRelay(relayServers: hintedRelayServers);
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[ui] push open hinted pollRelay failed type=${pushPayload.type} '
          'source=$source hints=${hintedRelayServers.length} error=$error',
          name: 'ui',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    try {
      await widget.facade.pollRelay();
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[ui] push open full pollRelay failed type=${pushPayload.type} '
        'source=$source error=$error',
        name: 'ui',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _handleInitialDeepLink() async {
    final link = await DeepLinkService.instance.initialLink();
    if (link == null || link.trim().isEmpty) {
      AppFileLogger.log('[ui] deepLink warning initial empty', name: 'ui');
      return;
    }
    AppFileLogger.log(
      '[ui] deepLink warning initial received length=${link.length}',
      name: 'ui',
    );
    await _handleDeepLink(link);
  }

  Future<void> _handleDeepLink(String rawLink) async {
    final link = _extractDeepLinkCandidate(rawLink);
    if (link.isEmpty) {
      AppFileLogger.log(
        '[ui] deepLink warning extracted empty rawLength=${rawLink.length}',
        name: 'ui',
      );
      return;
    }

    try {
      AppFileLogger.log(
        '[ui] deepLink warning handle scheme=${Uri.tryParse(link)?.scheme} '
        'host=${Uri.tryParse(link)?.host} length=${link.length}',
        name: 'ui',
      );
      final uri = Uri.tryParse(link);
      final isCallDeepLink =
          uri != null && uri.scheme == 'peerlink' && uri.host == 'call';
      if (isCallDeepLink) {
        setState(() {
          index = 2;
        });
        unawaited(_refreshMissedCallsBadge(markSeen: true));
        return;
      }
      if (!_handledDeepLinks.add(link)) {
        AppFileLogger.log(
          '[ui] deepLink warning duplicate ignored length=${link.length}',
          name: 'ui',
        );
        return;
      }

      final serverConfigFromPayload = _settingsController
          .tryParseServerConfigFromAnyDeepLinkPayload(link);
      if (serverConfigFromPayload != null ||
          _settingsController.isServerConfigDeepLink(link)) {
        await _settingsController.initialize();
        if (!mounted) {
          return;
        }
        final payload =
            serverConfigFromPayload ??
            _settingsController.parseServerConfigDeepLink(link);
        AppFileLogger.log(
          '[ui] deepLink warning config import start '
          'bootstrap=${payload.bootstrap.length} relay=${payload.relay.length} '
          'turn=${payload.turn.length} push=${payload.push.length}',
          name: 'ui',
        );
        await _settingsController.importServerConfigPayload(
          payload,
          mode: ServerConfigImportMode.merge,
        );
        AppFileLogger.log(
          '[ui] deepLink warning config import done '
          'bootstrap=${_settingsController.bootstrapPeers.length} '
          'relay=${_settingsController.relayServers.length} '
          'turn=${_settingsController.turnServers.length} '
          'push=${_settingsController.pushServers.length}',
          name: 'ui',
        );
        if (!mounted) {
          return;
        }
        setState(() {
          index = 3;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.serverSettingsMerged)),
        );
        return;
      }

      if (_settingsController.isAccountPairingDeepLink(link)) {
        await _settingsController.initialize();
        await _settingsController.requestAccountPairingDeepLink(link);
        if (!mounted) {
          return;
        }
        setState(() {
          index = 3;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.strings.accountPairingRequestSent)),
        );
        return;
      }

      final invite = _settingsController.parseInviteDeepLink(link);
      await _settingsController.initialize();
      AppFileLogger.log(
        '[ui] deepLink warning invite import start '
        'peer=${invite.peerId} bootstrap=${invite.serverConfig.bootstrap.length} '
        'relay=${invite.serverConfig.relay.length} '
        'turn=${invite.serverConfig.turn.length} '
        'push=${invite.serverConfig.push.length}',
        name: 'ui',
      );
      await _settingsController.importServerConfigPayload(
        invite.serverConfig,
        mode: ServerConfigImportMode.merge,
      );
      AppFileLogger.log(
        '[ui] deepLink warning invite import done '
        'bootstrap=${_settingsController.bootstrapPeers.length} '
        'relay=${_settingsController.relayServers.length} '
        'turn=${_settingsController.turnServers.length} '
        'push=${_settingsController.pushServers.length}',
        name: 'ui',
      );
      if (invite.peerId == widget.facade.peerId) {
        return;
      }
      final displayName = invite.displayName?.trim().isNotEmpty == true
          ? invite.displayName!.trim()
          : invite.peerId;
      await _contactsController.addOrUpdateContact(
        Contact(peerId: invite.peerId, name: displayName),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        index = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.strings.contactAdded(displayName))),
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[ui] deepLink ignored link=$link error=$error',
        name: 'ui',
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  String _extractDeepLinkCandidate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final directUri = Uri.tryParse(trimmed);
    if (directUri != null && directUri.hasScheme) {
      return trimmed;
    }
    final match = RegExp(
      r'(peerlink:\/\/\S+|https?:\/\/\S+)',
    ).firstMatch(trimmed);
    if (match == null) {
      return trimmed;
    }
    final candidate = match.group(0)?.trim() ?? '';
    return candidate.replaceFirst(RegExp(r'[)\].,;!?]+$'), '');
  }
}

class _GlobalCallScreen extends StatefulWidget {
  final NodeFacade facade;
  final UiAppController appController;
  final ContactsController contactsController;

  const _GlobalCallScreen({
    required this.facade,
    required this.appController,
    required this.contactsController,
  });

  @override
  State<_GlobalCallScreen> createState() => _GlobalCallScreenState();
}

class _GlobalCallScreenState extends State<_GlobalCallScreen> {
  late final StreamSubscription<CallState> _callStateSubscription;
  late final ValueNotifier<int> _dataBytesNotifier;
  late CallState _state;
  String? _lastRenderedContactName;

  @override
  void initState() {
    super.initState();
    _state = widget.facade.callState;
    widget.contactsController.loadIntoMemory();
    _lastRenderedContactName = _resolveContactName(_state.peerId);
    _dataBytesNotifier = ValueNotifier<int>(
      _state.bytesSent + _state.bytesReceived,
    );
    widget.contactsController.addListener(_handleContactsChanged);
    _callStateSubscription = widget.facade.callStateStream.listen((next) {
      _dataBytesNotifier.value = next.bytesSent + next.bytesReceived;
      final previousPeerId = _state.peerId;
      if (!_shouldRebuild(_state, next)) {
        _state = next;
        if (previousPeerId != next.peerId) {
          _refreshContactName();
        }
        return;
      }
      if (!mounted) {
        _state = next;
        return;
      }
      setState(() {
        _state = next;
        _lastRenderedContactName = _resolveContactName(next.peerId);
      });
    });
  }

  @override
  void dispose() {
    widget.contactsController.removeListener(_handleContactsChanged);
    _callStateSubscription.cancel();
    _dataBytesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallScreen(
      facade: widget.facade,
      state: _state,
      contactName: _lastRenderedContactName!,
      dataBytesListenable: _dataBytesNotifier,
    );
  }

  void _handleContactsChanged() {
    _refreshContactName();
  }

  void _refreshContactName() {
    final nextContactName = _resolveContactName(_state.peerId);
    if (nextContactName == _lastRenderedContactName) {
      return;
    }
    if (!mounted) {
      _lastRenderedContactName = nextContactName;
      return;
    }
    setState(() {
      _lastRenderedContactName = nextContactName;
    });
  }

  bool _shouldRebuild(CallState previous, CallState next) {
    return previous.phase != next.phase ||
        previous.direction != next.direction ||
        previous.peerId != next.peerId ||
        previous.callId != next.callId ||
        previous.connectedAt != next.connectedAt ||
        previous.mediaType != next.mediaType ||
        previous.localVideoEnabled != next.localVideoEnabled ||
        previous.localVideoAvailable != next.localVideoAvailable ||
        previous.remoteVideoEnabled != next.remoteVideoEnabled ||
        previous.remoteVideoAvailable != next.remoteVideoAvailable ||
        previous.videoToggleInProgress != next.videoToggleInProgress ||
        previous.isFrontCamera != next.isFrontCamera ||
        previous.isMuted != next.isMuted ||
        previous.speakerOn != next.speakerOn ||
        previous.transportMode != next.transportMode ||
        previous.transportLabel != next.transportLabel ||
        previous.debugStatus != next.debugStatus ||
        previous.error != next.error ||
        previous.localStream?.id != next.localStream?.id ||
        previous.remoteStream?.id != next.remoteStream?.id;
  }

  String _resolveContactName(String? peerId) {
    return widget.appController.contactNameFor(peerId);
  }
}
