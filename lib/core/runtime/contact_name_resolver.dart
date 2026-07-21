class ContactNameResolver {
  static String resolveFromEntry(
    Object? raw, {
    required String peerId,
    String? fallback,
  }) {
    if (raw is Map) {
      final name = raw['name'];
      if (name is String && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return fallback ?? peerId;
  }

  static String resolveFromMap(
    Map<String, dynamic>? contacts, {
    required String peerId,
    String? fallback,
  }) {
    return resolveFromEntry(
      contacts?[peerId],
      peerId: peerId,
      fallback: fallback,
    );
  }
}
