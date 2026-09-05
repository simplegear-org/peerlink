import 'dart:convert';

import 'package:peerlink/core/messaging/chat_service.dart';
import 'package:peerlink/core/runtime/account_pairing_payload.dart';
import 'package:peerlink/features/chat/application/chat_account_payload_decoder.dart';
import 'package:test/test.dart';

void main() {
  test('decodePairRequest accepts matching account pair request payload', () {
    final payload = AccountPairingRequestPayload(
      requestId: 'request-1',
      sessionId: 'session-1',
      targetAccountId: 'account-target',
      targetDeviceId: 'device-target',
      requesterPeerId: 'peer-requester',
      requesterAccountId: 'account-requester',
      requesterDeviceId: 'device-requester',
      requesterDisplayName: 'Requester',
      requesterSigningPublicKey: 'signing',
      requesterAgreementPublicKey: 'agreement',
      requesterEndpointId: null,
      requesterFcmTokenHash: null,
      requestedAtMs: 1,
    );

    final decoded = ChatAccountPayloadDecoder.decodePairRequest(
      ChatMessage(
        id: 'm1',
        peerId: 'peer',
        kind: 'accountPairRequest',
        text: jsonEncode(payload.toJson()),
      ),
    );

    expect(decoded?.requestId, 'request-1');
    expect(decoded?.requesterPeerId, 'peer-requester');
  });

  test('decodePairRequest rejects wrong kind, invalid json and wrong type', () {
    expect(
      ChatAccountPayloadDecoder.decodePairRequest(
        ChatMessage(
          id: 'm1',
          peerId: 'peer',
          kind: 'text',
          text: '{"type":"peerlink_account_pair_request"}',
        ),
      ),
      isNull,
    );
    expect(
      ChatAccountPayloadDecoder.decodePairRequest(
        ChatMessage(
          id: 'm2',
          peerId: 'peer',
          kind: 'accountPairRequest',
          text: '{',
        ),
      ),
      isNull,
    );
    expect(
      ChatAccountPayloadDecoder.decodePairRequest(
        ChatMessage(
          id: 'm3',
          peerId: 'peer',
          kind: 'accountPairRequest',
          text: '[]',
        ),
      ),
      isNull,
    );
  });
}
