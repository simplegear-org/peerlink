const String accountDeviceEventsStorageKey = 'account_device_events.v1';

enum AccountDeviceEventType {
  pairingRequestSent,
  pairingApproved,
  pairingRejected,
  deviceAdded,
  deviceRemoved,
}

class AccountDeviceEvent {
  static const int version = 1;

  final String eventId;
  final AccountDeviceEventType type;
  final String accountId;
  final String? deviceId;
  final String? actorDeviceId;
  final int timestampMs;
  final String? details;

  const AccountDeviceEvent({
    required this.eventId,
    required this.type,
    required this.accountId,
    required this.deviceId,
    required this.actorDeviceId,
    required this.timestampMs,
    this.details,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'version': version,
      'eventId': eventId,
      'type': type.name,
      'accountId': accountId,
      if (deviceId != null) 'deviceId': deviceId,
      if (actorDeviceId != null) 'actorDeviceId': actorDeviceId,
      'timestampMs': timestampMs,
      if (details != null) 'details': details,
    };
  }

  factory AccountDeviceEvent.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString() ?? '';
    final parsedType = AccountDeviceEventType.values.where(
      (item) => item.name == typeName,
    );
    if (parsedType.isEmpty) {
      throw const FormatException('Unknown account device event type');
    }
    return AccountDeviceEvent(
      eventId: json['eventId']?.toString() ?? '',
      type: parsedType.first,
      accountId: json['accountId']?.toString() ?? '',
      deviceId: _nullableTrimmed(json['deviceId']),
      actorDeviceId: _nullableTrimmed(json['actorDeviceId']),
      timestampMs: int.tryParse(json['timestampMs']?.toString() ?? '') ?? 0,
      details: _nullableTrimmed(json['details']),
    );
  }

  static String? _nullableTrimmed(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
