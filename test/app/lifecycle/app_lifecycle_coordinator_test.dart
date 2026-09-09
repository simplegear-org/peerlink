import 'package:flutter/widgets.dart';
import 'package:peerlink/app/lifecycle/app_lifecycle_coordinator.dart';
import 'package:peerlink/features/calls/platform/ios_callkit_service.dart';
import 'package:test/test.dart';

void main() {
  test('resume refreshes voip registration and restriction status', () async {
    final callkit = _FakeIosCallkitService();
    var restrictionRefreshes = 0;
    var moderationRetries = 0;
    final coordinator = AppLifecycleCoordinator(
      iosCallkitService: callkit,
      refreshRestrictionStatus: ({required reason}) async {
        restrictionRefreshes++;
        expect(reason, 'resume');
      },
      retryModerationReports: () => moderationRetries++,
    );

    coordinator.handleLifecycleState(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    expect(callkit.refreshes, 0);
    expect(restrictionRefreshes, 0);
    expect(moderationRetries, 0);

    coordinator.handleLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(callkit.refreshes, 1);
    expect(callkit.lastReason, 'resume');
    expect(restrictionRefreshes, 1);
    expect(moderationRetries, 1);
  });
}

class _FakeIosCallkitService implements IosCallkitService {
  int refreshes = 0;
  String? lastReason;

  @override
  Future<void> refreshVoipRegistration({String reason = 'manual'}) async {
    refreshes++;
    lastReason = reason;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
