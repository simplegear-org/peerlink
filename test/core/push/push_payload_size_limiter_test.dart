import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/push/push_payload_size_limiter.dart';

void main() {
  group('PushPayloadSizeLimiter', () {
    test('compacts regular server metadata without removing event fields', () {
      const limiter = PushPayloadSizeLimiter(maxTransportPayloadBytes: 700);
      final payload = <String, dynamic>{
        'type': 'call_invite',
        'callerUserId': 'caller',
        'calleeUserId': 'callee',
        'callId': 'call-1',
        'mediaType': 'video',
        'servers': <String, dynamic>{
          'bootstrap': _strings('wss://bootstrap', 20),
          'relay': _strings('https://relay', 20),
          'push': _strings('https://push', 20),
          'turn': _turnServers(20),
        },
      };

      final compacted = limiter.compact(payload);

      expect(limiter.transportSizeBytes(compacted), lessThanOrEqualTo(700));
      expect(compacted['type'], 'call_invite');
      expect(compacted['callerUserId'], 'caller');
      expect(compacted['calleeUserId'], 'callee');
      expect(compacted['callId'], 'call-1');
      expect(compacted['mediaType'], 'video');
      expect(limiter.transportSizeBytes(payload), greaterThan(700));
    });

    test('keeps priority servers untouched while compacting', () {
      const limiter = PushPayloadSizeLimiter(maxTransportPayloadBytes: 500);
      final priorityServers = <String, dynamic>{
        'bootstrap': _strings('wss://priority-bootstrap', 2),
        'relay': _strings('https://priority-relay', 2),
        'push': _strings('https://priority-push', 2),
        'turn': _turnServers(2),
      };
      final payload = <String, dynamic>{
        'type': 'direct_update',
        'directPeerId': 'peer-a',
        'lastSeq': 'message-1',
        'servers': <String, dynamic>{
          'bootstrap': _strings('wss://bootstrap', 20),
          'relay': _strings('https://relay', 20),
          'push': _strings('https://push', 20),
          'turn': _turnServers(20),
        },
        'priority_servers': priorityServers,
      };

      final compacted = limiter.compact(payload);

      expect(compacted['priority_servers'], priorityServers);
      expect(compacted['type'], 'direct_update');
      expect(compacted['directPeerId'], 'peer-a');
      expect(compacted['lastSeq'], 'message-1');
      expect(
        limiter.transportSizeBytes(compacted),
        lessThan(limiter.transportSizeBytes(payload)),
      );
    });

    test('keeps one server of each type before removing a type', () {
      const limiter = PushPayloadSizeLimiter(maxTransportPayloadBytes: 720);
      final payload = <String, dynamic>{
        'type': 'direct_update',
        'directPeerId': 'peer-a',
        'lastSeq': 'message-1',
        'servers': <String, dynamic>{
          'bootstrap': _strings('wss://bootstrap', 8),
          'relay': _strings('https://relay', 8),
          'push': const <String>[
            'https://push-a.example.com:445',
            'https://push-b.example.com:445',
          ],
          'turn': _turnServers(8),
        },
      };

      final compacted = limiter.compact(payload);
      final servers = compacted['servers']! as Map<String, dynamic>;

      expect(servers['bootstrap'], const <String>[
        'wss://bootstrap-0.example.com',
      ]);
      expect(servers['relay'], const <String>['https://relay-0.example.com']);
      expect(servers['push'], const <String>['https://push-a.example.com:445']);
      expect(servers['turn'], hasLength(1));
      expect(limiter.transportSizeBytes(compacted), lessThanOrEqualTo(720));
    });

    test('leaves small payload unchanged', () {
      const limiter = PushPayloadSizeLimiter();
      final payload = <String, dynamic>{
        'type': 'direct_update',
        'directPeerId': 'peer-a',
        'servers': <String, dynamic>{
          'push': <String>['https://push.example:445'],
        },
      };

      expect(limiter.compact(payload), payload);
    });
  });
}

List<String> _strings(String prefix, int count) {
  return List<String>.generate(count, (index) => '$prefix-$index.example.com');
}

List<Map<String, dynamic>> _turnServers(int count) {
  return List<Map<String, dynamic>>.generate(
    count,
    (index) => <String, dynamic>{
      'url': 'turn:turn-$index.example.com:3478?transport=tcp',
      'username': 'peerlink',
      'password': 'peerlink',
      'priority': 100 - index,
    },
  );
}
