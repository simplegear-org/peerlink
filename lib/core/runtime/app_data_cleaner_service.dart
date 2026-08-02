import '../node/node_facade.dart';
import 'account_device_event.dart';
import 'account_membership_update_payload.dart';
import 'account_pairing_payload.dart';
import 'app_file_logger.dart';
import 'storage_service.dart';

class AppDataCleanerService {
  static const _pendingAccountPairingRequestKey =
      'pending_account_pairing_request.v1';
  static const _localAvatarPathKey = 'local_avatar_path_v1';
  static const _localAvatarUpdatedAtKey = 'local_avatar_updated_at_ms_v1';
  static const _localAvatarBytesB64Key = 'local_avatar_bytes_b64_v1';
  static const _localAvatarMimeTypeKey = 'local_avatar_mime_type_v1';
  static const _avatarSettingsKey = 'peer_avatars_v1';

  final NodeFacade facade;
  final StorageService storage;

  const AppDataCleanerService({required this.facade, required this.storage});

  Future<void> resetLocalAccount() async {
    await storage.init();
    await _clearAccountScopedData();
    await facade.resetToNewLocalAccount();
  }

  Future<void> resetDeviceCompletely() async {
    await storage.init();
    await _clearAccountScopedData();
    await storage.clearSettingsAndServiceData();
    await AppFileLogger.instance.clearAll();
    await facade.clearPersistedIdentity(preserveDeviceKeys: false);
  }

  Future<void> clearCurrentLog() {
    return AppFileLogger.instance.clearAll();
  }

  Future<void> clearAllLogs() {
    return AppFileLogger.instance.clearAll();
  }

  Future<void> clearManagedMediaStorage() async {
    await storage.init();
    await storage.clearManagedMediaStorage();
  }

  Future<void> clearMessagesDatabase() async {
    await storage.init();
    await storage.clearMessagesDatabase();
  }

  Future<void> clearSettingsAndServiceData() async {
    await storage.init();
    await storage.clearSettingsAndServiceData();
  }

  Future<void> _clearAccountScopedData() async {
    await storage.clearMessagesDatabase();
    await storage.clearManagedMediaStorage();
    await storage.getContacts().clear();
    await storage.getCalls().clear();
    await storage.getGroupMeta().clear();
    await storage.getGroupKeys().clear();

    final settings = storage.getSettings();
    for (final key in _accountScopedSettingKeys) {
      await settings.delete(key);
    }

    await facade.clearPersistedIdentity(preserveDeviceKeys: true);
  }

  static const List<String> _accountScopedSettingKeys = <String>[
    _pendingAccountPairingRequestKey,
    accountPairingIncomingRequestsStorageKey,
    accountPairingOutgoingRequestStorageKey,
    accountPairingApprovedPayloadStorageKey,
    accountPairingRejectedPayloadStorageKey,
    accountPairingStagedServerConfigStorageKey,
    accountPairingActiveSessionsStorageKey,
    accountMembershipUpdatesStorageKey,
    accountDeviceEventsStorageKey,
    _localAvatarPathKey,
    _localAvatarUpdatedAtKey,
    _localAvatarBytesB64Key,
    _localAvatarMimeTypeKey,
    _avatarSettingsKey,
  ];
}
