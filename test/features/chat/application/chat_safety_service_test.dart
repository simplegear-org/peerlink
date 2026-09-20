import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/runtime/secure_storage_wrapper.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/moderation_report_service.dart';
import 'package:peerlink/core/runtime/moderation_report_models.dart';
import 'package:peerlink/features/chat/application/chat_safety_service.dart';
import 'package:peerlink/features/chat/domain/chat.dart';
import 'package:peerlink/features/chat/domain/message.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late StorageService storage;
  late PeerAccessControlService access;
  late Directory directory;

  setUp(() async {
    await StorageService.resetForTesting();
    directory = await Directory.systemTemp.createTemp('chat-safety-');
    storage = StorageService();
    await storage.initForTesting(rootDirectory: directory);
    access = PeerAccessControlService.forStorage(storage);
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    await directory.delete(recursive: true);
  });

  test(
    'block hides immediately before network, preserves queue on failure and retries after restart',
    () async {
      final delivery = Completer<void>();
      final attempted = Completer<void>();
      final push = Completer<void>();
      final events = <String>[];
      final reports = ModerationReportService(
        settingsBox: storage.getSettings(),
        localPeerId: () => 'me',
        deliverReport: (report) {
          expect(
            storage.getSettings().get(
              ModerationReportService.pendingReportsKey,
            ),
            hasLength(1),
          );
          attempted.complete();
          return delivery.future;
        },
      );
      final safety = ChatSafetyService(
        accessControl: access,
        reports: reports,
        chats: () => const <Chat>[],
        notifyMessageUpdated: events.add,
        syncPushPolicy: (_) => push.future,
        log: (_) {},
      );
      final chat = Chat(peerId: 'bad', name: 'Bad');
      final operation = safety.blockAndReport(
        'bad',
        reason: ModerationReportReason.spam,
      );
      final failure = expectLater(operation, throwsStateError);
      await attempted.future;
      expect(events, ['bad']);
      expect(safety.isChatVisible(chat), isFalse);
      for (final type in IncomingInteractionType.values) {
        expect(
          access.evaluateIncoming(peerId: 'bad', type: type),
          IncomingInteractionDecision.blockedPeer,
        );
      }
      delivery.completeError(StateError('offline'));
      push.completeError(StateError('push offline'));
      await failure;
      expect(access.isBlocked('bad'), isTrue);
      expect(safety.isChatVisible(chat), isFalse);
      expect(
        storage.getSettings().get(ModerationReportService.pendingReportsKey),
        hasLength(1),
      );
      await StorageService.resetForTesting();
      storage = StorageService();
      await storage.initForTesting(rootDirectory: directory);
      // initForTesting creates empty boxes; restore the persisted settings snapshot.
      final saved =
          jsonDecode((await SecureStorageWrapper.read('peerlink.settings'))!)
              as Map;
      for (final entry in saved.entries) {
        await storage.getSettings().put(entry.key as String, entry.value);
      }
      expect(
        PeerAccessControlService.forStorage(storage).isBlocked('bad'),
        isTrue,
      );
      final sent = <Map<String, dynamic>>[];
      final restarted = ModerationReportService(
        settingsBox: storage.getSettings(),
        localPeerId: () => 'me',
        deliverReport: (report) async => sent.add(report),
      );
      await restarted.retryPendingReports();
      expect(sent.single['reportedPeerId'], 'bad');
      expect(sent.single['content'], isNull);
      expect(
        storage.getSettings().get(ModerationReportService.pendingReportsKey),
        isEmpty,
      );
    },
  );

  test(
    'group survives, blocked author and preview hide; unblock respects local deletion',
    () async {
      final reports = ModerationReportService(
        settingsBox: storage.getSettings(),
        localPeerId: () => 'me',
      );
      final safety = ChatSafetyService(
        accessControl: access,
        reports: reports,
        chats: () => const <Chat>[],
        notifyMessageUpdated: (_) {},
        syncPushPolicy: (_) async {},
        log: (_) {},
      );
      final group = Chat(peerId: 'group:1', name: 'Group', isGroup: true);
      Message message(String id, String author) => Message(
        id: id,
        peerId: group.peerId,
        senderPeerId: author,
        text: 'private $id',
        incoming: true,
        timestamp: DateTime.utc(2026),
      );
      final other = message('other', 'good');
      final bad = message('bad', 'bad');
      group.messages.addAll([other, bad]);
      await safety.blockAndReport(
        'bad',
        reason: ModerationReportReason.harassment,
        groupId: group.peerId,
      );
      expect(safety.isChatVisible(group), isTrue);
      expect(safety.visibleMessages(group), [other]);
      expect(safety.visiblePreview(group), other);
      expect(group.messages, [other, bad]);
      group.messages.remove(
        other,
      ); // Explicit local deletion must not be undone.
      await safety.unblock('bad');
      expect(safety.visibleMessages(group), [bad]);
      expect(safety.isChatVisible(Chat(peerId: 'bad', name: 'Bad')), isTrue);
      final queued =
          storage.getSettings().get(ModerationReportService.pendingReportsKey)
              as List;
      expect((queued.single as Map)['type'], 'group_report');
    },
  );

  test('visibility refresh includes every group chat', () async {
    final group = Chat(peerId: 'group:1', name: 'Group', isGroup: true);
    final direct = Chat(peerId: 'friend', name: 'Friend');
    final updates = <String>[];
    final safety = ChatSafetyService(
      accessControl: access,
      reports: ModerationReportService(
        settingsBox: storage.getSettings(),
        localPeerId: () => 'me',
      ),
      chats: () => [group, direct],
      notifyMessageUpdated: updates.add,
      syncPushPolicy: (_) async {},
      log: (_) {},
    );

    await safety.unblock('blocked-peer');

    expect(updates, ['blocked-peer', group.peerId]);
  });
}
