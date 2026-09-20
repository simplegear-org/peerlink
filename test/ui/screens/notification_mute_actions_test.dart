import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/notifications/application/notification_mute_preferences.dart';
import 'package:peerlink/features/notifications/domain/notification_mute_state.dart';
import 'package:peerlink/ui/screens/notification_mute_actions.dart';

void main() {
  testWidgets('message and call switches use independent mute channels', (
    tester,
  ) async {
    final preferences = _FakeNotificationMutePreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationMuteActions(
            targetId: 'peer-a',
            messageChannel: NotificationMuteChannel.directMessage,
            callChannel: NotificationMuteChannel.directCall,
            preferences: preferences,
          ),
        ),
      ),
    );

    expect(find.text('Включены'), findsNWidgets(2));
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(
      preferences.isMuted(
        channel: NotificationMuteChannel.directMessage,
        id: 'peer-a',
      ),
      isTrue,
    );
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).last).value, isTrue);
    expect(
      preferences.isMuted(
        channel: NotificationMuteChannel.directCall,
        id: 'peer-a',
      ),
      isFalse,
    );
    expect(find.text('Без звука'), findsOneWidget);
    expect(find.text('Включены'), findsOneWidget);
  });

  testWidgets('group call switch does not mute group messages', (tester) async {
    final preferences = _FakeNotificationMutePreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationMuteActions(
            targetId: 'group-a',
            messageChannel: NotificationMuteChannel.groupMessage,
            callChannel: NotificationMuteChannel.groupCall,
            preferences: preferences,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch).last);
    await tester.pump();

    expect(
      preferences.isMuted(
        channel: NotificationMuteChannel.groupMessage,
        id: 'group-a',
      ),
      isFalse,
    );
    expect(
      preferences.isMuted(
        channel: NotificationMuteChannel.groupCall,
        id: 'group-a',
      ),
      isTrue,
    );
  });
}

class _FakeNotificationMutePreferences implements NotificationMutePreferences {
  NotificationMuteState _state = NotificationMuteState.empty();

  @override
  NotificationMuteState get state => _state;

  @override
  bool isMuted({required NotificationMuteChannel channel, required String id}) {
    return _state.isMuted(channel: channel, id: id);
  }

  @override
  Future<void> setMuted({
    required NotificationMuteChannel channel,
    required String id,
    required bool muted,
  }) async {
    _state = _state.withMuted(channel: channel, id: id, muted: muted);
  }
}
