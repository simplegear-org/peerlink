import '../calls/call_log_entry.dart';
import '../calls/call_models.dart';
import '../firebase/firebase_push_payload.dart';
import '../runtime/storage_service.dart';
import 'notification_service.dart';

class AppBadgeService {
  AppBadgeService({StorageService? storage})
    : _storage = storage ?? StorageService();

  static const String _missedCallsSeenAtKey = 'peerlink.calls.missed_seen_at';
  static const String _handledPushEventsKey =
      'peerlink.app.badge_handled_push_events';
  static const int _handledPushEventsLimit = 100;

  final StorageService _storage;

  int totalForUi({required int unreadMessages, required int missedCalls}) {
    return unreadMessages + missedCalls;
  }

  Future<int> syncFromUi({
    required int unreadMessages,
    required int missedCalls,
  }) async {
    final total = totalForUi(
      unreadMessages: unreadMessages,
      missedCalls: missedCalls,
    );
    await NotificationService.instance.syncStoredBadgeCount(total);
    return total;
  }

  Future<int> syncFromStorage() async {
    await _storage.init();
    final total = await _loadTotalFromStorage();
    await NotificationService.instance.syncStoredBadgeCount(total);
    return total;
  }

  Future<int> applyBackgroundPushHint(Map<String, dynamic> data) async {
    final payload = FirebasePushPayload.fromMap(data);
    if (!payload.isMessageLike) {
      return NotificationService.instance.readStoredBadgeCount();
    }
    await _storage.init();
    final eventKey = _backgroundEventKey(payload);
    if (eventKey.isEmpty) {
      return NotificationService.instance.readStoredBadgeCount();
    }
    final settings = _storage.getSettings();
    final handled = _readHandledPushEvents(settings.get(_handledPushEventsKey));
    if (handled.contains(eventKey)) {
      return NotificationService.instance.readStoredBadgeCount();
    }
    handled.add(eventKey);
    while (handled.length > _handledPushEventsLimit) {
      handled.removeAt(0);
    }
    await settings.put(_handledPushEventsKey, handled);
    return NotificationService.instance.incrementStoredBadgeCount();
  }

  Future<int> _loadTotalFromStorage() async {
    final unreadMessages = await _loadUnreadMessagesCount();
    final missedCalls = await _loadMissedCallsCount();
    return unreadMessages + missedCalls;
  }

  Future<int> _loadUnreadMessagesCount() async {
    final summaries = await _storage.loadAllChatSummaries();
    return summaries.fold<int>(0, (sum, summary) {
      return sum + _asInt(summary['unreadCount']);
    });
  }

  Future<int> _loadMissedCallsCount() async {
    final rawEntries = await _storage.readCallLogs();
    final settings = _storage.getSettings();
    final seenAt = _parseDateTime(settings.get(_missedCallsSeenAtKey));
    var count = 0;
    for (final raw in rawEntries) {
      final entry = CallLogEntry.fromJson(raw);
      if (entry.status != CallLogStatus.missed) {
        continue;
      }
      if (entry.direction != CallDirection.incoming) {
        continue;
      }
      if (seenAt != null && !entry.endedAt.isAfter(seenAt)) {
        continue;
      }
      count += 1;
    }
    return count;
  }

  String _backgroundEventKey(FirebasePushPayload payload) {
    final type = payload.type.trim();
    final sender = payload.senderPeerId.trim();
    final target = payload.groupId.trim().isNotEmpty
        ? payload.groupId.trim()
        : payload.directPeerId.trim();
    final seq = payload.relayMessageId.trim();
    if (type.isEmpty || sender.isEmpty || seq.isEmpty) {
      return '';
    }
    return '$type|$sender|$target|$seq';
  }

  List<String> _readHandledPushEvents(Object? raw) {
    if (raw is! List) {
      return <String>[];
    }
    return raw
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: true);
  }

  int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DateTime? _parseDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
