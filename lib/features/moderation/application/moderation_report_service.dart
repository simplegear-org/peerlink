// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:uuid/uuid.dart';

import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/features/moderation/domain/moderation_report_models.dart';

import 'moderation_reports_api.dart';
import 'moderation_report_outbox.dart';

class ModerationReportService implements ModerationReportsApi {
  static const String pendingReportsKey = 'peerlink.moderation.reports.v1';
  static const String moderationPublicKeyBase64 = String.fromEnvironment(
    'PEERLINK_MODERATION_PUBLIC_KEY_X25519_B64',
    defaultValue: '',
  );

  final SecureStorageBox settingsBox;
  final ModerationReportOutbox? outbox;
  final String Function() localPeerId;
  final Future<void> Function(Map<String, dynamic> report)? deliverReport;
  final Uuid _uuid;
  Future<void> _deliveryTail = Future<void>.value();

  /// Reuses the durable outbox on startup, resume and connectivity recovery.
  @override
  Future<void> retryPendingReports() async {
    final delivery = deliverReport;
    if (delivery != null) await _scheduleFlush(delivery, raiseForId: '');
  }

  Future<void> _scheduleFlush(
    Future<void> Function(Map<String, dynamic>) delivery, {
    required String raiseForId,
  }) {
    final next = _deliveryTail.then(
      (_) => _flushPendingReports(delivery, raiseForId: raiseForId),
    );
    _deliveryTail = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return next;
  }

  ModerationReportService({
    required this.settingsBox,
    this.outbox,
    required this.localPeerId,
    this.deliverReport,
    String? publicKeyBase64,
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  @override
  Future<Map<String, dynamic>> createDirectReport({
    required String reportedPeerId,
    required ModerationReportReason reason,
    ModerationReportedMessageMetadata? selectedMessage,
    DateTime? createdAt,
    String? groupId,
  }) async {
    final normalizedPeerId = reportedPeerId.trim();
    if (normalizedPeerId.isEmpty) {
      throw ArgumentError.value(reportedPeerId, 'reportedPeerId');
    }
    final timestamp = (createdAt ?? DateTime.now().toUtc()).toUtc();
    final normalizedGroupId = groupId?.trim();
    final report = <String, dynamic>{
      'schemaVersion': 1,
      'id': _uuid.v4(),
      'type': normalizedGroupId?.isNotEmpty == true
          ? 'group_report'
          : 'direct_report',
      'reason': _reasonWireValue(reason),
      'createdAt': timestamp.toIso8601String(),
      'reporterPeerId': localPeerId().trim(),
      'reportedPeerId': normalizedPeerId,
      'contentEncrypted': false,
      'content': null,
      'contentOmittedReason': 'ugc_content_not_collected',
      if (normalizedGroupId?.isNotEmpty == true) 'groupId': normalizedGroupId,
      if (selectedMessage != null) 'message': selectedMessage.toJson(),
      'deliveryState': 'pending',
    };
    await _appendPendingReport(report);
    final delivery = deliverReport;
    if (delivery != null) {
      await _scheduleFlush(delivery, raiseForId: report['id'] as String);
      if (!_hasPendingReport(report['id'] as String)) {
        report['deliveryState'] = 'sent';
      }
    }
    return report;
  }

  String _reasonWireValue(ModerationReportReason reason) {
    return switch (reason) {
      ModerationReportReason.spam => 'spam',
      ModerationReportReason.harassment => 'harassment',
      ModerationReportReason.threats => 'threats',
      ModerationReportReason.illegalContent => 'illegal_content',
      ModerationReportReason.other => 'other',
    };
  }

  Future<void> _appendPendingReport(Map<String, dynamic> report) async {
    final reports = _readPendingReports()..add(report);
    await _writePendingReports(reports);
  }

  Future<void> _flushPendingReports(
    Future<void> Function(Map<String, dynamic> report) delivery, {
    required String raiseForId,
  }) async {
    final reports = _readPendingReports();
    Object? raisedError;
    for (final report in reports) {
      final id = report['id']?.toString() ?? '';
      try {
        await delivery(report);
        await _removePendingReport(id);
      } catch (error) {
        report['lastDeliveryError'] = error.toString();
        await _replacePendingReport(report);
        if (id == raiseForId) {
          raisedError = error;
        }
      }
    }
    if (raisedError != null) {
      throw raisedError;
    }
  }

  Future<void> _replacePendingReport(Map<String, dynamic> report) async {
    final id = report['id']?.toString();
    final reports = _readPendingReports();
    final index = reports.indexWhere((item) => item['id']?.toString() == id);
    if (index >= 0) {
      reports[index] = report;
    } else {
      reports.add(report);
    }
    await _writePendingReports(reports);
  }

  Future<void> _removePendingReport(String id) async {
    final reports = _readPendingReports()
      ..removeWhere((item) => item['id']?.toString() == id);
    await _writePendingReports(reports);
  }

  bool _hasPendingReport(String id) {
    return _readPendingReports().any((item) => item['id']?.toString() == id);
  }

  List<Map<String, dynamic>> _readPendingReports() {
    final persistentOutbox = outbox;
    if (persistentOutbox != null) return persistentOutbox.read();
    final raw = settingsBox.get(pendingReportsKey);
    return raw is List
        ? raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: true)
        : <Map<String, dynamic>>[];
  }

  Future<void> _writePendingReports(List<Map<String, dynamic>> reports) {
    return outbox?.write(reports) ??
        settingsBox.put(pendingReportsKey, reports);
  }
}
