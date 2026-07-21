class MessageCache {
  final Map<String, int> _cache = {};

  bool contains(String id) {
    return _cache.containsKey(id);
  }

  void store(String id) {
    _cache[id] = DateTime.now().millisecondsSinceEpoch;

    if (_cache.length > 5000) {
      _cleanup();
    }
  }

  void _cleanup() {
    final now = DateTime.now().millisecondsSinceEpoch;

    _cache.removeWhere(
      (key, value) => now - value > 60000,
    );
  }
}