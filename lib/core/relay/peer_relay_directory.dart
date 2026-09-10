// SPDX-License-Identifier: MPL-2.0

abstract interface class PeerRelayDirectory {
  List<String> freshRelayServersFor(String peerId);

  Future<void> updateRelayServers(
    String peerId,
    Iterable<String> relayServers, {
    required DateTime updatedAt,
  });
}
