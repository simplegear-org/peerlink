// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/chat/application/chat_history_load_coordinator.dart';

abstract interface class ChatHistoryApi {
  Future<void> initializeGroupKeys();

  Future<void> loadChats();

  Future<void> ensureChatLoaded(String peerId);

  Future<bool> loadMoreMessages(String peerId);

  Future<void> persistLoadedChat(String peerId);

  void schedulePersistLoadedChat(String peerId);

  Future<void> unloadChatMessages(String peerId);

  Future<int?> messageOffsetFromNewest(String peerId, String messageId);

  Future<String?> firstInitialUnreadMessageId(String peerId);

  Future<void> runGroupKeyGc();
}

final class ChatControllerHistoryApi implements ChatHistoryApi {
  const ChatControllerHistoryApi(this._coordinator);

  final ChatHistoryLoadCoordinator _coordinator;

  @override
  Future<void> initializeGroupKeys() => _coordinator.initializeGroupKeys();

  @override
  Future<void> loadChats() => _coordinator.loadChats();

  @override
  Future<void> ensureChatLoaded(String peerId) =>
      _coordinator.ensureChatLoaded(peerId);

  @override
  Future<bool> loadMoreMessages(String peerId) =>
      _coordinator.loadMoreMessages(peerId);

  @override
  Future<void> persistLoadedChat(String peerId) =>
      _coordinator.persistLoadedChat(peerId);

  @override
  void schedulePersistLoadedChat(String peerId) =>
      _coordinator.schedulePersistLoadedChat(peerId);

  @override
  Future<void> unloadChatMessages(String peerId) =>
      _coordinator.unloadChatMessages(peerId);

  @override
  Future<int?> messageOffsetFromNewest(String peerId, String messageId) =>
      _coordinator.messageOffsetFromNewest(peerId, messageId);

  @override
  Future<String?> firstInitialUnreadMessageId(String peerId) =>
      _coordinator.firstInitialUnreadMessageId(peerId);

  @override
  Future<void> runGroupKeyGc() => _coordinator.runGroupKeyGc();
}
