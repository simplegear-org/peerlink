class ChatScreenMimeType {
  const ChatScreenMimeType._();

  static String forPath(String fileName, String fallbackName) {
    final lower = (fileName.isNotEmpty ? fileName : fallbackName).toLowerCase();
    if (lower.endsWith('.png')) {
      return 'image/png';
    }
    if (lower.endsWith('.webp')) {
      return 'image/webp';
    }
    return 'image/jpeg';
  }
}
