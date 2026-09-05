import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/firebase/firebase_push_log_formatter.dart';

void main() {
  group('FirebasePushLogFormatter', () {
    test('redacts sensitive incoming push fields', () {
      const formatter = FirebasePushLogFormatter();

      final safeData = formatter.sanitizeIncomingPushData(<String, dynamic>{
        'type': 'message',
        'sig': 'signature',
        'signingPub': 'public-key',
        'messageToken': 'token',
        'authorization': 'bearer',
      });

      expect(safeData['type'], 'message');
      expect(safeData['sig'], '<redacted>');
      expect(safeData['signingPub'], '<redacted>');
      expect(safeData['messageToken'], '<redacted>');
      expect(safeData['authorization'], '<redacted>');
    });

    test('truncates long payload logs', () {
      const formatter = FirebasePushLogFormatter();

      final result = formatter.truncate('a' * 12, maxLength: 5);

      expect(result, 'aaaaa...(truncated)');
    });
  });
}
