import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../core/calls/call_models.dart';
import '../core/runtime/deep_link_service.dart';
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
import 'state/avatar_service.dart';
import 'state/app_appearance_controller.dart';
import 'state/app_locale_controller.dart';
import 'state/presence_service.dart';
import 'state/settings_controller.dart';
import 'state/ui_app_controller.dart';

import '../core/runtime/call_log_repository.dart';
import '../core/runtime/contacts_repository.dart';
import '../core/node/node_facade.dart';
import '../core/runtime/storage_service.dart';
import '../core/runtime/self_hosted_deploy_service.dart';

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

class _UiAppState extends State<UiApp> {
  int index = 0;
  late final ChatController _chatController;
  late final CallsController _callsController;
  late final ContactsController _contactsController;
  late final SettingsController _settingsController;
  late final SelfHostedDeployService _selfHostedDeployService;
  late final AvatarService _avatarService;
  late final PresenceService _presenceService;
  late final UiAppController _appController;
  late final ContactsRepository _contactsRepository;
  late final CallLogRepository _callLogRepository;
  late final StreamSubscription<CallState> _callStateSubscription;
  StreamSubscription<String>? _deepLinkSubscription;
  CallState _callState = CallState.idle;
  Route<void>? _callRoute;
  String? _lastRecordedCallId;
  int _callsRefreshVersion = 0;
  final Set<String> _handledDeepLinks = <String>{};

  @override
  void initState() {
    super.initState();
    AppFileLogger.log('[ui] UiApp.initState');
    _avatarService = AvatarService(
      facade: widget.facade,
      storage: widget.storage,
    );
    _chatController = ChatController(
      widget.facade,
      storage: widget.storage,
      avatarService: _avatarService,
    );
    _contactsRepository = ContactsRepository(storage: widget.storage);
    _callLogRepository = CallLogRepository(storage: widget.storage);
    _callsController = CallsController(repository: _callLogRepository);
    _contactsController = ContactsController(repository: _contactsRepository);
    _settingsController = SettingsController(
      facade: widget.facade,
      storage: widget.storage,
    );
    _selfHostedDeployService = SelfHostedDeployService();
    _presenceService = PresenceService(facade: widget.facade);
    _appController = UiAppController(
      contactsRepository: _contactsRepository,
      callLogRepository: _callLogRepository,
    );
    _callState = widget.facade.callState;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_handleInitialDeepLink());
      unawaited(_syncCallRoute(_callState));
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
  }

  @override
  void dispose() {
    final route = _callRoute;
    if (route != null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.removeRoute(route);
      _callRoute = null;
    }
    _callStateSubscription.cancel();
    unawaited(_deepLinkSubscription?.cancel());
    unawaited(_avatarService.dispose());
    unawaited(_presenceService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppFileLogger.log('[ui] UiApp.build index=$index');
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

    return Scaffold(
      body: screens[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        height: 74,
        onDestinationSelected: (i) {
          setState(() {
            index = i;
          });
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.people),
            label: strings.contacts,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat),
            label: strings.chats,
          ),
          NavigationDestination(
            icon: const Icon(Icons.call),
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

    if (state.isBusy) {
      if (route != null) {
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
  }

  Future<void> _handleInitialDeepLink() async {
    final link = await DeepLinkService.instance.initialLink();
    if (link == null || link.trim().isEmpty) {
      return;
    }
    await _handleDeepLink(link);
  }

  Future<void> _handleDeepLink(String rawLink) async {
    final link = rawLink.trim();
    if (link.isEmpty || !_handledDeepLinks.add(link)) {
      return;
    }

    try {
      final invite = _settingsController.parseInviteDeepLink(link);
      if (invite.peerId == widget.facade.peerId) {
        return;
      }
      await _settingsController.initialize();
      await _settingsController.importServerConfigPayload(
        invite.serverConfig,
        mode: ServerConfigImportMode.merge,
      );
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
    }
  }
}

class _GlobalCallScreen extends StatefulWidget {
  final NodeFacade facade;
  final UiAppController appController;

  const _GlobalCallScreen({required this.facade, required this.appController});

  @override
  State<_GlobalCallScreen> createState() => _GlobalCallScreenState();
}

class _GlobalCallScreenState extends State<_GlobalCallScreen> {
  late final StreamSubscription<CallState> _callStateSubscription;
  late final ValueNotifier<int> _dataBytesNotifier;
  late CallState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.facade.callState;
    _dataBytesNotifier = ValueNotifier<int>(
      _state.bytesSent + _state.bytesReceived,
    );
    _callStateSubscription = widget.facade.callStateStream.listen((next) {
      _dataBytesNotifier.value = next.bytesSent + next.bytesReceived;
      if (!_shouldRebuild(_state, next)) {
        _state = next;
        return;
      }
      if (!mounted) {
        _state = next;
        return;
      }
      setState(() {
        _state = next;
      });
    });
  }

  @override
  void dispose() {
    _callStateSubscription.cancel();
    _dataBytesNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallScreen(
      facade: widget.facade,
      state: _state,
      contactName: _contactNameFor(_state.peerId),
      dataBytesListenable: _dataBytesNotifier,
    );
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

  String _contactNameFor(String? peerId) {
    return widget.appController.contactNameFor(peerId);
  }
}
