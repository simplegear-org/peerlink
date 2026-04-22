import '../../core/calls/call_log_entry.dart';
import '../../core/runtime/call_log_repository.dart';

class CallsController {
  final CallLogRepository repository;

  CallsController({required this.repository});

  Future<List<CallLogEntry>> loadEntries() async {
    return repository.readAll();
  }

  Future<void> deleteEntries(Iterable<CallLogEntry> entries) async {
    for (final entry in entries) {
      await repository.deleteById(entry.id);
    }
  }
}
