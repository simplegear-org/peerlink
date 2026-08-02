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
