// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'chat_database.dart';

abstract class ChatSummaryStore {
  Future<List<Map<String, dynamic>>> loadAll();

  Future<Map<String, dynamic>?> get(String peerId);

  Future<void> save(String peerId, Map<String, dynamic> json);

  Future<void> delete(String peerId);

  Future<int> unreadMessagesCount();
}

class ChatDatabaseSummaryStore implements ChatSummaryStore {
  const ChatDatabaseSummaryStore();

  @override
  Future<List<Map<String, dynamic>>> loadAll() {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getAllChatSummariesAsJson(),
      operation: 'loadAllChatSummaries',
    );
  }

  @override
  Future<Map<String, dynamic>?> get(String peerId) {
    return ChatDatabaseService.runWithRecovery(
      (database) => database.getChatSummaryAsJson(peerId),
      operation: 'getChatSummary($peerId)',
    );
  }

  @override
  Future<void> save(String peerId, Map<String, dynamic> json) async {
    await ChatDatabaseService.runWithRecovery(
      (database) => database.upsertChatSummary(peerId, json),
      operation: 'saveChatSummaryMap($peerId)',
    );
  }

  @override
  Future<void> delete(String peerId) async {
    await ChatDatabaseService.runWithRecovery(
      (database) => database.deleteChatSummary(peerId),
      operation: 'deleteChatSummaryMap($peerId)',
    );
  }

  @override
  Future<int> unreadMessagesCount() async {
    final summaries = await loadAll();
    return summaries.fold<int>(0, (sum, summary) {
      final value = summary['unreadCount'];
      if (value is int) {
        return sum + value;
      }
      if (value is num) {
        return sum + value.toInt();
      }
      return sum + (int.tryParse(value?.toString() ?? '') ?? 0);
    });
  }
}
