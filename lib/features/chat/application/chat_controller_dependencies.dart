// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/application/chat_contacts_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_controller_ports.dart';
import 'package:peerlink/features/chat/application/chat_cleanup_api.dart';
import 'package:peerlink/features/chat/application/chat_direct_lifecycle_service.dart';
import 'package:peerlink/features/chat/application/chat_groups_api.dart';
import 'package:peerlink/features/chat/application/chat_history_api.dart';
import 'package:peerlink/features/chat/application/chat_inbound_service.dart';
import 'package:peerlink/features/chat/application/chat_inbound_subscription_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_media_api.dart';
import 'package:peerlink/features/chat/application/chat_messages_api.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/application/chat_safety_api.dart';
import 'package:peerlink/features/chat/application/chat_summary_service.dart';
import 'package:peerlink/features/profile/application/profile_inbound_handler.dart';

class ChatControllerDependencies {
  const ChatControllerDependencies({
    required this.persistence,
    required this.messaging,
    required this.groups,
    required this.mediaLifecycle,
    required this.safety,
  });

  final ChatPersistenceDependencies persistence;
  final ChatMessagingDependencies messaging;
  final ChatGroupDependencies groups;
  final ChatMediaLifecycleDependencies mediaLifecycle;
  final ChatSafetyDependencies safety;
}

class ChatPersistenceDependencies {
  const ChatPersistenceDependencies({
    required this.summaryService,
    required this.historyApi,
  });

  final ChatSummaryService summaryService;
  final ChatHistoryApi historyApi;
}

class ChatMessagingDependencies {
  const ChatMessagingDependencies({
    required this.outboundCodec,
    required this.messagesApi,
  });

  final ChatOutboundCodec outboundCodec;
  final ChatMessagesApi messagesApi;
}

class ChatGroupDependencies {
  const ChatGroupDependencies({
    required this.contactsService,
    required this.groupsApi,
  });

  final ChatContactsService contactsService;
  final ChatGroupsApi groupsApi;
}

class ChatMediaLifecycleDependencies {
  const ChatMediaLifecycleDependencies({
    required this.directLifecycleService,
    required this.lifecycleService,
    required this.mediaApi,
    required this.cleanupApi,
    required this.inboundService,
    required this.inboundSubscriptionCoordinator,
  });

  final ChatDirectLifecycleService directLifecycleService;
  final ChatControllerLifecycleService lifecycleService;
  final ChatMediaApi mediaApi;
  final ChatCleanupApi cleanupApi;
  final ChatInboundService inboundService;
  final ChatInboundSubscriptionCoordinator inboundSubscriptionCoordinator;
}

class ChatSafetyDependencies {
  const ChatSafetyDependencies({required this.safetyApi});

  final ChatSafetyApi safetyApi;
}

typedef ChatControllerDependenciesFactory =
    ChatControllerDependencies Function({
      required ChatRuntimeApi runtime,
      required StorageService storage,
      required ProfileInboundHandler avatarService,
      required ChatPresentationStatePort presentationState,
      required ChatConnectionStatePort connectionState,
      required ChatMessageStatePort messageState,
      required ChatMediaStatePort mediaState,
      required ChatGroupStatePort groupState,
      required ChatNotificationPort notifications,
      required ChatLifecyclePort lifecycle,
      required ChatInboundPort inbound,
      required ChatAccountPayloadPort accountPayloads,
    });
