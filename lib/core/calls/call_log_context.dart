// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import '../transport/transport_mode.dart';
import 'call_models.dart';

String buildStructuredCallLogContext({
  required String scope,
  required String? peerId,
  required String? callId,
  required int epoch,
  required String role,
  required CallMediaType mediaType,
  required TransportMode? transportMode,
  CallPhase? phase,
  String signalingState = 'unknown',
}) {
  final peer = (peerId == null || peerId.isEmpty) ? '-' : peerId;
  final call = (callId == null || callId.isEmpty) ? '-' : callId;
  final mode = transportMode?.name ?? 'unknown';
  final currentPhase = phase?.name ?? 'unknown';
  return '[ctx scope=$scope callId=$call peerId=$peer epoch=$epoch role=$role '
      'phase=$currentPhase signaling=$signalingState mode=$mode media=${mediaType.name}]';
}
