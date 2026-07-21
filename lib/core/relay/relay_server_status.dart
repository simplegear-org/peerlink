class RelayServerStatus {
  final String url;
  final bool healthy;
  final String? lastError;
  final DateTime? lastSuccessAt;

  const RelayServerStatus({
    required this.url,
    required this.healthy,
    this.lastError,
    this.lastSuccessAt,
  });
}
