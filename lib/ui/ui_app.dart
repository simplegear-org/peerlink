// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../app/calls/app_call_coordinator.dart';
import '../app/composition/app_dependencies.dart';
import '../app/deep_links/app_deep_link_coordinator.dart';
import '../app/invites/invite_flow_coordinator.dart';
import '../app/lifecycle/app_lifecycle_coordinator.dart';
import '../app/push/app_push_coordinator.dart';
import '../core/calls/call_models.dart';
import '../core/firebase/firebase_push_payload.dart';
import '../core/node/node_capability_apis.dart';
import '../core/runtime/android_install_referrer_service.dart';
import '../features/calls/platform/ios_callkit_service.dart';
import '../core/runtime/peer_access_control_service.dart';
import 'screens/account_restricted_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/call_screen.dart';
import 'screens/chats_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/calls_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/terms_gate_screen.dart';
import 'localization/app_strings.dart';
import 'state/chat_controller.dart';
import 'state/calls_controller.dart';
import 'state/contacts_controller.dart';
import 'state/app_restriction_controller.dart';
import 'state/presence_service.dart';
import 'state/settings_controller.dart';
import 'state/ui_app_controller.dart';

import '../core/node/node_facade.dart';
import '../features/profile/application/avatar_service.dart';
import '../core/runtime/self_hosted_deploy_service.dart';
import '../core/firebase/firebase_messaging_service.dart';

class UiApp extends StatefulWidget {
  final AppDependencies dependencies;

  const UiApp({super.key, required this.dependencies});

