import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/relay/relay_media_transfer_service.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/relay/relay_transfer_status.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/chat/application/chat_file_progress_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_file_queue_service.dart';
import 'package:peerlink/features/chat/application/chat_incoming_media_restore_coordinator.dart';
import 'package:peerlink/features/chat/application/chat_controller_parts.dart';
import 'package:peerlink/features/chat/application/chat_media_restore_service.dart';
import 'package:peerlink/features/chat/application/chat_message_mutation_service.dart';
import 'package:peerlink/features/chat/application/chat_outbound_codec.dart';
import 'package:peerlink/features/chat/application/chat_runtime_api.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';
import 'package:peerlink/features/chat/infrastructure/chat_repository.dart';
import 'package:peerlink/features/chat/infrastructure/chat_summary_store.dart';

void main() {
  late Directory root;
  late StorageService storage;
  late RelayMediaRetryCoordinator retry;
  late Map<String, Message> messages;
  late List<String> backgroundRestores;

  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'peerlink_chat_media_restore_test_',
    );
    storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
    retry = RelayMediaRetryCoordinator(settingsBox: storage.getSettings());
    messages = <String, Message>{};
    backgroundRestores = <String>[];
  });

  tearDown(() async {
    retry.dispose();
    await StorageService.resetForTesting();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test(
    'TEST RELAY-MEDIA-001 direct restore persists localFilePath and no retry',
    () async {
      final service = _service(
        retry: retry,
        messages: messages,
        backgroundRestores: backgroundRestores,
      );
      final message = _message(
        peerId: 'peer-a',
        messageId: 'm-direct',
        transferId: 'dirblob:peer-a|m-direct|blob-direct',
      );
      messages[_key(message.peerId, message.id)] = message;

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-direct',
        fileName: 'photo.jpg',
        downloadBlob: _download(<int>[1, 2, 3]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );

      final restored = messages[_key(message.peerId, message.id)]!;
      expect(path, '/media/peer-a/m-direct-photo.jpg');
      expect(restored.localFilePath, path);
      expect(restored.transferStatus, isNull);
      expect(restored.sendProgress, isNull);
      expect(retry.attemptsForKey(_key(message.peerId, message.id)), 0);
      expect(backgroundRestores, isEmpty);
    },
  );

  test(
    'TEST RELAY-MEDIA-002 group restore persists localFilePath and no retry',
    () async {
      final service = _service(
        retry: retry,
        messages: messages,
        backgroundRestores: backgroundRestores,
      );
      final message = _message(
        peerId: 'group-a',
        messageId: 'm-group',
        transferId: 'grpblob:group-a|m-group|blob-group',
      );
      messages[_key(message.peerId, message.id)] = message;

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-group',
        fileName: 'video.mp4',
        downloadBlob: _download(<int>[4, 5, 6]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );

      final restored = messages[_key(message.peerId, message.id)]!;
      expect(path, '/media/group-a/m-group-video.mp4');
      expect(restored.localFilePath, path);
      expect(restored.transferStatus, isNull);
      expect(retry.attemptsForKey(_key(message.peerId, message.id)), 0);
      expect(backgroundRestores, isEmpty);
    },
  );

  test(
    'TEST RELAY-MEDIA-003 thumbnail failure keeps restored media successful',
    () async {
      final service = _service(
        retry: retry,
        messages: messages,
        backgroundRestores: backgroundRestores,
        ensureThumbnail: (_) =>
            Future<String?>.error(StateError('thumbnail failed')),
      );
      final message = _message(
        peerId: 'peer-a',
        messageId: 'm-thumb',
        transferId: 'dirblob:peer-a|m-thumb|blob-thumb',
      );
      messages[_key(message.peerId, message.id)] = message;

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-thumb',
        fileName: 'photo.jpg',
        downloadBlob: _download(<int>[1, 2, 3]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );
      await Future<void>.delayed(Duration.zero);

      final restored = messages[_key(message.peerId, message.id)]!;
      expect(path, '/media/peer-a/m-thumb-photo.jpg');
      expect(restored.localFilePath, path);
      expect(restored.transferStatus, isNull);
      expect(restored.thumbnailPath, isNull);
      expect(retry.attemptsForKey(_key(message.peerId, message.id)), 0);
      expect(backgroundRestores, isEmpty);
    },
  );

  test(
    'TEST RELAY-MEDIA-004 save failure does not schedule relay retry',
    () async {
      final service = _service(
        retry: retry,
        messages: messages,
        backgroundRestores: backgroundRestores,
        saveMediaBytes:
            ({
              required peerId,
              required messageId,
              required fileName,
              required bytes,
            }) async => '',
      );
      final message = _message(
        peerId: 'peer-a',
        messageId: 'm-save',
        transferId: 'dirblob:peer-a|m-save|blob-save',
      );
      messages[_key(message.peerId, message.id)] = message;

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-save',
        fileName: 'photo.jpg',
        downloadBlob: _download(<int>[1, 2, 3]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );

      final restored = messages[_key(message.peerId, message.id)]!;
      expect(path, isNull);
      expect(restored.localFilePath, isNull);
      expect(
        restored.transferStatus,
        RelayMediaTransferService.incomingSaveErrorStatus,
      );
      expect(retry.attemptsForKey(_key(message.peerId, message.id)), 0);
      expect(backgroundRestores, isEmpty);
    },
  );

  test(
    'retryable download failure shows retry status instead of error',
    () async {
      final service = _service(
        retry: retry,
        messages: messages,
        backgroundRestores: backgroundRestores,
      );
      final message = _message(
        peerId: 'peer-a',
        messageId: 'm-download-retry',
        transferId: 'dirblob:peer-a|m-download-retry|blob-download-retry',
      );
      messages[_key(message.peerId, message.id)] = message;

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-download-retry',
        fileName: 'photo.jpg',
        downloadBlob: (_) => Future<RelayBlobDownload>.error(
          StateError('temporary download failure'),
        ),
        restoreInBackground: _background(backgroundRestores),
      );

      expect(path, isNull);
      expect(
        messages[_key(message.peerId, message.id)]!.transferStatus,
        RelayMediaTransferService.incomingRetryStatus,
      );
      expect(retry.attemptsForKey(_key(message.peerId, message.id)), 1);
    },
  );

  test('new download progress replaces stale download error status', () async {
    final chats = <String, Chat>{};
    final chat = Chat(
      peerId: 'peer-progress',
      name: 'peer-progress',
      messagesLoaded: true,
    );
    final message = ChatMessageCopy.copy(
      _message(
        peerId: chat.peerId,
        messageId: 'm-progress',
        transferId: 'dirblob:peer-progress|m-progress|blob-progress',
      ),
      sendProgress: 0.0,
      transferStatus: RelayMediaTransferService.incomingErrorStatus,
    );
    chat.messages.add(message);
    chats[chat.peerId] = chat;
    final mediaRestoreService = _service(
      retry: retry,
      messages: <String, Message>{},
      backgroundRestores: backgroundRestores,
    );
    final progressCoordinator = ChatFileProgressCoordinator(
      fileQueueService: ChatFileQueueService(),
      chats: chats,
      incomingMediaRestoreCoordinator: ChatIncomingMediaRestoreCoordinator(
        mediaRestoreService: mediaRestoreService,
        outboundCodec: const ChatOutboundCodec(
          localPeerIdProvider: _testLocalPeerId,
        ),
        facade: _FakeChatRuntimeApi(),
        decodeGroupBlobBytes:
            ({required groupId, required encryptedBytes}) async =>
                encryptedBytes,
        decodeDirectBlobBytes:
            ({required peerId, required encryptedBytes}) async =>
                encryptedBytes,
      ),
      incomingRelayNotConfiguredStatus:
          RelayMediaTransferService.incomingRelayNotConfiguredStatus,
      incomingRelayUnavailableStatus:
          RelayMediaTransferService.incomingRelayUnavailableStatus,
      notifyMessageUpdated: (_) {},
    );

    await progressCoordinator.applyFileProgressUpdate(
      chat.peerId,
      message.id,
      sentBytes: 50,
      totalBytes: 100,
      statusText: RelayMediaTransferService.incomingDownloadStatus,
    );

    expect(
      chat.messages.single.transferStatus,
      RelayMediaTransferService.incomingDownloadStatus,
    );
    expect(chat.messages.single.sendProgress, 0.5);
  });

  test('incoming relay media ignores delayed outgoing progress', () async {
    final chats = <String, Chat>{};
    final chat = Chat(
      peerId: 'peer-progress',
      name: 'peer-progress',
      messagesLoaded: true,
    );
    final message = ChatMessageCopy.copy(
      _message(
        peerId: chat.peerId,
        messageId: 'm-progress',
        transferId: 'dirblob:peer-progress|m-progress|blob-progress',
      ),
      sendProgress: 1.0,
      transferStatus: RelayMediaTransferService.incomingCompleteStatus,
    );
    chat.messages.add(message);
    chats[chat.peerId] = chat;
    final mediaRestoreService = _service(
      retry: retry,
      messages: <String, Message>{},
      backgroundRestores: backgroundRestores,
    );
    final progressCoordinator = ChatFileProgressCoordinator(
      fileQueueService: ChatFileQueueService(),
      chats: chats,
      incomingMediaRestoreCoordinator: ChatIncomingMediaRestoreCoordinator(
        mediaRestoreService: mediaRestoreService,
        outboundCodec: const ChatOutboundCodec(
          localPeerIdProvider: _testLocalPeerId,
        ),
        facade: _FakeChatRuntimeApi(),
        decodeGroupBlobBytes:
            ({required groupId, required encryptedBytes}) async =>
                encryptedBytes,
        decodeDirectBlobBytes:
            ({required peerId, required encryptedBytes}) async =>
                encryptedBytes,
      ),
      incomingRelayNotConfiguredStatus:
          RelayMediaTransferService.incomingRelayNotConfiguredStatus,
      incomingRelayUnavailableStatus:
          RelayMediaTransferService.incomingRelayUnavailableStatus,
      notifyMessageUpdated: (_) {},
    );

    await progressCoordinator.applyFileProgressUpdate(
      chat.peerId,
      message.id,
      sentBytes: 100,
      totalBytes: 100,
      statusText: RelayTransferStatus.outgoingUploadingRelay,
    );

    expect(
      chat.messages.single.transferStatus,
      RelayMediaTransferService.incomingCompleteStatus,
    );
    expect(chat.messages.single.sendProgress, 1.0);
  });

  test(
    'TEST RELAY-MEDIA-005 persistence failure does not schedule relay retry',
    () async {
      final service = _service(
        retry: retry,
        messages: messages,
        backgroundRestores: backgroundRestores,
        replaceMessage: (_, _, _) =>
            Future<void>.error(StateError('persist failed')),
      );
      final message = _message(
        peerId: 'peer-a',
        messageId: 'm-persist',
        transferId: 'dirblob:peer-a|m-persist|blob-persist',
      );
      messages[_key(message.peerId, message.id)] = message;

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-persist',
        fileName: 'photo.jpg',
        downloadBlob: _download(<int>[1, 2, 3]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );

      expect(path, isNull);
      expect(retry.attemptsForKey(_key(message.peerId, message.id)), 0);
      expect(backgroundRestores, isEmpty);
    },
  );

  test(
    'TEST RELAY-MEDIA-006 restore persists localFilePath through SQLite stack',
    () async {
      const peerId = 'peer-sqlite';
      const messageId = 'm-sqlite';
      final chats = <String, Chat>{};
      final repository = ChatRepository(
        storage: storage,
        ensureChat: (id, {fallbackName}) => chats.putIfAbsent(
          id,
          () => Chat(peerId: id, name: fallbackName ?? id),
        ),
        persistChatSummary: (chat) =>
            const ChatDatabaseSummaryStore().save(chat.peerId, chat.toJson()),
        isInitialUnreadAnchor: (message) => message.incoming && !message.isRead,
      );
      final mutationService = ChatMessageMutationService(
        storage: storage,
        chatRepository: repository,
        chats: chats,
      );
      final service = ChatMediaRestoreService(
        relayMediaTransfer: const RelayMediaTransferService(),
        relayMediaRetry: retry,
        findMessage: mutationService.findMessage,
        replaceMessage: mutationService.replaceMessage,
        updateFileProgress:
            (
              _,
              _, {
              required sentBytes,
              required totalBytes,
              required statusText,
            }) async {},
        saveMediaBytes:
            ({
              required peerId,
              required messageId,
              required fileName,
              required bytes,
            }) async => '/media/$peerId/$messageId-$fileName',
        ensureThumbnail: (_) async => null,
        clearProgressUpdate: (_, _) {},
        notifyMessageUpdated: (_) {},
        mediaKeyFor: _key,
        isMessageUpdatesClosed: () => false,
      );
      final message = _message(
        peerId: peerId,
        messageId: messageId,
        transferId: 'dirblob:$peerId|$messageId|blob-sqlite',
      );

      await mutationService.appendMessage(peerId, message);
      final path = await service.restoreMediaFromRelay(
        peerId: peerId,
        messageId: messageId,
        blobId: 'blob-sqlite',
        fileName: 'photo.jpg',
        downloadBlob: _download(<int>[1, 2, 3]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );

      final stored = await const ChatDatabaseChatMessageStore().read(peerId);
      final restored = Message.fromJson(stored.single);
      expect(path, '/media/$peerId/$messageId-photo.jpg');
      expect(restored.localFilePath, path);
      expect(restored.transferStatus, isNull);
      expect(restored.sendProgress, isNull);
      expect(retry.attemptsForKey(_key(peerId, messageId)), 0);
      expect(backgroundRestores, isEmpty);
    },
  );

  test(
    'TEST RELAY-MEDIA-007 delayed progress cannot overwrite final restore state',
    () async {
      final delayedProgress = Completer<void>();
      final chats = <String, Chat>{};
      final chat = Chat(
        peerId: 'peer-race',
        name: 'peer-race',
        messagesLoaded: true,
        hasMoreMessages: false,
      );
      chats[chat.peerId] = chat;
      final message = _message(
        peerId: chat.peerId,
        messageId: 'm-race',
        transferId: 'dirblob:peer-race|m-race|blob-race',
      );
      chat.messages.add(message);
      final mediaRestoreService = _service(
        retry: retry,
        messages: <String, Message>{},
        backgroundRestores: backgroundRestores,
      );
      final progressCoordinator = ChatFileProgressCoordinator(
        fileQueueService: ChatFileQueueService(),
        chats: chats,
        incomingMediaRestoreCoordinator: ChatIncomingMediaRestoreCoordinator(
          mediaRestoreService: mediaRestoreService,
          outboundCodec: const ChatOutboundCodec(
            localPeerIdProvider: _testLocalPeerId,
          ),
          facade: _FakeChatRuntimeApi(),
          decodeGroupBlobBytes:
              ({required groupId, required encryptedBytes}) async =>
                  encryptedBytes,
          decodeDirectBlobBytes:
              ({required peerId, required encryptedBytes}) async =>
                  encryptedBytes,
        ),
        incomingRelayNotConfiguredStatus:
            RelayMediaTransferService.incomingRelayNotConfiguredStatus,
        incomingRelayUnavailableStatus:
            RelayMediaTransferService.incomingRelayUnavailableStatus,
        notifyMessageUpdated: (_) {},
      );
      final service = ChatMediaRestoreService(
        relayMediaTransfer: const RelayMediaTransferService(),
        relayMediaRetry: retry,
        findMessage: (peerId, messageId) async => chat.messages
            .where((message) => message.id == messageId)
            .cast<Message?>()
            .firstOrNull,
        replaceMessage: (peerId, messageId, transform) async {
          final index = chat.messages.indexWhere(
            (message) => message.id == messageId,
          );
          if (index != -1) {
            chat.messages[index] = transform(chat.messages[index]);
          }
        },
        updateFileProgress:
            (
              peerId,
              messageId, {
              required sentBytes,
              required totalBytes,
              required statusText,
            }) async {
              await delayedProgress.future;
              await progressCoordinator.updateFileProgress(
                peerId,
                messageId,
                sentBytes: sentBytes,
                totalBytes: totalBytes,
                statusText: statusText,
              );
            },
        saveMediaBytes:
            ({
              required peerId,
              required messageId,
              required fileName,
              required bytes,
            }) async => '/media/$peerId/$messageId-$fileName',
        ensureThumbnail: (_) async => null,
        clearProgressUpdate: progressCoordinator.clearProgressUpdate,
        notifyMessageUpdated: (_) {},
        mediaKeyFor: _key,
        isMessageUpdatesClosed: () => false,
      );

      final path = await service.restoreMediaFromRelay(
        peerId: message.peerId,
        messageId: message.id,
        blobId: 'blob-race',
        fileName: 'photo.jpg',
        downloadBlob: _download(<int>[1, 2, 3]),
        transformPayload: (blob) async => blob.payload,
        restoreInBackground: _background(backgroundRestores),
      );
      delayedProgress.complete();
      await Future<void>.delayed(Duration.zero);

      final restored = chat.messages.single;
      expect(path, '/media/peer-race/m-race-photo.jpg');
      expect(restored.localFilePath, path);
      expect(restored.transferStatus, isNull);
      expect(restored.sendProgress, isNull);
      expect(restored.transferredBytes, isNull);
    },
  );
}

ChatMediaRestoreService _service({
  required RelayMediaRetryCoordinator retry,
  required Map<String, Message> messages,
  required List<String> backgroundRestores,
  RestoreSaveMediaBytes? saveMediaBytes,
  RestoreReplaceMessage? replaceMessage,
  RestoreEnsureThumbnail? ensureThumbnail,
}) {
  return ChatMediaRestoreService(
    relayMediaTransfer: const RelayMediaTransferService(),
    relayMediaRetry: retry,
    findMessage: (peerId, messageId) async => messages[_key(peerId, messageId)],
    replaceMessage:
        replaceMessage ??
        (peerId, messageId, transform) async {
          final key = _key(peerId, messageId);
          final current = messages[key];
          if (current == null) {
            return;
          }
          messages[key] = transform(current);
        },
    updateFileProgress:
        (
          peerId,
          messageId, {
          required sentBytes,
          required totalBytes,
          required statusText,
        }) async {
          final key = _key(peerId, messageId);
          final current = messages[key];
          if (current == null) {
            return;
          }
          messages[key] = ChatMessageCopy.copy(
            current,
            transferredBytes: sentBytes,
            sendProgress: totalBytes == null ? null : sentBytes / totalBytes,
            transferStatus: statusText,
          );
        },
    saveMediaBytes:
        saveMediaBytes ??
        ({
          required peerId,
          required messageId,
          required fileName,
          required bytes,
        }) async {
          return '/media/$peerId/$messageId-$fileName';
        },
    ensureThumbnail: ensureThumbnail ?? (_) async => null,
    clearProgressUpdate: (_, _) {},
    notifyMessageUpdated: (_) {},
    mediaKeyFor: _key,
    isMessageUpdatesClosed: () => false,
  );
}

RelayMediaDownloadOperation _download(List<int> payload) {
  return (onProgress) async {
    onProgress(
      receivedBytes: payload.length,
      totalBytes: payload.length,
      status: RelayMediaTransferService.incomingDownloadStatus,
    );
    return RelayBlobDownload(
      id: 'blob',
      fileName: 'download.bin',
      mimeType: 'application/octet-stream',
      sizeBytes: payload.length,
      payload: Uint8List.fromList(payload),
    );
  };
}

RestoreBackground _background(List<String> calls) {
  return (message, {required isGroup, force = false}) {
    calls.add('${message.peerId}:${message.id}:$isGroup:$force');
  };
}

Message _message({
  required String peerId,
  required String messageId,
  required String transferId,
}) {
  return Message(
    id: messageId,
    peerId: peerId,
    text: 'file',
    incoming: true,
    timestamp: DateTime.utc(2026, 1, 1),
    kind: MessageKind.file,
    fileName: 'file.bin',
    transferId: transferId,
  );
}

String _key(String peerId, String messageId) =>
    RelayMediaRetryCoordinator.mediaKey(peerId, messageId);

String _testLocalPeerId() => 'local-peer';

class _FakeChatRuntimeApi implements ChatRuntimeApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
