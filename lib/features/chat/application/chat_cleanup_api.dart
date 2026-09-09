// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/features/chat/application/chat_cleanup_coordinator.dart';

abstract interface class ChatCleanupApi {
  Future<void> clearManagedMediaReferencesInMemory();

  void clearAllChatsFromMemory();

  Future<void> deleteMessage(String peerId, String messageId);

  Future<void> deleteChat(String peerId);
}

final class ChatControllerCleanupApi implements ChatCleanupApi {
  const ChatControllerCleanupApi(this._coordinator);

  final ChatCleanupCoordinator _coordinator;

  @override
  Future<void> clearManagedMediaReferencesInMemory() =>
      _coordinator.clearManagedMediaReferencesInMemory();

  @override
  void clearAllChatsFromMemory() => _coordinator.clearAllChatsFromMemory();

  @override
  Future<void> deleteMessage(String peerId, String messageId) =>
      _coordinator.deleteMessage(peerId, messageId);

  @override
  Future<void> deleteChat(String peerId) => _coordinator.deleteChat(peerId);
}
