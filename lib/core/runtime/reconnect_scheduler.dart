class ReconnectScheduler {
  final Map<String, int> attempts = {};

  Duration nextDelay(String peerId) {
    final a = attempts.putIfAbsent(peerId, () => 0);

    attempts[peerId] = a + 1;

    final seconds = (1 << a).clamp(1, 60);

    return Duration(seconds: seconds);
  }

  void reset(String peerId) {
    attempts.remove(peerId);
  }
}
