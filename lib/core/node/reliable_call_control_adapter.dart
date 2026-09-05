// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/calls/call_control_reliable_payload.dart';
import 'package:peerlink/core/calls/call_control_transport.dart';
import 'package:peerlink/core/messaging/chat_service.dart';

class ReliableCallControlAdapter implements CallControlTransport {
  ReliableCallControlAdapter({
    required String selfPeerId,
    required ChatService chat,
    CallControlReliablePayload codec = const CallControlReliablePayload(),
  }) : _selfPeerId = selfPeerId,
       _chat = chat,
       _codec = codec {
    _chat.setControlHandler(_handleControlMessage);
  }

  final String _selfPeerId;
  final ChatService _chat;
  final CallControlReliablePayload _codec;
  CallControlInboundHandler? _incomingHandler;

  @override
  Future<void> send(String peerId, String text) {
    return _chat.sendControlMessage(
      peerId,
      kind: 'callControl',
      text: text,
      forcePlain: true,
    );
  }

  @override
  void setIncomingHandler(CallControlInboundHandler? handler) {
    _incomingHandler = handler;
  }

  Future<bool> _handleControlMessage(ChatMessage message) async {
    final sourcePeerId = (message.senderPeerId ?? message.peerId).trim();
    if (sourcePeerId.isEmpty) {
      return false;
    }
    final decoded = _codec.decode(
      fromPeerId: sourcePeerId,
      toPeerId: _selfPeerId,
      text: message.text,
    );
    if (decoded == null) {
      return false;
    }
    final handler = _incomingHandler;
    if (handler == null) {
      return false;
    }
    return handler(
      CallControlPayload(fromPeerId: sourcePeerId, text: message.text),
    );
  }

  void dispose() {
    _chat.setControlHandler(null);
    _incomingHandler = null;
  }
}
