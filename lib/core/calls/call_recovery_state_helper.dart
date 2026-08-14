// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'call_models.dart';

class CallRecoveryStateHelper {
  const CallRecoveryStateHelper();

  CallState startRecovery({
    required CallState currentState,
    required CallRecoveryKind kind,
    required String status,
  }) {
    final attempt =
        currentState.isRecovering && currentState.recoveryKind == kind
        ? currentState.recoveryAttempt + 1
        : 1;
    final returnPhase = currentState.isRecovering
        ? (currentState.recoveryReturnPhase ?? CallPhase.connecting)
        : currentState.phase;
    final keepActiveUi = kind == CallRecoveryKind.ice && currentState.isActive;
    return currentState.copyWith(
      phase: keepActiveUi ? currentState.phase : CallPhase.recovering,
      recoveryKind: kind,
      recoveryAttempt: attempt,
      recoveryReturnPhase: returnPhase,
      debugStatus: keepActiveUi ? currentState.debugStatus : status,
      clearError: true,
    );
  }

  CallState completeRecovery({
    required CallState currentState,
    String? status,
  }) {
    if (!currentState.isRecovering) {
      if (currentState.recoveryKind == CallRecoveryKind.ice &&
          currentState.isActive) {
        return currentState.copyWith(
          recoveryAttempt: 0,
          clearRecoveryKind: true,
          clearRecoveryReturnPhase: true,
          clearError: true,
        );
      }
      return currentState;
    }
    return currentState.copyWith(
      phase: currentState.recoveryReturnPhase ?? CallPhase.connecting,
      debugStatus: status ?? currentState.debugStatus,
      recoveryAttempt: 0,
      clearRecoveryKind: true,
      clearRecoveryReturnPhase: true,
      clearError: true,
    );
  }
}
