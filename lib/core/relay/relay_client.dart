import 'relay_models.dart';

abstract class RelayClient {
  Future<void> store(RelayEnvelope envelope);
  Future<void> storeGroup(RelayGroupEnvelope envelope);
  Future<void> updateGroupMembers(RelayGroupMembersUpdateEnvelope envelope);
  Future<void> storeBlob(
    RelayBlobUploadEnvelope envelope, {
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  });
  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })? onProgress,
  });
  Future<RelayFetchResult> fetch(String recipientId, {String? cursor, int limit});
  Future<void> ack(RelayAck ack);
  void configureServers(List<String> servers);
}
