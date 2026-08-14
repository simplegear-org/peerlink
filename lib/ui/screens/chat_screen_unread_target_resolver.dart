// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../models/message.dart';

class ChatScreenUnreadTargetResolver {
  const ChatScreenUnreadTargetResolver._();

  static bool containsMessage(List<Message> messages, String messageId) {
    return messages.any((message) => message.id == messageId);
  }

  static String? firstUnreadMessageId(
    List<Message> messages, {
    required bool Function(Message message) isInitialUnreadAnchor,
  }) {
    for (final message in messages) {
      if (isInitialUnreadAnchor(message)) {
        return message.id;
      }
    }
    return null;
  }
}
