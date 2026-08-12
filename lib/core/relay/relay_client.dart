import 'relay_models.dart';

abstract class RelayClient {
  Future<RelayWriteReceipt> store(RelayEnvelope envelope);
  Future<RelayWriteReceipt> storeGroup(RelayGroupEnvelope envelope);
  Future<void> updateGroupMembers(RelayGroupMembersUpdateEnvelope envelope);
  Future<void> registerPushToken({
    required String peerId,
    required String token,
  });
  Future<void> unregisterPushToken({
    required String peerId,
    required String token,
  });
  Future<void> storeBlob(
    RelayBlobUploadEnvelope envelope, {
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  });
  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  });
  Future<RelayFetchResult> fetch(
    String recipientId, {
    String? cursor,
    int limit,
  });
  Future<RelayFetchResult> fetchFromServers(
    String recipientId, {
    required List<String> servers,
    String? cursor,
    int limit,
  });
  Future<void> ack(RelayAck ack);
  void configureServers(List<String> servers);
}
