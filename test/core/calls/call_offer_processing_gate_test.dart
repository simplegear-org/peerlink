import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_offer_processing_gate.dart';

void main() {
  group('CallOfferProcessingGate', () {
    test('suppresses duplicate in-flight offer', () async {
      final gate = CallOfferProcessingGate();
      final blocker = Completer<void>();
      final logs = <String>[];
      var firstRuns = 0;
      var secondRuns = 0;

      final firstFuture = gate.runIfAccepted(
        offerKey: 'call-1:turn:abc',
        log: logs.add,
        action: () async {
          firstRuns++;
          await blocker.future;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      final secondAccepted = await gate.runIfAccepted(
        offerKey: 'call-1:turn:abc',
        log: logs.add,
        action: () async {
          secondRuns++;
        },
      );

      expect(secondAccepted, isFalse);
      expect(firstRuns, 1);
      expect(secondRuns, 0);
      expect(logs.last, contains('duplicate in-flight'));

      blocker.complete();
      final firstAccepted = await firstFuture;
      expect(firstAccepted, isTrue);
    });

    test('suppresses duplicate completed offer', () async {
      final gate = CallOfferProcessingGate();
      final logs = <String>[];
      var runs = 0;

      final firstAccepted = await gate.runIfAccepted(
        offerKey: 'call-1:turn:abc',
        log: logs.add,
        action: () async {
          runs++;
        },
      );
      final secondAccepted = await gate.runIfAccepted(
        offerKey: 'call-1:turn:abc',
        log: logs.add,
        action: () async {
          runs++;
        },
      );

      expect(firstAccepted, isTrue);
      expect(secondAccepted, isFalse);
      expect(runs, 1);
      expect(logs.last, contains('duplicate completed'));
    });
  });
}
