import '../../core/calls/call_log_entry.dart';
import '../../core/calls/call_models.dart';
import '../../core/runtime/call_log_repository.dart';
import '../../core/runtime/contacts_repository.dart';

class UiAppController {
  final ContactsRepository contactsRepository;
  final CallLogRepository callLogRepository;

  UiAppController({
    required this.contactsRepository,
    required this.callLogRepository,
  });

  String contactNameFor(String? peerId) {
    return contactsRepository.displayName(peerId);
  }

  Future<void> recordCall(CallState state) async {
    final callId = state.callId;
    final peerId = state.peerId;
    final direction = state.direction;
    if (callId == null ||
        callId.isEmpty ||
        peerId == null ||
        peerId.isEmpty ||
        direction == null) {
      return;
    }

    final endedAt = DateTime.now();
    final connectedAt = state.connectedAt;
    final startedAt = _dateFromCallId(callId);
    final durationSeconds = connectedAt == null
        ? 0
        : endedAt.difference(connectedAt).inSeconds.clamp(0, 24 * 60 * 60);

    final entry = CallLogEntry(
      id: callId,
      peerId: peerId,
      contactName: contactNameFor(peerId),
      direction: direction,
      status: logStatusFor(state),
      startedAt: startedAt,
      endedAt: endedAt,
      durationSeconds: durationSeconds,
    );
    await callLogRepository.prepend(entry);
  }

  CallLogStatus logStatusFor(CallState state) {
    if (state.phase == CallPhase.failed) {
      return CallLogStatus.failed;
    }
    switch (state.debugStatus) {
      case 'Завершен':
        return CallLogStatus.completed;
      case 'Пропущен':
      case 'Без ответа':
        return CallLogStatus.missed;
      case 'Отклонен':
        return CallLogStatus.declined;
      case 'Отменен':
        return CallLogStatus.canceled;
      case 'Занят':
        return CallLogStatus.busy;
      default:
        return state.connectedAt != null
            ? CallLogStatus.completed
            : CallLogStatus.failed;
    }
  }

  DateTime _dateFromCallId(String callId) {
    final micros = int.tryParse(callId);
    if (micros == null) {
      return DateTime.now();
    }
    return DateTime.fromMicrosecondsSinceEpoch(micros);
  }
}
