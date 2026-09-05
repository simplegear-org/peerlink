import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/firebase/firebase_push_server_update_parser.dart';

void main() {
  group('FirebasePushServerUpdateParser', () {
    test('parses servers and priority servers from transport payload', () {
      const parser = FirebasePushServerUpdateParser();

      final update = parser.parse(<String, dynamic>{
        'payload': jsonEncode(<String, dynamic>{
          'servers': <String, dynamic>{
            'bootstrap': <String>['bootstrap.example.com'],
            'relay': <String>['relay.example.com'],
            'push': <String>['https://push.example.com:445'],
            'turn': <Map<String, dynamic>>[
              <String, dynamic>{'url': 'turn:turn.example.com:3478'},
            ],
          },
          'priority_servers': <String, dynamic>{
            'bootstrap': <String>['priority-bootstrap.example.com'],
            'relay': <String>['priority-relay.example.com'],
            'push': <String>['https://priority-push.example.com:445'],
            'turn': <Map<String, dynamic>>[
              <String, dynamic>{'url': 'turn:priority-turn.example.com:3478'},
            ],
          },
        }),
      });

      expect(update, isNotNull);
      expect(update!.bootstrap, const <String>['wss://bootstrap.example.com']);
      expect(update.relay, const <String>['https://relay.example.com:444']);
      expect(update.push, const <String>['https://push.example.com:445']);
      expect(
        update.turn.single.url,
        'turn:turn.example.com:3478?transport=tcp',
      );
      expect(update.priorityBootstrap, const <String>[
        'wss://priority-bootstrap.example.com',
      ]);
      expect(update.priorityRelay, const <String>[
        'https://priority-relay.example.com:444',
      ]);
      expect(update.priorityPush, const <String>[
        'https://priority-push.example.com:445',
      ]);
      expect(
        update.priorityTurn.single.url,
        'turn:priority-turn.example.com:3478?transport=tcp',
      );
    });
  });
}
