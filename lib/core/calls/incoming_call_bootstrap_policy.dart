class IncomingCallBootstrapPolicy {
  const IncomingCallBootstrapPolicy({
    this.acceptRuntimeEnrichmentWaitTimeout = const Duration(
      milliseconds: 1200,
    ),
  });

  final Duration acceptRuntimeEnrichmentWaitTimeout;

  bool get showIncomingCallImmediately => true;
  bool get mergeMissingServersAsynchronously => true;

  Future<void> waitForAcceptRuntimeEnrichment({
    required Future<void> Function(Duration timeout)
    waitForPendingRuntimeEnrichment,
    required void Function(String message) log,
  }) async {
    log(
      'incomingBootstrapPolicy:wait start '
      'timeoutMs=${acceptRuntimeEnrichmentWaitTimeout.inMilliseconds} '
      'showImmediately=$showIncomingCallImmediately '
      'mergeAsync=$mergeMissingServersAsynchronously',
    );
    await waitForPendingRuntimeEnrichment(acceptRuntimeEnrichmentWaitTimeout);
    log(
      'incomingBootstrapPolicy:wait done '
      'timeoutMs=${acceptRuntimeEnrichmentWaitTimeout.inMilliseconds}',
    );
  }
}
