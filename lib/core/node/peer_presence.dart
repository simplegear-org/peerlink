class PeerPresenceUpdate {
  final String peerId;
  final bool isOnline;
  final DateTime observedAt;
  final DateTime? lastSeenAt;

  const PeerPresenceUpdate({
    required this.peerId,
    required this.isOnline,
    required this.observedAt,
    this.lastSeenAt,
  });
}
