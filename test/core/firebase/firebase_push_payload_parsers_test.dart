import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/firebase/firebase_push_payload_parsers.dart';

void main() {
  group('FirebasePushGroupMembersPayloadParser', () {
    test('parses group members payload from transport payload', () {
      const parser = FirebasePushGroupMembersPayloadParser();
      final groupMembers = <String, dynamic>{
        'senderPeerId': 'peer-a',
        'groupId': 'group-1',
        'memberPeerIds': <String>['peer-a', 'peer-b'],
      };

      final result = parser.parse(<String, dynamic>{
        'payload': jsonEncode(<String, dynamic>{
          'type': 'group_members_update',
          'groupMembers': groupMembers,
        }),
      });

      expect(result, isNotNull);
      expect(result!.sourcePeerId, 'peer-a');
      expect(result.payload, groupMembers);
    });
  });
}
