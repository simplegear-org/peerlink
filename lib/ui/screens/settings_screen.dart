// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/runtime/self_hosted_deploy_service.dart';
import '../../core/runtime/avatar_service.dart';
import '../../core/runtime/moderation_policy_service.dart';
import '../state/app_appearance_controller.dart';
import '../state/app_locale_controller.dart';
import '../state/chat_controller.dart';
import '../state/settings_controller.dart';
import '../localization/app_strings.dart';
import 'settings_screen_avatar_actions.dart';
import 'settings_screen_content.dart';
import 'settings_screen_pairing_actions.dart';
import 'settings_screen_system_actions.dart';

/// Экран системных настроек: peer id и список bootstrap-серверов.
class SettingsScreen extends StatefulWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final ChatController chatController;
  final SelfHostedDeployService selfHostedDeployService;
  final AppAppearanceController appearanceController;
  final AppLocaleController localeController;
  final ModerationPolicySnapshot moderationPolicy;

  const SettingsScreen({
    super.key,
    required this.controller,
    required this.avatarService,
    required this.chatController,
    required this.selfHostedDeployService,
    required this.appearanceController,
    required this.localeController,
    required this.moderationPolicy,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  StreamSubscription? _connectionStatusSubscription;
  StreamSubscription? _errorSubscription;
  StreamSubscription<String>? _avatarSubscription;
  Timer? _pairingRefreshTimer;
  bool _pendingPairingPromptShown = false;
  late final SettingsScreenAvatarActions _avatarActions;
  late final SettingsScreenPairingActions _pairingActions;
  late final SettingsScreenSystemActions _systemActions;

  SettingsController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _avatarActions = SettingsScreenAvatarActions(
      avatarService: widget.avatarService,
      isMounted: () => mounted,
    );
    _pairingActions = SettingsScreenPairingActions(
      controller: controller,
      isMounted: () => mounted,
      refreshUi: _refreshUi,
    );
    _systemActions = SettingsScreenSystemActions(
      controller: controller,
      avatarService: widget.avatarService,
      chatController: widget.chatController,
      selfHostedDeployService: widget.selfHostedDeployService,
      isMounted: () => mounted,
      refreshUi: _refreshUi,
    );
    controller.initialize().then((_) {
      if (!mounted) return;
      _refreshUi();
      _startPairingRefresh();
      _pairingActions.tryApplyApprovedPairing(context);
      _showPendingPairingPromptIfNeeded();
    });
    _connectionStatusSubscription = controller.connectionStatusStream.listen((
      _,
    ) {
      if (!mounted) return;
      setState(() {});
    });
    _errorSubscription = controller.lastErrorStream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
    _avatarSubscription = widget.avatarService.updatesStream.listen((_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  void _startPairingRefresh() {
    _pairingRefreshTimer?.cancel();
    _pairingRefreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pairingActions.tryApplyApprovedPairing(context);
    });
  }

  void _showPendingPairingPromptIfNeeded() {
    _pairingActions
        .showPendingPairingPromptIfNeeded(
          context,
          promptShown: _pendingPairingPromptShown,
        )
        .then((value) {
          _pendingPairingPromptShown = value;
        });
  }

  @override
  void dispose() {
    _pairingRefreshTimer?.cancel();
    _connectionStatusSubscription?.cancel();
    _errorSubscription?.cancel();
    _avatarSubscription?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.strings.settings)),
      body: SettingsScreenContent(
        controller: controller,
        avatarService: widget.avatarService,
        moderationPolicy: widget.moderationPolicy,
        appearanceController: widget.appearanceController,
        localeController: widget.localeController,
        onShowAvatarActions: () => _avatarActions.showAvatarActions(context),
        onShowAccountPairingSheet: () =>
            _pairingActions.showAccountPairingSheet(context),
        onScanAccountPairingQr: () =>
            _pairingActions.scanAccountPairingQr(context),
        onOpenAccountDevices: () => _systemActions.openAccountDevices(context),
        onOpenAccountDeviceHistory: () =>
            _systemActions.openAccountDeviceHistory(context),
        onInstallSelfHostedServers: () =>
            _systemActions.installSelfHostedServers(context),
        onSetShareServersInPush: (value) async {
          await controller.setShareServersInPush(value);
          _refreshUi();
        },
        onSetReceiveServersFromPush: (value) async {
          await controller.setReceiveServersFromPush(value);
          _refreshUi();
        },
        onSetAllowMessagesOnlyFromContacts: (value) async {
          await controller.setAllowMessagesOnlyFromContacts(value);
          _refreshUi();
        },
        onOpenBlockedUsers: () => _systemActions.openBlockedUsers(context),
        onOpenPushServers: () => _systemActions.openPushServers(context),
        onOpenBootstrapServers: () =>
            _systemActions.openBootstrapServers(context),
        onOpenRelayServers: () => _systemActions.openRelayServers(context),
        onOpenTurnServers: () => _systemActions.openTurnServers(context),
        onScanServerConfigQr: () => _systemActions.scanServerConfigQr(context),
        onShareServerConfigQr: () =>
            _systemActions.shareServerConfigQr(context),
        onOpenStorageDetails: () => _systemActions.openStorageDetails(context),
        onShowAppLogPreview: () => _systemActions.showAppLogPreview(context),
        onShareAppLog: () => _systemActions.shareAppLog(context),
        onClearAppLog: () => _systemActions.clearAppLog(context),
        onSetAppLogLevel: (level) async {
          await controller.setAppLogLevel(level);
          _refreshUi();
        },
        onConfirmResetLocalAccount: () =>
            _systemActions.confirmResetLocalAccount(context),
        onConfirmResetDeviceCompletely: () =>
            _systemActions.confirmResetDeviceCompletely(context),
        onApproveIncomingPairingRequest: (request) =>
            _pairingActions.approveIncomingPairingRequest(context, request),
        onRejectIncomingPairingRequest: (request) =>
            _pairingActions.rejectIncomingPairingRequest(context, request),
      ),
    );
  }

  void _refreshUi() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }
}
