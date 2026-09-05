import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

void main() {
  const service = RelayMediaTransferService();

  test(
    'restoreIncomingMedia returns failed result instead of throwing',
    () async {
      var attempts = 0;
      var saveCalled = false;

      final result = await service.restoreIncomingMedia(
        peerId: 'peer',
        messageId: 'message',
        blobId: 'blob:missing-network',
        fileName: 'photo.jpg',
        downloadBlob: (onProgress) {
          attempts += 1;
          return Future<RelayBlobDownload>.error(StateError('network down'));
        },
        saveBytes: ({required fileName, required bytes}) async {
          saveCalled = true;
          return '/tmp/$fileName';
        },
        onProgress:
            ({required receivedBytes, required totalBytes, required status}) {},
        onStage:
            ({
              required transferredBytes,
              required sendProgress,
              required transferStatus,
            }) {},
      );

      expect(result.status, RelayMediaRestoreStatus.failed);
      expect(result.errorKind, 'transient');
      expect(attempts, 2);
      expect(saveCalled, isFalse);
    },
  );

  test('restoreIncomingMedia handles synchronous download throws', () async {
    final result = await service.restoreIncomingMedia(
      peerId: 'peer',
      messageId: 'message',
      blobId: 'blob:no-relays',
      fileName: 'photo.jpg',
      downloadBlob: (onProgress) {
        throw StateError('No message relay servers configured');
      },
      saveBytes: ({required fileName, required bytes}) async {
        return '/tmp/$fileName';
      },
      onProgress:
          ({required receivedBytes, required totalBytes, required status}) {},
      onStage:
          ({
            required transferredBytes,
            required sendProgress,
            required transferStatus,
          }) {},
    );

    expect(result.status, RelayMediaRestoreStatus.failed);
    expect(result.errorKind, 'transient');
  });

  test('restoreIncomingMedia returns notFound result without saving', () async {
    var saveCalled = false;

    final result = await service.restoreIncomingMedia(
      peerId: 'peer',
      messageId: 'message',
      blobId: 'blob:not-found',
      fileName: 'photo.jpg',
      downloadBlob: (onProgress) async {
        return RelayBlobDownload.notFound('blob:not-found');
      },
      saveBytes: ({required fileName, required bytes}) async {
        saveCalled = true;
        return '/tmp/$fileName';
      },
      onProgress:
          ({required receivedBytes, required totalBytes, required status}) {},
      onStage:
          ({
            required transferredBytes,
            required sendProgress,
            required transferStatus,
          }) {},
    );

    expect(result.status, RelayMediaRestoreStatus.notFound);
    expect(result.errorKind, 'not_found');
    expect(saveCalled, isFalse);
  });

  test('restoreIncomingMedia saves downloaded payload', () async {
    final result = await service.restoreIncomingMedia(
      peerId: 'peer',
      messageId: 'message',
      blobId: 'blob:ok',
      fileName: null,
      downloadBlob: (onProgress) async {
        return RelayBlobDownload(
          id: 'blob:ok',
          fileName: 'file.bin',
          mimeType: 'application/octet-stream',
          sizeBytes: 3,
          payload: Uint8List.fromList(<int>[1, 2, 3]),
        );
      },
      saveBytes: ({required fileName, required bytes}) async {
        expect(fileName, 'file.bin');
        expect(bytes, <int>[1, 2, 3]);
        return '/tmp/$fileName';
      },
      onProgress:
          ({required receivedBytes, required totalBytes, required status}) {},
      onStage:
          ({
            required transferredBytes,
            required sendProgress,
            required transferStatus,
          }) {},
    );

    expect(result.status, RelayMediaRestoreStatus.saved);
    expect(result.path, '/tmp/file.bin');
  });

  test('retry coordinator keeps relay unavailable media resumable', () async {
    final root = await Directory.systemTemp.createTemp(
      'peerlink_relay_retry_test_',
    );
    final storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    addTearDown(() async {
      await StorageService.resetForTesting();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final retry = RelayMediaRetryCoordinator(
      settingsBox: storage.getSettings(),
    );
    const peerId = 'peer';
    const messageId = 'message';
    final key = RelayMediaRetryCoordinator.mediaKey(peerId, messageId);

    for (var i = 0; i < RelayMediaRetryCoordinator.maxAttempts; i++) {
      final canRetry = await retry.recordFailure(
        peerId: peerId,
        messageId: messageId,
        errorKind: 'unavailable',
      );
      expect(canRetry, isTrue);
    }

    expect(retry.isDue(key), isFalse);
    await retry.clear(peerId, messageId);
  });

  test('retry coordinator stops permanently missing relay blobs', () async {
    final root = await Directory.systemTemp.createTemp(
      'peerlink_relay_retry_test_',
    );
    final storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    addTearDown(() async {
      await StorageService.resetForTesting();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    final retry = RelayMediaRetryCoordinator(
      settingsBox: storage.getSettings(),
    );
    const peerId = 'peer';
    const messageId = 'message';
    final key = RelayMediaRetryCoordinator.mediaKey(peerId, messageId);

    final canRetry = await retry.recordFailure(
      peerId: peerId,
      messageId: messageId,
      errorKind: 'not_found',
    );

    expect(canRetry, isFalse);
    expect(retry.isDue(key), isFalse);
  });
}
