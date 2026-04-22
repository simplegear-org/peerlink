import 'call_models.dart';

enum CallLogStatus {
  completed,
  missed,
  declined,
  canceled,
  busy,
  failed,
}

class CallLogEntry {
  final String id;
  final String peerId;
  final String contactName;
  final CallDirection direction;
  final CallLogStatus status;
  final DateTime startedAt;
  final DateTime endedAt;
  final int durationSeconds;

  const CallLogEntry({
    required this.id,
    required this.peerId,
    required this.contactName,
    required this.direction,
    required this.status,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
  });

  factory CallLogEntry.fromJson(Map<String, dynamic> json) {
    return CallLogEntry(
      id: json['id'] as String? ?? '',
      peerId: json['peerId'] as String? ?? '',
      contactName: json['contactName'] as String? ?? '',
      direction: (json['direction'] as String? ?? 'incoming') == 'outgoing'
          ? CallDirection.outgoing
          : CallDirection.incoming,
      status: CallLogStatus.values.firstWhere(
        (value) => value.name == (json['status'] as String? ?? ''),
        orElse: () => CallLogStatus.failed,
      ),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: DateTime.tryParse(json['endedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      durationSeconds: json['durationSeconds'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'peerId': peerId,
      'contactName': contactName,
      'direction': direction.name,
      'status': status.name,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': endedAt.toIso8601String(),
      'durationSeconds': durationSeconds,
    };
  }
}
