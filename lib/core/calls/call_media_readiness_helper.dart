// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'call_models.dart';
import '../transport/transport_mode.dart';

class CallMediaReadinessHelper {
  const CallMediaReadinessHelper();

  CallState buildReadinessState({
    required CallState currentState,
    required bool localMediaReady,
    required bool remoteMediaReady,
    required DateTime now,
  }) {
    if (currentState.isRecovering) {
      return currentState;
    }
    if (localMediaReady && remoteMediaReady) {
      if (currentState.phase == CallPhase.active) {
        return currentState;
      }
      return currentState.copyWith(
        phase: CallPhase.active,
        debugStatus: currentState.transportMode == TransportMode.turn
            ? 'Звонок через TURN активен, видеоканал готов'
            : 'Звонок активен, видеоканал готов',
        connectedAt: now,
      );
    }

    final waitingFor = <String>[];
    if (!localMediaReady) {
      waitingFor.add('локальный входящий аудиопоток');
    }
    if (!remoteMediaReady) {
      waitingFor.add('подтверждение второй стороны');
    }

    return currentState.copyWith(
      phase: CallPhase.connecting,
      debugStatus: 'Ждем ${waitingFor.join(' и ')}',
    );
  }
}
