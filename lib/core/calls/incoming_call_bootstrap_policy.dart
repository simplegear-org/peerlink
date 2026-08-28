// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class IncomingCallBootstrapPolicy {
  const IncomingCallBootstrapPolicy({
    this.acceptRuntimeEnrichmentWaitTimeout = const Duration(seconds: 8),
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
