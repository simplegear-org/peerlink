import 'dart:convert';

import '../../core/runtime/account_device_event.dart';
import '../../core/runtime/account_membership_update_payload.dart';
import '../../core/runtime/account_pairing_payload.dart';
import 'settings_controller_models.dart';

typedef SettingsReadValue = dynamic Function(String key);
typedef SettingsWriteValue = Future<void> Function(String key, dynamic value);
typedef SettingsDeleteValue = Future<void> Function(String key);

class SettingsPairingStateRepository {
  final SettingsReadValue _read;
  final SettingsWriteValue _write;
  final SettingsDeleteValue _delete;

  const SettingsPairingStateRepository({
    required SettingsReadValue read,
    required SettingsWriteValue write,
    required SettingsDeleteValue delete,
  }) : _read = read,
       _write = write,
       _delete = delete;

  PendingAccountPairingRequest? loadPendingRequest(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Неверный формат pending-привязки');
    }
    return PendingAccountPairingRequest.fromJson(decoded);
  }

  Future<void> savePendingRequest(
    String key,
    PendingAccountPairingRequest request,
  ) {
    return _write(key, jsonEncode(request.toJson()));
  }

  Future<void> clearPendingRequest(String key) => _delete(key);

  List<AccountPairingPayload> loadActiveSessions(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return const <AccountPairingPayload>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <AccountPairingPayload>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                AccountPairingPayload.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => !item.isExpired)
          .toList(growable: false);
    } catch (_) {
      return const <AccountPairingPayload>[];
    }
  }

  Future<void> storeActiveSession(
    String key,
    AccountPairingPayload payload,
    List<AccountPairingPayload> current,
  ) {
    final sessions = current
        .where((item) => item.sessionId != payload.sessionId)
        .toList(growable: true)
      ..add(payload);
    return _write(
      key,
      jsonEncode(sessions.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> removeActiveSession(
    String key,
    String sessionId,
    List<AccountPairingPayload> current,
  ) {
    final normalized = sessionId.trim();
    final sessions = current
        .where((item) => item.sessionId != normalized)
        .toList(growable: false);
    if (sessions.isEmpty) {
      return _delete(key);
    }
    return _write(
      key,
      jsonEncode(sessions.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  List<IncomingAccountPairingRequest> loadIncomingRequests(
    String key,
    Set<String> activeSessionIds,
  ) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return const <IncomingAccountPairingRequest>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <IncomingAccountPairingRequest>[];
      }
      return decoded
          .whereType<Map>()
          .map(
            (item) => IncomingAccountPairingRequest.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (item) => activeSessionIds.contains(item.payload.sessionId.trim()),
          )
          .toList(growable: false);
    } catch (_) {
      return const <IncomingAccountPairingRequest>[];
    }
  }

  Future<void> cleanupIncomingRequests(
    String key,
    Set<String> activeSessionIds,
  ) async {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        await _delete(key);
        return;
      }
      final filtered = decoded
          .whereType<Map>()
          .map(
            (item) => IncomingAccountPairingRequest.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where(
            (item) => activeSessionIds.contains(item.payload.sessionId.trim()),
          )
          .map((item) => item.toJson())
          .toList(growable: false);
      if (filtered.isEmpty) {
        await _delete(key);
        return;
      }
      await _write(key, jsonEncode(filtered));
    } catch (_) {
      await _delete(key);
    }
  }

  Future<void> removeIncomingRequest(
    String key,
    String requestId,
    List<IncomingAccountPairingRequest> current,
  ) {
    final filtered = current
        .where((item) => item.payload.requestId != requestId)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return _delete(key);
    }
    return _write(
      key,
      jsonEncode(filtered.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  AccountPairingRequestPayload? loadOutgoingRequest(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingRequestPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  AccountPairingApprovalPayload? loadApprovedPayload(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingApprovalPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  AccountPairingRejectedPayload? loadRejectedPayload(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingRejectedPayload.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  AccountPairingStagedServerConfig? loadStagedServerConfig(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return AccountPairingStagedServerConfig.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveStagedServerConfig(
    String key,
    AccountPairingStagedServerConfig value,
  ) {
    return _write(key, jsonEncode(value.toJson()));
  }

  Future<void> clearValue(String key) => _delete(key);

  List<AccountDeviceEvent> loadAccountDeviceEvents(String key) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return const <AccountDeviceEvent>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <AccountDeviceEvent>[];
      }
      final events = decoded
          .whereType<Map>()
          .map(
            (item) =>
                AccountDeviceEvent.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
      events.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
      return events;
    } catch (_) {
      return const <AccountDeviceEvent>[];
    }
  }

  Future<void> saveAccountDeviceEvents(
    String key,
    List<AccountDeviceEvent> events,
  ) {
    return _write(
      key,
      jsonEncode(events.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  List<AccountMembershipUpdatePayload> loadIncomingMembershipUpdates(
    String key,
  ) {
    final raw = _read(key);
    if (raw is! String || raw.trim().isEmpty) {
      return const <AccountMembershipUpdatePayload>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <AccountMembershipUpdatePayload>[];
      }
      final updates = decoded
          .whereType<Map>()
          .map(
            (item) => AccountMembershipUpdatePayload.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false);
      updates.sort((a, b) => a.updatedAtMs.compareTo(b.updatedAtMs));
      return updates;
    } catch (_) {
      return const <AccountMembershipUpdatePayload>[];
    }
  }

  Future<void> removeIncomingMembershipUpdate(
    String key,
    String updateId,
    List<AccountMembershipUpdatePayload> current,
  ) {
    final filtered = current
        .where((item) => item.updateId != updateId)
        .toList(growable: false);
    if (filtered.isEmpty) {
      return _delete(key);
    }
    return _write(
      key,
      jsonEncode(filtered.map((item) => item.toJson()).toList(growable: false)),
    );
  }
}
