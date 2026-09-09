import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/features/moderation/application/moderation_lifecycle_service.dart';
import 'package:peerlink/features/moderation/application/moderation_reports_api.dart';

void main() {
  test(
    'retries pending reports on startup, resume and connectivity recovery',
    () async {
      final connectivity = StreamController<List<ConnectivityResult>>();
      final reports = _FakeModerationReportsApi();
      final service = ModerationLifecycleService(
        reports: reports,
        connectivityChanges: connectivity.stream,
        log: (_) {},
      );

      service.start();
      await _settle();
      expect(reports.retryCalls, 1);

      connectivity.add(const [ConnectivityResult.none]);
      await _settle();
      expect(reports.retryCalls, 1);

      connectivity.add(const [ConnectivityResult.wifi]);
      await _settle();
      expect(reports.retryCalls, 2);

      service.handleAppResumed();
      await _settle();
      expect(reports.retryCalls, 3);

      await service.dispose();
      await connectivity.close();
    },
  );
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

class _FakeModerationReportsApi implements ModerationReportsApi {
  int retryCalls = 0;

  @override
  Future<void> retryPendingReports() async {
    retryCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
