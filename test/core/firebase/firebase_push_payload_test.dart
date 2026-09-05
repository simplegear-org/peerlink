import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/core/firebase/firebase_push_payload.dart';

void main() {
  test('FirebasePushPayload unifies call fields from nested data payload', () {
    final payload = FirebasePushPayload.fromMap(<String, dynamic>{
      'data': <String, dynamic>{
        'type': 'call_invite',
        'peerId': 'peer-a',
        'call_id': 'call-1',
        'media_type': 'video',
        'servers': <String, dynamic>{
          'bootstrap': <String>['https://bootstrap.example'],
        },
      },
    });

    expect(payload.isCallInvite, isTrue);
    expect(payload.hasPeerAndCallId, isTrue);
    expect(payload.callPeerId, 'peer-a');
    expect(payload.callId, 'call-1');
    expect(payload.callMediaType, CallMediaType.video);
    expect(payload.rawServers, isA<Map<String, dynamic>>());
  });

  test('FirebasePushPayload detects remote call end from callAction', () {
    final payload = FirebasePushPayload.fromMap(<String, dynamic>{
      'type': 'call_invite',
      'fromPeerId': 'peer-b',
      'callId': 'call-2',
      'callAction': 'end',
      'mediaType': 'audio',
    });

    expect(payload.isCallEnd, isTrue);
    expect(payload.isCallInvite, isFalse);
    expect(payload.isCallPayload, isTrue);
    expect(payload.hasPeerAndCallId, isTrue);
    expect(payload.callPeerId, 'peer-b');
    expect(payload.callMediaType, CallMediaType.audio);
  });

  test('FirebasePushPayload parses stringified nested data from iOS bridge', () {
    final payload = FirebasePushPayload.fromMap(<String, dynamic>{
      'aps': <String, dynamic>{
        'alert': <String, dynamic>{'body': 'New message'},
      },
      'data':
          '{"type":"message","fromPeerId":"peer-c","relayMessageId":"msg-3",'
          '"groupId":"group-7","servers":{"relay":["https://relay.example:444"]}}',
    });

    expect(payload.type, 'message');
    expect(payload.senderPeerId, 'peer-c');
    expect(payload.relayMessageId, 'msg-3');
    expect(payload.groupId, 'group-7');
    expect(payload.isMessageLike, isTrue);
    expect(payload.rawServers, isA<Map<String, dynamic>>());
  });

  test('FirebasePushPayload parses stringified transport payload', () {
    final payload = FirebasePushPayload.fromMap(<String, dynamic>{
      'payload':
          '{"type":"direct_update","directPeerId":"peer-d",'
          '"servers":{"push":["https://push.example:445"]}}',
    });

    expect(payload.type, 'direct_update');
    expect(payload.directPeerId, 'peer-d');
    expect(payload.isMessageLike, isTrue);
    expect(payload.rawServers, isA<Map<String, dynamic>>());
  });

  test('FirebasePushPayload parses FCM stringified group relay hints', () {
    final payload = FirebasePushPayload.fromMap(<String, dynamic>{
      'type': 'group_update',
      'groupId': 'group-1',
      'lastSeq': 'msg-1',
      'relay':
          '{"relayMessageId":"msg-1","scopeKind":"group",'
          '"serverId":"relay.example:444",'
          '"servers":["https://relay.example:444"]}',
      'servers':
          '{"relay":["https://relay.example:444"],'
          '"bootstrap":[],"push":[],"turn":[]}',
    });

    expect(payload.type, 'group_update');
    expect(payload.groupId, 'group-1');
    expect(payload.relayMessageId, 'msg-1');
    expect(payload.relayServers, const <String>['https://relay.example:444']);
    expect(payload.availableRelayServers, const <String>[
      'https://relay.example:444',
    ]);
  });

  test('FirebasePushPayload parses moderation policy payload', () {
    final payload = FirebasePushPayload.fromMap(<String, dynamic>{
      'type': 'moderation_policy',
      'peerId': 'local-peer',
      'policyState': 'banned',
      'message': 'Account blocked',
      'signedStatus': '{"schema":"peerlink_moderation_status_v1"}',
    });

    expect(payload.isModerationPolicy, isTrue);
    expect(payload.isModerationBan, isTrue);
    expect(payload.isModerationWarning, isFalse);
    expect(payload.rawSignedModerationStatus, isA<String>());
  });
}
