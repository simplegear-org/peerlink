import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/notifications/domain/notification_mute_state.dart';
import 'package:peerlink/features/notifications/infrastructure/settings_notification_mute_preferences.dart';

void main() {
  late Directory root;
  late StorageService storage;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('peerlink-notification-mute-');
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(rootDirectory: root);
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    await root.delete(recursive: true);
  });

  test('persists four independent direct and group mute channels', () async {
    final preferences = SettingsNotificationMutePreferences(
      settings: storage.getSettings(),
    );

    await preferences.setMuted(
      channel: NotificationMuteChannel.directMessage,
      id: ' peer-a ',
      muted: true,
    );
    await preferences.setMuted(
      channel: NotificationMuteChannel.directCall,
      id: 'peer-a',
      muted: true,
    );
    await preferences.setMuted(
      channel: NotificationMuteChannel.groupMessage,
      id: 'group-a',
      muted: true,
    );
    await preferences.setMuted(
      channel: NotificationMuteChannel.groupCall,
      id: 'group-a',
      muted: true,
    );
    await preferences.setMuted(
      channel: NotificationMuteChannel.directMessage,
      id: 'peer-a',
      muted: false,
    );

    final restored = SettingsNotificationMutePreferences(
      settings: storage.getSettings(),
    );
    expect(
      restored.isMuted(
        channel: NotificationMuteChannel.directMessage,
        id: 'peer-a',
      ),
      isFalse,
    );
    expect(
      restored.isMuted(
        channel: NotificationMuteChannel.directCall,
        id: 'peer-a',
      ),
      isTrue,
    );
    expect(
      restored.isMuted(
        channel: NotificationMuteChannel.groupMessage,
        id: 'group-a',
      ),
      isTrue,
    );
    expect(
      restored.isMuted(
        channel: NotificationMuteChannel.groupCall,
        id: 'group-a',
      ),
      isTrue,
    );
  });

  test('ignores malformed persisted entries without widening a mute', () async {
    await storage.getSettings().put(
      SettingsNotificationMutePreferences.storageKey,
      <String, dynamic>{
        'mutedMessagePeerIds': <dynamic>['peer-a', 42, ' ', 'peer-a'],
        'mutedCallPeerIds': 'not-a-list',
      },
    );

    final preferences = SettingsNotificationMutePreferences(
      settings: storage.getSettings(),
    );

    expect(
      preferences.isMuted(
        channel: NotificationMuteChannel.directMessage,
        id: 'peer-a',
      ),
      isTrue,
    );
    expect(
      preferences.state.mutedIdsFor(NotificationMuteChannel.directCall),
      isEmpty,
    );
  });

  test(
    'starts best-effort policy sync after a persisted mute change',
    () async {
      var syncCalls = 0;
      final preferences = SettingsNotificationMutePreferences(
        settings: storage.getSettings(),
        onChanged: () async {
          syncCalls += 1;
        },
      );

      await preferences.setMuted(
        channel: NotificationMuteChannel.directCall,
        id: 'peer-a',
        muted: true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(syncCalls, 1);
    },
  );
}
