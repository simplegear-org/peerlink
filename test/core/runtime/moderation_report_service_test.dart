import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/runtime/moderation_report_models.dart';
import 'package:peerlink/core/runtime/moderation_report_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

void main() {
  late StorageService storage;
  late ModerationReportService service;

  setUp(() async {
    await StorageService.resetForTesting();
    storage = StorageService();
    await storage.initForTesting(
      rootDirectory: Directory.systemTemp.createTempSync(
        'peerlink-report-test-',
      ),
    );
    service = ModerationReportService(
      settingsBox: storage.getSettings(),
      localPeerId: () => 'reporter-peer',
    );
  });

  test('metadata-only direct report stores no message content', () async {
    final report = await service.createDirectReport(
      reportedPeerId: 'bad-peer',
      reason: ModerationReportReason.spam,
      createdAt: DateTime.utc(2026, 8, 24),
    );

    expect(report['type'], 'direct_report');
    expect(report['reason'], 'spam');
    expect(report['reporterPeerId'], 'reporter-peer');
    expect(report['reportedPeerId'], 'bad-peer');
    expect(report['contentEncrypted'], isFalse);
    expect(report['content'], isNull);
  });

  test('illegal content reason uses server wire value', () async {
    final report = await service.createDirectReport(
      reportedPeerId: 'bad-peer',
      reason: ModerationReportReason.illegalContent,
      createdAt: DateTime.utc(2026, 8, 24),
    );

    expect(report['reason'], 'illegal_content');
  });

  test(
    'selected message report sends metadata without message content',
    () async {
      final report = await service.createDirectReport(
        reportedPeerId: 'bad-peer',
        reason: ModerationReportReason.harassment,
        selectedMessage: ModerationReportedMessageMetadata(
          messageId: 'm1',
          senderPeerId: 'bad-peer',
          incoming: true,
          timestamp: DateTime.utc(2026, 8, 24, 12),
          kind: 'text',
        ),
      );

      final encodedReport = jsonEncode(report);
      expect(encodedReport, isNot(contains('abusive selected text')));
      expect(encodedReport, isNot(contains('older message')));
      expect(encodedReport, isNot(contains('/tmp/private-path')));
      expect(encodedReport, isNot(contains('raw-file-bytes')));
      expect(encodedReport, isNot(contains('contacts')));
      expect(encodedReport, isNot(contains('private')));
      expect(encodedReport, isNot(contains('session')));

      expect(report['contentEncrypted'], isFalse);
      expect(report['content'], isNull);
      expect(report['contentOmittedReason'], 'ugc_content_not_collected');
      final message = Map<String, dynamic>.from(report['message'] as Map);
      expect(message['messageId'], 'm1');
      expect(message['senderPeerId'], 'bad-peer');
      expect(message['kind'], 'text');
      expect(message.containsKey('text'), isFalse);
    },
  );

  test(
    'group report targets message author and carries group metadata',
    () async {
      final report = await service.createDirectReport(
        reportedPeerId: 'bad-peer',
        reason: ModerationReportReason.threats,
        groupId: 'group:1',
        selectedMessage: ModerationReportedMessageMetadata(
          messageId: 'm1',
          senderPeerId: 'bad-peer',
          incoming: true,
          timestamp: DateTime.utc(2026, 8, 24, 12),
          kind: 'text',
        ),
      );

      expect(report['type'], 'group_report');
      expect(report['reportedPeerId'], 'bad-peer');
      expect(report['groupId'], 'group:1');
      expect(jsonEncode(report), isNot(contains('reported text')));
    },
  );

  test('delivered report is removed from pending outbox', () async {
    final delivered = <Map<String, dynamic>>[];
    service = ModerationReportService(
      settingsBox: storage.getSettings(),
      localPeerId: () => 'reporter-peer',
      publicKeyBase64: '',
      deliverReport: (report) async {
        delivered.add(Map<String, dynamic>.from(report));
      },
    );

    final report = await service.createDirectReport(
      reportedPeerId: 'bad-peer',
      reason: ModerationReportReason.spam,
    );

    expect(report['deliveryState'], 'sent');
    expect(delivered, hasLength(1));
    expect(
      storage.getSettings().get(ModerationReportService.pendingReportsKey),
      isEmpty,
    );
  });

  test('new report flushes existing pending outbox', () async {
    await storage.getSettings().put(ModerationReportService.pendingReportsKey, [
      <String, dynamic>{
        'id': 'old-report',
        'type': 'direct_report',
        'reason': 'spam',
        'reporterPeerId': 'reporter-peer',
        'reportedPeerId': 'bad-peer',
        'contentEncrypted': false,
        'content': null,
        'deliveryState': 'pending',
      },
    ]);
    final deliveredIds = <String>[];
    service = ModerationReportService(
      settingsBox: storage.getSettings(),
      localPeerId: () => 'reporter-peer',
      publicKeyBase64: '',
      deliverReport: (report) async {
        deliveredIds.add(report['id'] as String);
      },
    );

    await service.createDirectReport(
      reportedPeerId: 'bad-peer',
      reason: ModerationReportReason.spam,
    );

    expect(deliveredIds, contains('old-report'));
    expect(deliveredIds, hasLength(2));
    expect(
      storage.getSettings().get(ModerationReportService.pendingReportsKey),
      isEmpty,
    );
  });

  test('failed delivery keeps report pending with last error', () async {
    service = ModerationReportService(
      settingsBox: storage.getSettings(),
      localPeerId: () => 'reporter-peer',
      publicKeyBase64: '',
      deliverReport: (_) async {
        throw StateError('network down');
      },
    );

    await expectLater(
      service.createDirectReport(
        reportedPeerId: 'bad-peer',
        reason: ModerationReportReason.spam,
      ),
      throwsStateError,
    );

    final reports =
        storage.getSettings().get(ModerationReportService.pendingReportsKey)
            as List;
    expect(reports, hasLength(1));
    expect(
      (reports.single as Map)['lastDeliveryError'],
      contains('network down'),
    );
  });
}
