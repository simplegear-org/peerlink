// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/firebase/firebase_push_payload.dart';
import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:peerlink/core/runtime/deep_link_service.dart';
import 'package:peerlink/core/runtime/server_config_payload.dart';
import 'package:peerlink/ui/models/contact.dart';
import 'package:peerlink/ui/state/app_restriction_controller.dart';
import 'package:peerlink/ui/state/contacts_controller.dart';
import 'package:peerlink/ui/state/settings_controller.dart';

typedef AppCallRouteSync = Future<void> Function(CallState state);
typedef AppMissedCallsBadgeRefresh =
    Future<void> Function({required bool markSeen});

class AppDeepLinkCoordinator {
  AppDeepLinkCoordinator({
    required CallsApi calls,
    required IdentityApi identity,
    required SettingsController settingsController,
    required ContactsController contactsController,
    required AppRestrictionController restrictionController,
    required AppCallRouteSync syncCallRoute,
    required AppMissedCallsBadgeRefresh refreshMissedCallsBadge,
    required void Function() showContactsTab,
    required void Function() showCallsTab,
    required void Function() showSettingsTab,
    required void Function() onServerSettingsMerged,
    required void Function() onAccountPairingRequestSent,
    required void Function(String displayName) onContactAdded,
    required void Function(String error) onError,
    DeepLinkService? deepLinkService,
  }) : _calls = calls,
       _identity = identity,
       _settingsController = settingsController,
       _contactsController = contactsController,
       _restrictionController = restrictionController,
       _syncCallRoute = syncCallRoute,
       _refreshMissedCallsBadge = refreshMissedCallsBadge,
       _showContactsTab = showContactsTab,
       _showCallsTab = showCallsTab,
       _showSettingsTab = showSettingsTab,
       _onServerSettingsMerged = onServerSettingsMerged,
       _onAccountPairingRequestSent = onAccountPairingRequestSent,
       _onContactAdded = onContactAdded,
       _onError = onError,
       _deepLinkService = deepLinkService ?? DeepLinkService.instance;

  final CallsApi _calls;
  final IdentityApi _identity;
  final SettingsController _settingsController;
  final ContactsController _contactsController;
  final AppRestrictionController _restrictionController;
  final AppCallRouteSync _syncCallRoute;
  final AppMissedCallsBadgeRefresh _refreshMissedCallsBadge;
  final void Function() _showContactsTab;
  final void Function() _showCallsTab;
  final void Function() _showSettingsTab;
  final void Function() _onServerSettingsMerged;
  final void Function() _onAccountPairingRequestSent;
  final void Function(String displayName) _onContactAdded;
  final void Function(String error) _onError;
  final DeepLinkService _deepLinkService;
  final Set<String> _handledDeepLinks = <String>{};
  StreamSubscription<String>? _subscription;

  void start() {
    _subscription = _deepLinkService.links.listen(
      (link) => unawaited(handle(link)),
      onError: (error, stackTrace) {
        AppFileLogger.log(
          '[ui] deepLink stream error=$error',
          name: 'ui',
          stackTrace: stackTrace is StackTrace ? stackTrace : null,
        );
      },
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }

  Future<void> handleInitial() async {
    final link = await _deepLinkService.initialLink();
    if (link == null || link.trim().isEmpty) {
      AppFileLogger.log('[ui] deepLink warning initial empty', name: 'ui');
      return;
    }
    AppFileLogger.log(
      '[ui] deepLink warning initial received length=${link.length}',
      name: 'ui',
    );
    await handle(link);
  }

  Future<void> handle(String rawLink) async {
    final link = extractDeepLinkCandidate(rawLink);
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
        await _handleCallDeepLink(uri);
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
        await _handleServerConfigDeepLink(link, serverConfigFromPayload);
        return;
      }

      if (_settingsController.isAccountPairingDeepLink(link)) {
        await _handleAccountPairingDeepLink(link);
        return;
      }

      await _handleInviteDeepLink(link);
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[ui] deepLink ignored link=$link error=$error',
        name: 'ui',
        stackTrace: stackTrace,
      );
      _onError(error.toString());
    }
  }

  Future<void> _handleCallDeepLink(Uri uri) async {
    if (_shouldDropExternalInteraction('deep_link_call')) {
      return;
    }
    final pushPayload = FirebasePushPayload.fromMap(
      Map<String, dynamic>.from(uri.queryParameters),
    );
    if (pushPayload.isCallEnd && pushPayload.hasPeerAndCallId) {
      await _calls.endCallFromRemotePush(
        peerId: pushPayload.callPeerId,
        callId: pushPayload.callId,
      );
      return;
    }
    if (pushPayload.isCallInvite && pushPayload.hasPeerAndCallId) {
      await _calls.presentIncomingCallFromPush(
        peerId: pushPayload.callPeerId,
        callId: pushPayload.callId,
        mediaType: pushPayload.callMediaType,
      );
      unawaited(_syncCallRoute(_calls.callState));
      return;
    }
    _showCallsTab();
    unawaited(_refreshMissedCallsBadge(markSeen: true));
  }

  Future<void> _handleServerConfigDeepLink(
    String link,
    ServerConfigPayload? serverConfigFromPayload,
  ) async {
    await _settingsController.initialize();
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
    _showSettingsTab();
    _onServerSettingsMerged();
  }

  Future<void> _handleAccountPairingDeepLink(String link) async {
    if (_shouldDropExternalInteraction('deep_link_pairing')) {
      return;
    }
    await _settingsController.initialize();
    await _settingsController.requestAccountPairingDeepLink(link);
    _showSettingsTab();
    _onAccountPairingRequestSent();
  }

  Future<void> _handleInviteDeepLink(String link) async {
    final invite = _settingsController.parseInviteDeepLink(link);
    if (_shouldDropExternalInteraction('deep_link_invite')) {
      return;
    }
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
    if (invite.peerId == _identity.peerId) {
      return;
    }
    final identityBundle = invite.identityBundleV3;
    if (identityBundle != null) {
      await _identity.trustPeerIdentityBundleV3(
        identityBundle,
        expectedPeerId: invite.peerId,
      );
    }
    final displayName = invite.displayName?.trim().isNotEmpty == true
        ? invite.displayName!.trim()
        : invite.peerId;
    await _contactsController.addOrUpdateContact(
      Contact(peerId: invite.peerId, name: displayName),
    );
    _showContactsTab();
    _onContactAdded(displayName);
  }

  bool _shouldDropExternalInteraction(String label) {
    return _restrictionController.shouldDropExternalInteraction(label);
  }

  static String extractDeepLinkCandidate(String raw) {
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
