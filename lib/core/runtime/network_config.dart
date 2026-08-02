class NetworkConfig {
  final bool enableRelay;
  final bool enableTurn;
  final bool enableDht;
  final Duration bucketRefreshInterval;

  const NetworkConfig({
    this.enableRelay = true,
    this.enableTurn = true,
    this.enableDht = true,
    this.bucketRefreshInterval = const Duration(minutes: 5),
  });
}