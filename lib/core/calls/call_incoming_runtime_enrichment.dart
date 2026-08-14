// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../runtime/server_update_callback_registry.dart';
import 'call_models.dart';
import 'incoming_call_bootstrap_policy.dart';

class CallIncomingRuntimeEnrichment {
  const CallIncomingRuntimeEnrichment({
    IncomingCallBootstrapPolicy policy = const IncomingCallBootstrapPolicy(),
  }) : _policy = policy;

  final IncomingCallBootstrapPolicy _policy;

  Future<void> waitIfIncoming({
    required CallState Function() getState,
    required void Function(String message) log,
  }) async {
    if (!getState().isIncoming) {
      return;
    }
    await _policy.waitForAcceptRuntimeEnrichment(
      waitForPendingRuntimeEnrichment: (timeout) {
        return ServerUpdateCallbackRegistry.waitForPendingServersApply(
          timeout: timeout,
          logName: 'call',
          logPrefix: '[call][servers]',
        );
      },
      log: log,
    );
  }
}
