import '../../core/calls/call_log_entry.dart';
import '../../core/calls/call_models.dart';
import '../../core/runtime/call_log_repository.dart';

class CallsController {
  final CallLogRepository repository;
  static const String _missedCallsSeenAtKey = 'peerlink.calls.missed_seen_at';

  CallsController({required this.repository});

  Future<List<CallLogEntry>> loadEntries() async {
    return repository.readAll();
  }

  Future<int> loadMissedCallsBadgeCount() async {
    final entries = await repository.readAll();
    final seenAt = _missedCallsSeenAt();
    return entries.where((entry) {
      if (entry.status != CallLogStatus.missed) {
        return false;
      }
      if (entry.direction != CallDirection.incoming) {
        return false;
      }
      if (seenAt == null) {
        return true;
      }
      return entry.endedAt.isAfter(seenAt);
    }).length;
  }

  Future<void> markMissedCallsSeenNow() async {
    await repository.storage
        .getSettings()
        .put(_missedCallsSeenAtKey, DateTime.now().toIso8601String());
  }

  Future<void> deleteEntries(Iterable<CallLogEntry> entries) async {
    for (final entry in entries) {
      await repository.deleteById(entry.id);
    }
  }

  DateTime? _missedCallsSeenAt() {
    final raw = repository.storage.getSettings().get(_missedCallsSeenAtKey);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
