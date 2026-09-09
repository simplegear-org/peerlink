import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/moderation/application/moderation_report_outbox.dart';
import 'package:peerlink/features/moderation/application/moderation_report_service.dart';

class StorageModerationReportOutbox implements ModerationReportOutbox {
  const StorageModerationReportOutbox(this._settingsBox);

  final SecureStorageBox _settingsBox;

  @override
  List<Map<String, dynamic>> read() {
    final raw = _settingsBox.get(ModerationReportService.pendingReportsKey);
    return raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: true)
        : <Map<String, dynamic>>[];
  }

  @override
  Future<void> write(List<Map<String, dynamic>> reports) {
    return _settingsBox.put(ModerationReportService.pendingReportsKey, reports);
  }
}
