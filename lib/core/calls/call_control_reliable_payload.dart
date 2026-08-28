// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import '../signaling/signaling_message.dart';
import 'call_models.dart';

typedef CallControlReliableSender =
    Future<void> Function(String peerId, String text);

class CallControlReliablePayload {
  static const String prefix = '__peerlink_call_control_v1__:';
  static const Set<String> criticalTypes = <String>{
    'call_invite',
    'call_accept',
    'call_reject',
    'call_end',
  };

  const CallControlReliablePayload();

  String encode({
    required String controlType,
    required String callId,
    required Map<String, dynamic> data,
  }) {
    final sanitizedData = Map<String, dynamic>.from(data)
      ..remove('type')
      ..remove('from')
      ..remove('to');
    sanitizedData['callId'] = callId;
    sanitizedData['signalScope'] = 'call';
    return '$prefix${jsonEncode(<String, dynamic>{'v': 1, 'type': 'call_control', 'controlType': controlType, 'data': sanitizedData, 'createdAtMs': DateTime.now().millisecondsSinceEpoch})}';
  }

  SignalingMessage? decode({
    required String fromPeerId,
    required String toPeerId,
    required String text,
  }) {
    if (!text.startsWith(prefix)) {
      return null;
    }
    try {
      final raw = jsonDecode(text.substring(prefix.length));
      if (raw is! Map<String, dynamic>) {
        return null;
      }
      if (raw['v'] != 1 || raw['type'] != 'call_control') {
        return null;
      }
      final controlType = (raw['controlType'] as String? ?? '').trim();
      if (!criticalTypes.contains(controlType)) {
        return null;
      }
      final rawData = raw['data'];
      if (rawData is! Map<String, dynamic>) {
        return null;
      }
      final data = Map<String, dynamic>.from(rawData);
      final callId = (data['callId'] as String? ?? '').trim();
      if (callId.isEmpty) {
        return null;
      }
      data['callId'] = callId;
      data['signalScope'] = 'call';
      return SignalingMessage(
        type: controlType,
        fromPeerId: fromPeerId,
        toPeerId: toPeerId,
        data: data,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> inviteData({
    required String callId,
    required CallMediaType mediaType,
    required Map<String, dynamic> inviteMetadata,
  }) {
    final sanitizedInviteMetadata = Map<String, dynamic>.from(inviteMetadata)
      ..remove('callId')
      ..remove('signalScope')
      ..remove('mediaType');
    return <String, dynamic>{
      'callId': callId,
      'signalScope': 'call',
      'mediaType': mediaType.name,
      'videoCapable': true,
      ...sanitizedInviteMetadata,
    };
  }

  Map<String, dynamic> terminalData({required String callId}) {
    return <String, dynamic>{'callId': callId, 'signalScope': 'call'};
  }
}
