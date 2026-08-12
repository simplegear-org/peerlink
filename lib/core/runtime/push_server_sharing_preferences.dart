import 'storage_service.dart';

class PushServerSharingPreferences {
  static const String shareOutgoingServersKey =
      'push_server_sharing.share_outgoing_servers';
  static const String receiveIncomingServersKey =
      'push_server_sharing.receive_incoming_servers';

  const PushServerSharingPreferences._();

  static bool shareOutgoingServers(SecureStorageBox settings) {
    return settings.get(shareOutgoingServersKey) != false;
  }

  static bool receiveIncomingServers(SecureStorageBox settings) {
    return shareOutgoingServers(settings) &&
        settings.get(receiveIncomingServersKey) != false;
  }

  static Future<void> setShareOutgoingServers(
    SecureStorageBox settings,
    bool value,
  ) async {
    await settings.put(shareOutgoingServersKey, value);
    if (!value) {
      await settings.put(receiveIncomingServersKey, false);
    }
  }

  static Future<void> setReceiveIncomingServers(
    SecureStorageBox settings,
    bool value,
  ) async {
    if (!shareOutgoingServers(settings)) {
      await settings.put(receiveIncomingServersKey, false);
      return;
    }
    await settings.put(receiveIncomingServersKey, value);
  }
}
