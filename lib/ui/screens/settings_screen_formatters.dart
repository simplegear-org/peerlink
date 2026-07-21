class SettingsScreenFormatters {
  static String formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 B';
    }
    const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex += 1;
    }
    final fractionDigits = value >= 100 || unitIndex == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${units[unitIndex]}';
  }

  static String shortId(String value) {
    final normalized = value.trim();
    if (normalized.length <= 12) {
      return normalized;
    }
    return '${normalized.substring(0, 6)}…${normalized.substring(normalized.length - 4)}';
  }

  static String formatDateTime(int timestampMs) {
    if (timestampMs <= 0) {
      return '—';
    }
    final value = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  static String formatRemainingTime(int expiresAtMs) {
    final remainingMs = expiresAtMs - DateTime.now().millisecondsSinceEpoch;
    final remainingSeconds = remainingMs <= 0 ? 0 : remainingMs ~/ 1000;
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
