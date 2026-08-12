import 'dart:async';

import 'app_file_logger.dart';
import 'server_update_callback_registry.dart';
import 'server_update_parser.dart';
import 'server_update_storage_merger.dart';
import 'push_server_sharing_preferences.dart';
import 'storage_service.dart';

class RuntimeServersMergeOrchestrator {
  const RuntimeServersMergeOrchestrator({
    ServerUpdateParser serverUpdateParser = const ServerUpdateParser(),
    ServerUpdateStorageMerger serverStorageMerger =
        const ServerUpdateStorageMerger(),
  }) : _serverUpdateParser = serverUpdateParser,
       _serverStorageMerger = serverStorageMerger;

  final ServerUpdateParser _serverUpdateParser;
  final ServerUpdateStorageMerger _serverStorageMerger;

  bool hasServerUpdate(Map<String, dynamic> payload) {
    final update = _serverUpdateParser.parse(payload);
    return update != null && !update.isEmpty;
  }

  Future<void> applyIfPresent(
    Map<String, dynamic> payload, {
    required String source,
    String logName = 'servers',
    String logPrefix = '[servers]',
  }) async {
    final update = _serverUpdateParser.parse(payload);
    if (update == null || update.isEmpty) {
      return;
    }
    try {
      AppFileLogger.log(
        '$logPrefix apply start source=$source '
        'bootstrap=${update.bootstrap.length} relay=${update.relay.length} '
        'push=${update.push.length} turn=${update.turn.length} '
        'priorityBootstrap=${update.priorityBootstrap.length} '
        'priorityRelay=${update.priorityRelay.length} '
        'priorityPush=${update.priorityPush.length} '
        'priorityTurn=${update.priorityTurn.length}',
        name: logName,
      );
      final storage = StorageService();
      final settings = storage.getSettings();
      if (!PushServerSharingPreferences.receiveIncomingServers(settings)) {
        AppFileLogger.log(
          '$logPrefix apply skipped source=$source reason=disabled',
          name: logName,
        );
        return;
      }
      final mergeResult = await _serverStorageMerger.merge(
        settings: settings,
        update: update,
      );
      AppFileLogger.log(
        '$logPrefix storage merged source=$source '
        'bootstrapChanged=${mergeResult.bootstrapChanged} '
        'relayChanged=${mergeResult.relayChanged} '
        'pushChanged=${mergeResult.pushChanged} '
        'turnChanged=${mergeResult.turnChanged}',
        name: logName,
      );
      final callback = ServerUpdateCallbackRegistry.onServersUpdate;
      if (callback == null) {
        AppFileLogger.log(
          '$logPrefix apply callback missing source=$source',
          name: logName,
        );
        return;
      }
      AppFileLogger.log(
        '$logPrefix apply callback start source=$source',
        name: logName,
      );
      final future = callback(update);
      ServerUpdateCallbackRegistry.trackPendingServersApply(future);
      await future;
      AppFileLogger.log(
        '$logPrefix apply callback done source=$source',
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
    String logName = 'servers',
    String logPrefix = '[servers]',
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
