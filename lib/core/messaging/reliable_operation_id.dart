// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class ReliableOperationId {
  const ReliableOperationId._();

  static String pendingMessage({
    required bool isGroup,
    required String targetId,
    String? messageId,
  }) {
    final prefix = isGroup ? 'group' : 'direct';
    final effectiveMessageId =
        messageId ?? DateTime.now().microsecondsSinceEpoch.toString();
    return '$prefix:$targetId:$effectiveMessageId';
  }
}