  NodeFacade get facade => dependencies.nodeFacade;

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
  late final PresenceService _presenceService;
  late final UiAppController _appController;
  late final AppCallCoordinator _callCoordinator;
  late final AppDeepLinkCoordinator _deepLinkCoordinator;
  late final InviteFlowCoordinator _inviteFlowCoordinator;
  late final AppLifecycleCoordinator _lifecycleCoordinator;
  late final AppPushCoordinator _pushCoordinator;
  late final AppRestrictionController _restrictionController;
  late final PeerAccessControlService _accessControl;
  StreamSubscription<String>? _chatUpdatesSubscription;
  CallState _callState = CallState.idle;
  Route<void>? _callRoute;
  String? _lastCallUiPresentedAckCallId;
  int _callsRefreshVersion = 0;
  int _missedCallsBadgeCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppFileLogger.log('[ui] UiApp.initState');
    final ui = widget.dependencies.ui;
    _chatController = ui.chatController;
    _callsController = ui.callsController;
    _contactsController = ui.contactsController;
    _settingsController = ui.settingsController;
    _restrictionController = ui.restrictionController;
    _selfHostedDeployService = ui.selfHostedDeployService;
    _avatarService = ui.avatarService;
    _presenceService = ui.presenceService;
    _appController = ui.appController;
    _accessControl = ui.accessControl;
    ui.badgeCoordinator.onMissedCallsBadgeCountChanged = (count) {
      if (!mounted) {
        return;
      }
      setState(() {
        _missedCallsBadgeCount = count;
      });
    };
    _pushCoordinator = AppPushCoordinator(
      calls: widget.facade,
      network: widget.facade,
      onGroupMembersUpdate: (payload, {String? sourcePeerId}) {
        return _chatController.applyGroupMembersUpdateFromPush(
          payload,
          sourcePeerId: sourcePeerId,
        );
      },
      onModerationPolicy: (snapshot, {required source}) async {
        if (!mounted) {
          return;
        }
        await _restrictionController.applyPolicyFromPush(
          snapshot,
          callState: widget.facade.callState,
        );
        if (mounted) {
          setState(() {});
        }
      },
      shouldDropExternalInteraction: (label) {
        return !mounted || _shouldDropExternalInteraction(label);
      },
      shouldDropOpenedPush: _shouldDropOpenedPush,
      refreshMissedCallsBadge: _refreshMissedCallsBadge,
      syncCallRoute: _syncCallRoute,
      canHandleExternalInteraction: () {
        return mounted &&
            _restrictionController.gate.canHandleExternalInteraction;
      },
      showCallsTab: () {
        if (!mounted) {
          return;
        }
        setState(() {
          index = 2;
        });
      },
      showChatsTab: () {
        if (!mounted) {
          return;
        }
        setState(() {
          index = 1;
        });
      },
    );
    _pushCoordinator.register();
    _callState = widget.facade.callState;
    _callCoordinator = AppCallCoordinator(
      calls: widget.facade,
      canHandleExternalInteraction: () {
        return mounted &&
            _restrictionController.gate.canHandleExternalInteraction;
      },
      recordCall: _appController.recordCall,
      logStatusFor: _appController.logStatusFor,
      syncCallRoute: _syncCallRoute,
      refreshMissedCallsBadge: _refreshMissedCallsBadge,
      isCallsTabSelected: () => index == 2,
      showCallsTab: () {
        if (!mounted) {
          return;
        }
        setState(() {
          index = 2;
        });
      },
      onCallStateChanged: (state) {
        _callState = state;
      },
      onHistoryChanged: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _callsRefreshVersion++;
        });
      },
      showError: (error) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      },
    );
    _callCoordinator.start();
    _inviteFlowCoordinator = InviteFlowCoordinator(
      localPeerId: widget.facade.peerId,
      verifyIdentity: (bundle, {required expectedPeerId}) => widget.facade
          .trustPeerIdentityBundleV3(bundle, expectedPeerId: expectedPeerId),
      ensureInitialServerConfig:
          _settingsController.ensureInitialServerConfigForInvite,
      mergeServers: (config) => _settingsController.importServerConfigPayload(
        config,
        mode: ServerConfigImportMode.merge,
      ),
      upsertContact: ({required peerId, username}) => _contactsController
          .upsertInviteContact(peerId: peerId, username: username),
      ensureDirectChat: ({required peerId, required name}) =>
          _chatController.createDirectChat(peerId: peerId, name: name),
      openChat: _openInviteChat,
      localIdentityBundle: widget.facade.identityBundleV3Json,
      signInviteManifest: widget.facade.signInviteManifest,
      localUsername: () => _settingsController.inviteUsername,
      currentServerConfig:
          _settingsController.currentConfiguredServerConfigPayload,
      loadPendingInviteToken: _settingsController.loadPendingInviteToken,
      savePendingInviteToken: _settingsController.savePendingInviteToken,
      clearPendingInviteToken: _settingsController.clearPendingInviteToken,
    );
    _lifecycleCoordinator = AppLifecycleCoordinator(
      refreshRestrictionStatus: _refreshRestrictionStatus,
      retryModerationReports: ui.moderationLifecycleService.handleAppResumed,
      retryPendingInvite: _resumePendingInvite,
    );
    _deepLinkCoordinator = AppDeepLinkCoordinator(
      calls: widget.facade,
      identity: widget.facade,
      settingsController: _settingsController,
      contactsController: _contactsController,
      restrictionController: _restrictionController,
      syncCallRoute: _syncCallRoute,
      refreshMissedCallsBadge: _refreshMissedCallsBadge,
      showContactsTab: () => _selectTab(0),
      showCallsTab: () => _selectTab(2),
      showSettingsTab: () => _selectTab(3),
      onServerSettingsMerged: () {
        _showSnackBar(context.strings.serverSettingsMerged);
      },
      onAccountPairingRequestSent: () {
        _showSnackBar(context.strings.accountPairingRequestSent);
      },
      onContactAdded: (displayName) {
        _showSnackBar(context.strings.contactAdded(displayName));
      },
      onError: _showSnackBar,
      inviteFlowCoordinator: _inviteFlowCoordinator,
    );
    _deepLinkCoordinator.start();
    unawaited(_refreshMissedCallsBadge(markSeen: index == 2));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_settingsController.initialize());
      unawaited(_restoreDeferredAndroidInvite());
      unawaited(_refreshRestrictionStatus(reason: 'startup'));
      unawaited(_deepLinkCoordinator.handleInitial());
      unawaited(_syncCallRoute(_callState));
      unawaited(FirebaseMessagingService.consumePendingOpenedPushIfAny());
    });
    _chatUpdatesSubscription = _chatController.messageUpdatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      _updateAppIconBadge();
      setState(() {});
    });
  }

  bool _shouldDropOpenedPush(
    FirebasePushPayload payload, {
    required String source,
  }) {
    final peerId = payload.senderPeerId;
    if (peerId.isEmpty) {
      return false;
    }
    final decision = _accessControl.evaluateIncoming(
      peerId: peerId,
      type: payload.isCallPayload
          ? IncomingInteractionType.call
          : IncomingInteractionType.push,
    );
    if (decision == IncomingInteractionDecision.allow) {
      return false;
    }
    AppFileLogger.log(
      '[ui] push open dropped source=$source reason=${decision.name} '
      'type=${payload.type} from=$peerId',
      name: 'ui',
    );
    return true;
  }

  Future<void> _resumePendingInvite() async {
    await _settingsController.initialize();
    final result = await _inviteFlowCoordinator.resumePendingInvite();
    if (result?.isCompleted == true && mounted) {
      _showSnackBar(context.strings.contactAdded(result!.displayName!));
    }
  }

  Future<void> _restoreDeferredAndroidInvite() async {
    await _settingsController.initialize();
    final token = await AndroidInstallReferrerService.instance
        .readInviteToken();
    if (token != null) {
      final existing = await _settingsController.loadPendingInviteToken();
      if (existing == null) {
        await _settingsController.savePendingInviteToken(token);
      }
      await AndroidInstallReferrerService.instance.markInviteTokenHandled(
        token,
      );
    }
    await _resumePendingInvite();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushCoordinator.dispose();
    unawaited(_deepLinkCoordinator.dispose());
    final route = _callRoute;
    if (route != null) {
      final navigator = Navigator.of(context, rootNavigator: true);
      navigator.removeRoute(route);
      _callRoute = null;
    }
    unawaited(_callCoordinator.dispose());
    unawaited(_chatUpdatesSubscription?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleCoordinator.handleLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    if (_restrictionController.gate.shouldShowTermsGate) {
      return TermsGateScreen(
        version: _settingsController.termsVersion,
        onAccept: _acceptCurrentTerms,
      );
    }
    if (_restrictionController.gate.shouldShowModerationGate) {
      return AccountRestrictedScreen(
        policy: _restrictionController.moderationPolicy,
        moderation: widget.facade,
        onAppealSubmitted: _markModerationAppealSubmitted,
        onWarningContinued: _markModerationWarningAcknowledged,
      );
    }
    final screens = [
      ContactsScreen(
        controller: _chatController,
        contactsController: _contactsController,
        settingsController: _settingsController,
        presenceService: _presenceService,
        avatarService: _avatarService,
        createInviteUrl: _inviteFlowCoordinator.createInviteUrl,
      ),
      ChatsScreen(
        controller: _chatController,
        presenceService: _presenceService,
        avatarService: _avatarService,
      ),
      CallsScreen(
        calls: widget.facade,
        controller: _chatController,
        callsController: _callsController,
        contactsController: _contactsController,
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
        appearanceController: widget.dependencies.appearanceController,
        localeController: widget.dependencies.localeController,
        moderationPolicy: _restrictionController.moderationPolicy,
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
    if (!_restrictionController.gate.canHandleExternalInteraction) {
      return;
    }
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
              calls: widget.facade,
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

  Future<void> _refreshRestrictionStatus({required String reason}) async {
    final changed = await _restrictionController.refreshModerationStatus(
      reason: reason,
    );
    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _markModerationAppealSubmitted() async {
    await _restrictionController.markAppealSubmitted();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _markModerationWarningAcknowledged() async {
    await _restrictionController.markWarningAcknowledged();
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> _handleCallsHistoryChanged() async {
    await _refreshMissedCallsBadge(markSeen: index == 2);
  }

  void _selectTab(int nextIndex) {
    if (!mounted) {
      return;
    }
    setState(() {
      index = nextIndex;
    });
  }

  void _openInviteChat(String peerId, String name) {
    if (!mounted) return;
    final chat = _chatController.openChat(peerId, name);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          chat: chat,
          controller: _chatController,
          presenceService: _presenceService,
          avatarService: _avatarService,
        ),
      ),
    );
  }

  void _showSnackBar(String text) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _refreshMissedCallsBadge({required bool markSeen}) async {
    await widget.dependencies.ui.badgeCoordinator.refreshMissedCallsBadge(
      markSeen: markSeen,
    );
  }

  void _updateAppIconBadge({
    int? missedCallsOverride,
    int? unreadMessagesOverride,
  }) {
    widget.dependencies.ui.badgeCoordinator.syncAppIconBadge(
      missedCallsOverride: missedCallsOverride,
      unreadMessagesOverride: unreadMessagesOverride,
    );
  }

  bool _shouldDropExternalInteraction(String label) {
    return _restrictionController.shouldDropExternalInteraction(label);
  }

  Future<void> _acceptCurrentTerms() async {
    await _restrictionController.acceptCurrentTerms();
    if (!mounted) {
      return;
    }
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.strings.termsAccepted)));
    unawaited(_deepLinkCoordinator.handleInitial());
    unawaited(FirebaseMessagingService.consumePendingOpenedPushIfAny());
    unawaited(_syncCallRoute(_callState));
  }
}

class _GlobalCallScreen extends StatefulWidget {
  final CallsApi calls;
  final UiAppController appController;
  final ContactsController contactsController;

  const _GlobalCallScreen({
    required this.calls,
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
    _state = widget.calls.callState;
    widget.contactsController.loadIntoMemory();
    _lastRenderedContactName = _resolveContactName(_state.peerId);
    _dataBytesNotifier = ValueNotifier<int>(
      _state.bytesSent + _state.bytesReceived,
    );
    widget.contactsController.addListener(_handleContactsChanged);
    _callStateSubscription = widget.calls.callStateStream.listen((next) {
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
      calls: widget.calls,
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
