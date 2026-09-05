import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/server_update_parser.dart';

void main() {
  group('ServerUpdateParser', () {
    test('parses servers from top-level message payload', () {
      const parser = ServerUpdateParser();

      final update = parser.parse(<String, dynamic>{
        'id': 'm1',
        'text': 'hello',
        'servers': <String, dynamic>{
          'bootstrap': <String>['bootstrap.example.com'],
          'relay': <String>['relay.example.com'],
          'push': <String>['https://push.example.com:445'],
          'turn': <Map<String, dynamic>>[
            <String, dynamic>{'url': 'turn:turn.example.com:3478'},
          ],
        },
      });

      expect(update, isNotNull);
      expect(update!.bootstrap, const <String>['wss://bootstrap.example.com']);
      expect(update.relay, const <String>['https://relay.example.com:444']);
      expect(update.push, const <String>['https://push.example.com:445']);
      expect(
        update.turn.single.url,
        'turn:turn.example.com:3478?transport=tcp',
      );
    });

    test('parses servers from nested push payload', () {
      const parser = ServerUpdateParser();

      final update = parser.parse(<String, dynamic>{
        'payload': jsonEncode(<String, dynamic>{
          'servers': <String, dynamic>{
            'bootstrap': <String>['bootstrap.example.com'],
          },
          'priority_servers': <String, dynamic>{
            'relay': <String>['priority-relay.example.com'],
          },
        }),
      });

      expect(update, isNotNull);
      expect(update!.bootstrap, const <String>['wss://bootstrap.example.com']);
      expect(update.priorityRelay, const <String>[
        'https://priority-relay.example.com:444',
      ]);
    });
  });
}
