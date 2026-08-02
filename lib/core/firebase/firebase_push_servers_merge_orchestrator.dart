import 'dart:async';

import '../runtime/app_file_logger.dart';
import 'firebase_push_payload.dart';
import 'firebase_push_payload_processor.dart';

class FirebasePushServersMergeOrchestrator {
  const FirebasePushServersMergeOrchestrator({
    FirebasePushPayloadProcessor payloadProcessor =
        const FirebasePushPayloadProcessor(),
  }) : _payloadProcessor = payloadProcessor;

  final FirebasePushPayloadProcessor _payloadProcessor;

  Future<void> applyIfPresent(
    Map<String, dynamic> payload, {
    required String source,
    String logName = 'FirebaseMessagingService',
    String logPrefix = '[fcm][servers]',
  }) async {
    final pushPayload = FirebasePushPayload.fromMap(payload);
    final hasServers =
        pushPayload.rawServers != null || pushPayload.rawPriorityServers != null;
    if (!hasServers) {
      return;
    }
    try {
      AppFileLogger.log(
        '$logPrefix apply start source=$source '
        'serversLength=${(pushPayload.rawServers ?? '').toString().length} '
        'priorityServersLength=${(pushPayload.rawPriorityServers ?? '').toString().length}',
        name: logName,
      );
      await _payloadProcessor.mergeServersFromPush(payload);
      AppFileLogger.log(
        '$logPrefix apply done source=$source',
        name: logName,
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '$logPrefix apply failed source=$source error=$error',
        name: logName,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void scheduleIfPresent(
    Map<String, dynamic> payload, {
    required String source,
    String logName = 'FirebaseMessagingService',
    String logPrefix = '[fcm][servers]',
  }) {
    final snapshot = Map<String, dynamic>.from(payload);
    unawaited(
      applyIfPresent(
        snapshot,
        source: source,
        logName: logName,
        logPrefix: logPrefix,
      ),
    );
  }
}
