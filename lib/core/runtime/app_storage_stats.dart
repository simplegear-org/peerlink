// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

enum AppStorageCategory {
  mediaFiles,
  messagesDatabase,
  logs,
  settingsAndServiceData,
}

class AppStorageBreakdown {
  final int mediaFilesBytes;
  final int messagesDatabaseBytes;
  final int logsBytes;
  final int settingsAndServiceDataBytes;

  const AppStorageBreakdown({
    required this.mediaFilesBytes,
    required this.messagesDatabaseBytes,
    required this.logsBytes,
    required this.settingsAndServiceDataBytes,
  });

  int get totalBytes =>
      mediaFilesBytes +
      messagesDatabaseBytes +
      logsBytes +
      settingsAndServiceDataBytes;

  int bytesFor(AppStorageCategory category) {
    switch (category) {
      case AppStorageCategory.mediaFiles:
        return mediaFilesBytes;
      case AppStorageCategory.messagesDatabase:
        return messagesDatabaseBytes;
      case AppStorageCategory.logs:
        return logsBytes;
      case AppStorageCategory.settingsAndServiceData:
        return settingsAndServiceDataBytes;
    }
  }
}
