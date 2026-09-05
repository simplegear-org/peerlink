import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/calls/call_log_entry.dart';
import 'package:peerlink/core/calls/call_models.dart';
import 'package:peerlink/ui/models/contact.dart';
import 'package:peerlink/ui/screens/calls_screen_presenter.dart';

void main() {
  group('CallsScreenPresenter', () {
    const presenter = CallsScreenPresenter();

    test('uses contact name when contact exists', () {
      final entry = _entry(peerId: 'peer-1234567890', contactName: 'Stored');

      final name = presenter.displayNameFor(entry, <Contact>[
        Contact(peerId: 'peer-1234567890', name: 'Alice'),
      ]);

      expect(name, 'Alice');
    });

    test('falls back to short peer id when contact is missing', () {
      final entry = _entry(peerId: 'peer-1234567890', contactName: 'Stored');

      final name = presenter.displayNameFor(entry, const <Contact>[]);

      expect(name, 'peer...7890');
    });
  });
}

CallLogEntry _entry({required String peerId, required String contactName}) {
  final now = DateTime(2026, 8, 23, 12);
  return CallLogEntry(
    id: 'call-a',
    peerId: peerId,
    contactName: contactName,
    direction: CallDirection.incoming,
    status: CallLogStatus.completed,
    startedAt: now,
    endedAt: now,
    durationSeconds: 0,
  );
}
