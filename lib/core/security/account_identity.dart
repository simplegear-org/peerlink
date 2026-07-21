class AccountIdentity {
  static const currentSchemaVersion = 1;

  final int schemaVersion;
  final int membershipVersion;
  final String accountId;
  final String displayName;
  final List<AccountDeviceIdentity> devices;

  AccountIdentity({
    this.schemaVersion = currentSchemaVersion,
    this.membershipVersion = 1,
    required String accountId,
    String? displayName,
    required List<AccountDeviceIdentity> devices,
  }) : accountId = accountId.trim(),
       displayName = displayName?.trim() ?? '',
       devices = List.unmodifiable(devices);

  factory AccountIdentity.fromJson(Map<String, dynamic> json) {
    final rawDevices = json['devices'];
    return AccountIdentity(
      schemaVersion:
          int.tryParse(json['schemaVersion']?.toString() ?? '') ??
          currentSchemaVersion,
      membershipVersion:
          int.tryParse(json['membershipVersion']?.toString() ?? '') ?? 1,
      accountId: json['accountId']?.toString() ?? '',
      displayName: json['displayName']?.toString(),
      devices: rawDevices is List
          ? rawDevices
                .whereType<Map>()
                .map(
                  (item) => AccountDeviceIdentity.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const <AccountDeviceIdentity>[],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'schemaVersion': schemaVersion,
      'membershipVersion': membershipVersion,
      'accountId': accountId,
      'displayName': displayName,
      'devices': devices.map((device) => device.toJson()).toList(),
    };
  }

  AccountDeviceIdentity? deviceById(String deviceId) {
    final normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final device in devices) {
      if (device.deviceId == normalized) {
        return device;
      }
    }
    return null;
  }

  AccountIdentity upsertDevice(AccountDeviceIdentity device) {
    final nextDevices = <AccountDeviceIdentity>[];
    var replaced = false;
    for (final existing in devices) {
      if (existing.deviceId == device.deviceId) {
        nextDevices.add(device.copyWith(createdAtMs: existing.createdAtMs));
        replaced = true;
      } else {
        nextDevices.add(existing);
      }
    }
    if (!replaced) {
      nextDevices.add(device);
    }
    return copyWith(devices: nextDevices);
  }

  AccountIdentity removeDevices(Iterable<String> deviceIds) {
    final revoked = deviceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (revoked.isEmpty) {
      return this;
    }
    return copyWith(
      devices: devices
          .where((device) => !revoked.contains(device.deviceId))
          .toList(growable: false),
    );
  }

  AccountIdentity withCurrentDevice(String deviceId) {
    final normalized = deviceId.trim();
    if (normalized.isEmpty) {
      return this;
    }
    return copyWith(
      devices: devices
          .map(
            (device) =>
                device.copyWith(isCurrentDevice: device.deviceId == normalized),
          )
          .toList(growable: false),
    );
  }

  AccountIdentity copyWith({
    int? schemaVersion,
    int? membershipVersion,
    String? accountId,
    String? displayName,
    List<AccountDeviceIdentity>? devices,
  }) {
    return AccountIdentity(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      membershipVersion: membershipVersion ?? this.membershipVersion,
      accountId: accountId ?? this.accountId,
      displayName: displayName ?? this.displayName,
      devices: devices ?? this.devices,
    );
  }

  AccountIdentity bumpMembershipVersion() {
    return copyWith(membershipVersion: membershipVersion + 1);
  }
}

class AccountDeviceIdentity {
  final String deviceId;
  final String peerId;
  final String? signingPublicKey;
  final String? agreementPublicKey;
  final String? endpointId;
  final String? fcmTokenHash;
  final String? approvedByDeviceId;
  final int? approvedAtMs;
  final String? enrollmentSessionId;
  final String? membershipSignature;
  final int createdAtMs;
  final int updatedAtMs;
  final bool isCurrentDevice;

