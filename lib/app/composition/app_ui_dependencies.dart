// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';
import 'dart:developer' as developer;

import 'package:peerlink/app/badges/app_badge_coordinator.dart';
import 'package:peerlink/app/composition/chat_controller_composition.dart';
import 'package:peerlink/app/composition/chat_runtime_node_adapter.dart';
import 'package:peerlink/app/composition/profile_avatar_node_adapter.dart';
import 'package:peerlink/app/composition/settings_controller_composition.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/notification/app_badge_service.dart';
import 'package:peerlink/features/calls/platform/android_call_notification_service.dart';
import 'package:peerlink/features/profile/application/avatar_service.dart';
import 'package:peerlink/features/calls/infrastructure/call_log_repository.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/features/moderation/application/moderation_lifecycle_service.dart';
import 'package:peerlink/features/moderation/application/moderation_report_service.dart';
import 'package:peerlink/features/moderation/application/peer_access_control_service.dart';
import 'package:peerlink/features/moderation/infrastructure/storage_moderation_report_outbox.dart';
import 'package:peerlink/core/runtime/self_hosted_deploy_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/ui/state/app_restriction_controller.dart';
import 'package:peerlink/ui/state/calls_controller.dart';
import 'package:peerlink/ui/state/chat_controller.dart';
import 'package:peerlink/ui/state/contacts_controller.dart';
import 'package:peerlink/ui/state/presence_service.dart';
import 'package:peerlink/ui/state/settings_controller.dart';
import 'package:peerlink/ui/state/ui_app_controller.dart';

class AppUiDependencies {
  AppUiDependencies._({
    required this.appBadgeService,
    required this.badgeCoordinator,
    required this.androidCallNotifications,
    required this.avatarService,
    required this.chatController,
    required this.contactsRepository,
    required this.accessControl,
    required this.callLogRepository,
    required this.callsController,
    required this.contactsController,
    required this.moderationLifecycleService,
    required this.settingsController,
    required this.restrictionController,
    required this.selfHostedDeployService,
    required this.presenceService,
    required this.appController,
  });

  factory AppUiDependencies.create({
    required NodeFacade facade,
    required StorageService storage,
  }) {
    const chatSummaryStore = ChatDatabaseSummaryStore();
    final appBadgeService = AppBadgeService(
      storage: storage,
      loadUnreadMessagesCount: chatSummaryStore.unreadMessagesCount,
    );
    final avatarService = AvatarService(
      transport: ProfileAvatarNodeAdapter(facade),
      storage: storage,
      chatSummaryStore: chatSummaryStore,
    );
    final contactsRepository = ContactsRepository(storage: storage);
    final accessControl = PeerAccessControlService(
      settingsBox: storage.getSettings(),
      contactsRepository: contactsRepository,
    );
    final moderationReports = ModerationReportService(
      settingsBox: storage.getSettings(),
      outbox: StorageModerationReportOutbox(storage.getSettings()),
      localPeerId: () => facade.peerId,
      deliverReport: facade.submitModerationReport,
    );
    final moderationLifecycleService = ModerationLifecycleService(
      reports: moderationReports,
      log: (message) => developer.log(message, name: 'moderation'),
    )..start();
    final callLogRepository = CallLogRepository(storage: storage);
    final callsController = CallsController(repository: callLogRepository);
    final contactsController = ContactsController(
      repository: contactsRepository,
      accessControl: accessControl,
      onAccessPolicyChanged: (reason) {
        unawaited(
          facade.syncPushDeviceState(reason: reason, forcePolicy: true),
        );
      },
      onAccessPolicyChangedNow: (reason) {
        return facade.syncPushDeviceState(reason: reason, forcePolicy: true);
      },
    );
    contactsController.loadIntoMemory();
    final settingsController = SettingsController(
      identity: facade,
      network: facade,
      messaging: facade,
      storage: storage,
      dependenciesFactory: SettingsControllerComposition.create,
    );
    final badgeCoordinator = AppBadgeCoordinator(
      appBadgeService: appBadgeService,
      callsController: callsController,
    );
    final chatController = ChatController(
      ChatRuntimeNodeAdapter(facade),
      storage: storage,
      avatarService: avatarService,
      dependenciesFactory: ChatControllerComposition.create,
      onUnreadBadgeCountChanged: (unreadCount) {
        badgeCoordinator.syncAppIconBadge(unreadMessagesOverride: unreadCount);
      },
    );
    badgeCoordinator.unreadMessagesCount = chatController.unreadMessagesCount;
    final restrictionController = AppRestrictionController(
      identity: facade,
      moderation: facade,
      calls: facade,
      settingsController: settingsController,
      storage: storage,
    );
    final appController = UiAppController(
      contactsRepository: contactsRepository,
      callLogRepository: callLogRepository,
      contactsController: contactsController,
    );
    return AppUiDependencies._(
      appBadgeService: appBadgeService,
      badgeCoordinator: badgeCoordinator,
      androidCallNotifications: const AndroidCallNotificationService(),
      avatarService: avatarService,
      chatController: chatController,
      contactsRepository: contactsRepository,
      accessControl: accessControl,
      callLogRepository: callLogRepository,
      callsController: callsController,
      contactsController: contactsController,
      moderationLifecycleService: moderationLifecycleService,
      settingsController: settingsController,
      restrictionController: restrictionController,
      selfHostedDeployService: SelfHostedDeployService(),
      presenceService: PresenceService(presence: facade),
      appController: appController,
    );
  }

  final AppBadgeService appBadgeService;
  final AppBadgeCoordinator badgeCoordinator;
  final AndroidCallNotificationService androidCallNotifications;
  final AvatarService avatarService;
  final ChatController chatController;
  final ContactsRepository contactsRepository;
  final PeerAccessControlService accessControl;
  final CallLogRepository callLogRepository;
  final CallsController callsController;
  final ContactsController contactsController;
  final ModerationLifecycleService moderationLifecycleService;
  final SettingsController settingsController;
  final AppRestrictionController restrictionController;
  final SelfHostedDeployService selfHostedDeployService;
  final PresenceService presenceService;
  final UiAppController appController;

  Future<void> dispose() async {
    await moderationLifecycleService.dispose();
    await avatarService.dispose();
    await presenceService.dispose();
  }
}
