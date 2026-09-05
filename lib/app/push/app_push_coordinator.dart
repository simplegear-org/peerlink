// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/firebase/firebase_messaging_service.dart';
import 'package:peerlink/core/firebase/firebase_push_payload.dart';
import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:peerlink/core/runtime/moderation_policy_service.dart';

typedef AppExternalInteractionGate = bool Function(String label);
typedef AppOpenedPushDropper =
    bool Function(FirebasePushPayload payload, {required String source});
typedef AppGroupMembersPushHandler =
    Future<void> Function(Map<String, dynamic> payload, {String? sourcePeerId});
typedef AppModerationPolicyPushHandler =
    Future<void> Function(
      ModerationPolicySnapshot snapshot, {
      required String source,
    });
typedef AppCallRouteSync = Future<void> Function(CallState state);
typedef AppMissedCallsBadgeRefresh =
    Future<void> Function({required bool markSeen});

class AppPushCoordinator {
  AppPushCoordinator({
    required CallsApi calls,
    required NetworkApi network,
    required AppGroupMembersPushHandler onGroupMembersUpdate,
    required AppModerationPolicyPushHandler onModerationPolicy,
    required AppExternalInteractionGate shouldDropExternalInteraction,
    required AppOpenedPushDropper shouldDropOpenedPush,
    required AppMissedCallsBadgeRefresh refreshMissedCallsBadge,
    required AppCallRouteSync syncCallRoute,
    required bool Function() canHandleExternalInteraction,
    required void Function() showCallsTab,
    required void Function() showChatsTab,
  }) : _calls = calls,
       _network = network,
       _onGroupMembersUpdate = onGroupMembersUpdate,
       _onModerationPolicy = onModerationPolicy,
       _shouldDropExternalInteraction = shouldDropExternalInteraction,
       _shouldDropOpenedPush = shouldDropOpenedPush,
       _refreshMissedCallsBadge = refreshMissedCallsBadge,
       _syncCallRoute = syncCallRoute,
       _canHandleExternalInteraction = canHandleExternalInteraction,
       _showCallsTab = showCallsTab,
       _showChatsTab = showChatsTab;

  final CallsApi _calls;
  final NetworkApi _network;
  final AppGroupMembersPushHandler _onGroupMembersUpdate;
  final AppModerationPolicyPushHandler _onModerationPolicy;
  final AppExternalInteractionGate _shouldDropExternalInteraction;
  final AppOpenedPushDropper _shouldDropOpenedPush;
  final AppMissedCallsBadgeRefresh _refreshMissedCallsBadge;
  final AppCallRouteSync _syncCallRoute;
  final bool Function() _canHandleExternalInteraction;
  final void Function() _showCallsTab;
  final void Function() _showChatsTab;
  bool _registered = false;

  void register() {
    if (_registered) {
      return;
    }
    _registered = true;
    FirebaseMessagingService.onGroupMembersUpdateFromPush =
        _handleGroupMembersUpdate;
    FirebaseMessagingService.onPushOpened = _handlePushOpened;
    FirebaseMessagingService.onModerationPolicyFromPush =
        _handleModerationPolicy;
  }

  void dispose() {
    if (!_registered) {
      return;
    }
    FirebaseMessagingService.onGroupMembersUpdateFromPush = null;
    FirebaseMessagingService.onModerationPolicyFromPush = null;
    FirebaseMessagingService.onPushOpened = null;
    _registered = false;
  }

  Future<void> _handleGroupMembersUpdate(
    Map<String, dynamic> payload, {
    String? sourcePeerId,
  }) {
    if (_shouldDropExternalInteraction('group_members_push')) {
      return Future<void>.value();
    }
    return _onGroupMembersUpdate(payload, sourcePeerId: sourcePeerId);
  }

  Future<void> _handleModerationPolicy(
    ModerationPolicySnapshot snapshot, {
    required String source,
  }) {
    return _onModerationPolicy(snapshot, source: source);
  }

  Future<void> _handlePushOpened(
    Map<String, dynamic> data, {
    required String source,
  }) async {
    if (_shouldDropExternalInteraction('push_open source=$source')) {
      return;
    }
    final pushPayload = FirebasePushPayload.fromMap(data);
    if (_shouldDropOpenedPush(pushPayload, source: source)) {
      return;
    }
    if (pushPayload.isCallEnd && pushPayload.hasPeerAndCallId) {
      await _calls.endCallFromRemotePush(
        peerId: pushPayload.callPeerId,
        callId: pushPayload.callId,
      );
      return;
    }
    if (pushPayload.isCallInvite) {
      if (pushPayload.hasPeerAndCallId) {
        await _calls.presentIncomingCallFromPush(
          peerId: pushPayload.callPeerId,
          callId: pushPayload.callId,
          mediaType: pushPayload.callMediaType,
        );
        if (!_canHandleExternalInteraction()) {
          return;
        }
        _showCallsTab();
        unawaited(_refreshMissedCallsBadge(markSeen: true));
        unawaited(_syncCallRoute(_calls.callState));
      }
      return;
    }
    await _pollRelayForOpenedPush(pushPayload, source: source);
    if (source == 'foreground') {
      return;
    }
    _showChatsTab();
  }

  Future<void> _pollRelayForOpenedPush(
    FirebasePushPayload pushPayload, {
    required String source,
  }) async {
    final hintedRelayServers = <String>{
      ...pushPayload.relayServers,
      ...pushPayload.availableRelayServers,
    }.toList(growable: false)..sort();
    AppFileLogger.log(
      '[app_push] push relay poll start type=${pushPayload.type} '
      'source=$source group=${pushPayload.groupId} '
      'relayMessage=${pushPayload.relayMessageId} '
      'hints=${hintedRelayServers.length} hintServers=$hintedRelayServers',
      name: 'app_push',
    );
    var fetchedCount = 0;
    if (hintedRelayServers.isNotEmpty) {
      try {
        fetchedCount += await _network.pollRelay(
          relayServers: hintedRelayServers,
        );
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[app_push] push open hinted pollRelay failed '
          'type=${pushPayload.type} source=$source '
          'hints=${hintedRelayServers.length} error=$error',
          name: 'app_push',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    try {
      fetchedCount += await _network.pollRelay();
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[app_push] push open full pollRelay failed '
        'type=${pushPayload.type} source=$source error=$error',
        name: 'app_push',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (source == 'foreground') {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      try {
        fetchedCount += await _network.pollRelay(
          relayServers: hintedRelayServers.isEmpty ? null : hintedRelayServers,
        );
      } catch (error, stackTrace) {
        AppFileLogger.log(
          '[app_push] push foreground retry pollRelay failed '
          'type=${pushPayload.type} hints=${hintedRelayServers.length} '
          'error=$error',
          name: 'app_push',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    if (pushPayload.relayMessageId.isNotEmpty && fetchedCount == 0) {
      AppFileLogger.log(
        '[app_push] push relay poll miss type=${pushPayload.type} '
        'source=$source group=${pushPayload.groupId} '
        'relayMessage=${pushPayload.relayMessageId} '
        'hints=${hintedRelayServers.length} hintServers=$hintedRelayServers',
        name: 'app_push',
      );
    }
  }
}
