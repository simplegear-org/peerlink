// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'relay_models.dart';

abstract class RelayClient {
  Future<RelayBlobStoreReceipt> storeBlobWithReceipt(
    RelayBlobUploadEnvelope envelope, {
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) => throw UnsupportedError('Blob store receipts are not supported');
  Future<RelayWriteReceipt> store(
    RelayEnvelope envelope, {
    List<String> preferredServers = const <String>[],
  });
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
    List<String>? relayServers,
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
  Future<RelayAckReceipt> ack(
    RelayAck ack, {
    List<String> relayServers = const <String>[],
  });
  void configureServers(List<String> servers);
}