  AccountDeviceIdentity({
    required String deviceId,
    String? peerId,
    this.signingPublicKey,
    this.agreementPublicKey,
    this.endpointId,
    this.fcmTokenHash,
    this.approvedByDeviceId,
    this.approvedAtMs,
    this.enrollmentSessionId,
    this.membershipSignature,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.isCurrentDevice = false,
  }) : deviceId = deviceId.trim(),
       peerId = (peerId ?? deviceId).trim();

  factory AccountDeviceIdentity.fromJson(Map<String, dynamic> json) {
    return AccountDeviceIdentity(
      deviceId: json['deviceId']?.toString() ?? '',
      peerId: json['peerId']?.toString(),
      signingPublicKey: _nullableTrimmed(json['signingPublicKey']),
      agreementPublicKey: _nullableTrimmed(json['agreementPublicKey']),
      endpointId: _nullableTrimmed(json['endpointId']),
      fcmTokenHash: _nullableTrimmed(json['fcmTokenHash']),
      approvedByDeviceId: _nullableTrimmed(json['approvedByDeviceId']),
      approvedAtMs: _nullableInt(json['approvedAtMs']),
      enrollmentSessionId: _nullableTrimmed(json['enrollmentSessionId']),
      membershipSignature: _nullableTrimmed(json['membershipSignature']),
      createdAtMs: int.tryParse(json['createdAtMs']?.toString() ?? '') ?? 0,
      updatedAtMs: int.tryParse(json['updatedAtMs']?.toString() ?? '') ?? 0,
      isCurrentDevice:
          json['isCurrentDevice'] == true ||
          json['isCurrentDevice']?.toString() == 'true',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'peerId': peerId,
      if (signingPublicKey != null) 'signingPublicKey': signingPublicKey,
      if (agreementPublicKey != null) 'agreementPublicKey': agreementPublicKey,
      if (endpointId != null) 'endpointId': endpointId,
      if (fcmTokenHash != null) 'fcmTokenHash': fcmTokenHash,
      if (approvedByDeviceId != null) 'approvedByDeviceId': approvedByDeviceId,
      if (approvedAtMs != null) 'approvedAtMs': approvedAtMs,
      if (enrollmentSessionId != null)
        'enrollmentSessionId': enrollmentSessionId,
      if (membershipSignature != null)
        'membershipSignature': membershipSignature,
      'createdAtMs': createdAtMs,
      'updatedAtMs': updatedAtMs,
      'isCurrentDevice': isCurrentDevice,
    };
  }

  AccountDeviceIdentity copyWith({
    String? deviceId,
    String? peerId,
    String? signingPublicKey,
    String? agreementPublicKey,
    String? endpointId,
    String? fcmTokenHash,
    String? approvedByDeviceId,
    int? approvedAtMs,
    String? enrollmentSessionId,
    String? membershipSignature,
    int? createdAtMs,
    int? updatedAtMs,
    bool? isCurrentDevice,
  }) {
    return AccountDeviceIdentity(
      deviceId: deviceId ?? this.deviceId,
      peerId: peerId ?? this.peerId,
      signingPublicKey: signingPublicKey ?? this.signingPublicKey,
      agreementPublicKey: agreementPublicKey ?? this.agreementPublicKey,
      endpointId: endpointId ?? this.endpointId,
      fcmTokenHash: fcmTokenHash ?? this.fcmTokenHash,
      approvedByDeviceId: approvedByDeviceId ?? this.approvedByDeviceId,
      approvedAtMs: approvedAtMs ?? this.approvedAtMs,
      enrollmentSessionId: enrollmentSessionId ?? this.enrollmentSessionId,
      membershipSignature: membershipSignature ?? this.membershipSignature,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      isCurrentDevice: isCurrentDevice ?? this.isCurrentDevice,
    );
  }

  static String? _nullableTrimmed(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.toString());
  }
}
