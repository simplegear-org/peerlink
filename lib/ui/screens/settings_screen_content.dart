// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:flutter/material.dart';

import '../../core/runtime/app_file_logger.dart';
import '../../core/runtime/avatar_service.dart';
import '../../core/runtime/moderation_policy_service.dart';
import '../localization/app_strings.dart';
import '../state/app_appearance_controller.dart';
import '../state/app_locale_controller.dart';
import '../state/settings_controller.dart';
import 'settings_screen_account_sections.dart';
import 'settings_screen_preferences_sections.dart';
import 'settings_screen_server_sections.dart';
import 'settings_screen_styles.dart';

class SettingsScreenContent extends StatelessWidget {
  final SettingsController controller;
  final AvatarService avatarService;
  final ModerationPolicySnapshot moderationPolicy;
  final AppAppearanceController appearanceController;
  final AppLocaleController localeController;
  final Future<void> Function() onShowAvatarActions;
  final Future<void> Function() onShowAccountPairingSheet;
  final Future<void> Function() onScanAccountPairingQr;
  final Future<void> Function() onOpenAccountDevices;
  final Future<void> Function() onOpenAccountDeviceHistory;
  final Future<void> Function() onInstallSelfHostedServers;
  final Future<void> Function(bool value) onSetShareServersInPush;
  final Future<void> Function(bool value) onSetReceiveServersFromPush;
  final Future<void> Function(bool value) onSetAllowMessagesOnlyFromContacts;
  final Future<void> Function() onOpenBlockedUsers;
  final Future<void> Function() onOpenPushServers;
  final Future<void> Function() onOpenBootstrapServers;
  final Future<void> Function() onOpenRelayServers;
  final Future<void> Function() onOpenTurnServers;
  final Future<void> Function() onScanServerConfigQr;
  final Future<void> Function() onShareServerConfigQr;
  final Future<void> Function() onOpenStorageDetails;
  final Future<void> Function() onShowAppLogPreview;
  final Future<void> Function() onShareAppLog;
  final Future<void> Function() onClearAppLog;
  final Future<void> Function(AppLogLevel level) onSetAppLogLevel;
  final Future<void> Function() onConfirmResetLocalAccount;
  final Future<void> Function() onConfirmResetDeviceCompletely;
  final Future<void> Function(IncomingAccountPairingRequest request)
  onApproveIncomingPairingRequest;
  final Future<void> Function(IncomingAccountPairingRequest request)
  onRejectIncomingPairingRequest;

  const SettingsScreenContent({
    super.key,
    required this.controller,
    required this.avatarService,
    required this.moderationPolicy,
    required this.appearanceController,
    required this.localeController,
    required this.onShowAvatarActions,
    required this.onShowAccountPairingSheet,
    required this.onScanAccountPairingQr,
    required this.onOpenAccountDevices,
    required this.onOpenAccountDeviceHistory,
    required this.onInstallSelfHostedServers,
    required this.onSetShareServersInPush,
    required this.onSetReceiveServersFromPush,
    required this.onSetAllowMessagesOnlyFromContacts,
    required this.onOpenBlockedUsers,
    required this.onOpenPushServers,
    required this.onOpenBootstrapServers,
    required this.onOpenRelayServers,
    required this.onOpenTurnServers,
    required this.onScanServerConfigQr,
    required this.onShareServerConfigQr,
    required this.onOpenStorageDetails,
    required this.onShowAppLogPreview,
    required this.onShareAppLog,
    required this.onClearAppLog,
    required this.onSetAppLogLevel,
    required this.onConfirmResetLocalAccount,
    required this.onConfirmResetDeviceCompletely,
    required this.onApproveIncomingPairingRequest,
    required this.onRejectIncomingPairingRequest,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: SettingsScreenStyles.screenPadding,
      children: [
        SettingsIdentitySection(
          controller: controller,
          avatarService: avatarService,
          moderationPolicy: moderationPolicy,
          onShowAvatarActions: onShowAvatarActions,
        ),
        SettingsPrivacySection(
          controller: controller,
          onSetAllowMessagesOnlyFromContacts:
              onSetAllowMessagesOnlyFromContacts,
          onOpenBlockedUsers: onOpenBlockedUsers,
        ),
        SettingsSelfHostedSection(
          onInstallSelfHostedServers: onInstallSelfHostedServers,
        ),
        SettingsPushServerSharingSection(
          controller: controller,
          onSetShareServersInPush: onSetShareServersInPush,
          onSetReceiveServersFromPush: onSetReceiveServersFromPush,
        ),
        SettingsServerSummaryStreamSection(
          title: context.strings.pushServersTitle,
          description: context.strings.pushSummary,
          onTap: onOpenPushServers,
          updates: controller.pushAvailabilityStream,
          availableCount: () => controller.pushServers
              .where(
                (endpoint) =>
                    controller.pushState(endpoint) ==
                    SettingsServerState.connected,
              )
              .length,
          unavailableCount: () => controller.pushServers
              .where(
                (endpoint) =>
                    controller.pushState(endpoint) ==
                    SettingsServerState.unavailable,
              )
              .length,
        ),
        SettingsServerSummaryStreamSection(
          title: context.strings.bootstrapServersTitle,
          description: context.strings.bootstrapSummary,
          onTap: onOpenBootstrapServers,
          updates: controller.bootstrapAvailabilityStream,
          availableCount: () => controller.bootstrapAvailableCount,
          unavailableCount: () => controller.bootstrapUnavailableCount,
        ),
        SettingsServerSummaryStreamSection(
          title: context.strings.relayServersTitle,
          description: context.strings.relaySummary,
          onTap: onOpenRelayServers,
          updates: controller.relayAvailabilityStream,
          availableCount: () => controller.relayAvailableCount,
          unavailableCount: () => controller.relayUnavailableCount,
        ),
        SettingsServerSummaryStreamSection(
          title: context.strings.turnServersTitle,
          description: context.strings.turnSummary,
          onTap: onOpenTurnServers,
          updates: controller.turnAvailabilityStream,
          availableCount: () => controller.turnAvailableCount,
          unavailableCount: () => controller.turnUnavailableCount,
        ),
        SettingsServerQrSection(
          controller: controller,
          onScanServerConfigQr: onScanServerConfigQr,
          onShareServerConfigQr: onShareServerConfigQr,
        ),
        SettingsStorageSection(
          controller: controller,
          onOpenStorageDetails: onOpenStorageDetails,
        ),
        SettingsAppearanceSection(appearanceController: appearanceController),
        SettingsLanguageSection(localeController: localeController),
        SettingsLegalSection(controller: controller),
        SettingsAppLogSection(
          controller: controller,
          onShowAppLogPreview: onShowAppLogPreview,
          onShareAppLog: onShareAppLog,
          onClearAppLog: onClearAppLog,
          onSetAppLogLevel: onSetAppLogLevel,
        ),
        SettingsDataResetSection(
          onConfirmResetLocalAccount: onConfirmResetLocalAccount,
          onConfirmResetDeviceCompletely: onConfirmResetDeviceCompletely,
        ),
      ],
    );
  }
}
