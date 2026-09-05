// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/calls/call_log_entry.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/node/node_capability_apis.dart';
import 'package:peerlink/features/calls/platform/ios_callkit_service.dart';

typedef AppCallRouteSync = Future<void> Function(CallState state);
typedef AppCallErrorPresenter = void Function(String error);
typedef AppCallHistoryChanged = void Function();
typedef AppCallMissedBadgeRefresh =
    Future<void> Function({required bool markSeen});
typedef AppCallRecorder = Future<void> Function(CallState state);
typedef AppCallLogStatusResolver = CallLogStatus Function(CallState state);

class AppCallCoordinator {
  AppCallCoordinator({
    required CallsApi calls,
    required bool Function() canHandleExternalInteraction,
    required AppCallRecorder recordCall,
    required AppCallLogStatusResolver logStatusFor,
    required AppCallRouteSync syncCallRoute,
    required AppCallMissedBadgeRefresh refreshMissedCallsBadge,
    required bool Function() isCallsTabSelected,
    required void Function() showCallsTab,
    void Function(CallState state)? onCallStateChanged,
    required AppCallHistoryChanged onHistoryChanged,
    required AppCallErrorPresenter showError,
    IosCallkitService? iosCallkitService,
  }) : _calls = calls,
       _canHandleExternalInteraction = canHandleExternalInteraction,
       _recordCall = recordCall,
       _logStatusFor = logStatusFor,
       _syncCallRoute = syncCallRoute,
       _refreshMissedCallsBadge = refreshMissedCallsBadge,
       _isCallsTabSelected = isCallsTabSelected,
       _showCallsTab = showCallsTab,
       _onCallStateChanged = onCallStateChanged,
       _onHistoryChanged = onHistoryChanged,
       _showError = showError,
       _iosCallkitService = iosCallkitService ?? IosCallkitService.instance,
       currentState = calls.callState;

  final CallsApi _calls;
  final bool Function() _canHandleExternalInteraction;
  final AppCallRecorder _recordCall;
  final AppCallLogStatusResolver _logStatusFor;
  final AppCallRouteSync _syncCallRoute;
  final AppCallMissedBadgeRefresh _refreshMissedCallsBadge;
  final bool Function() _isCallsTabSelected;
  final void Function() _showCallsTab;
  final void Function(CallState state)? _onCallStateChanged;
  final AppCallHistoryChanged _onHistoryChanged;
  final AppCallErrorPresenter _showError;
  final IosCallkitService _iosCallkitService;
  StreamSubscription<CallState>? _callStateSubscription;
  StreamSubscription<void>? _openCallScreenSubscription;
  String? _lastRecordedCallId;

  CallState currentState;

  void start() {
    _openCallScreenSubscription = _iosCallkitService.onOpenCallScreen.listen((
      _,
    ) {
      if (!_canHandleExternalInteraction()) {
        return;
      }
      _showCallsTab();
      unawaited(_refreshMissedCallsBadge(markSeen: true));
      unawaited(_syncCallRoute(currentState));
    });
    _callStateSubscription = _calls.callStateStream.listen((state) {
      currentState = state;
      _onCallStateChanged?.call(state);
      unawaited(_syncCallRoute(state));
      unawaited(_maybeRecordCall(state));
      if (state.phase == CallPhase.failed && state.error != null) {
        _showError(state.error!);
      }
    });
  }

  Future<void> dispose() async {
    await _callStateSubscription?.cancel();
    await _openCallScreenSubscription?.cancel();
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
    await _recordCall(next);
    final status = _logStatusFor(next);
    _onHistoryChanged();
    await _refreshMissedCallsBadge(
      markSeen: _isCallsTabSelected() && status != CallLogStatus.missed,
    );
  }
}
