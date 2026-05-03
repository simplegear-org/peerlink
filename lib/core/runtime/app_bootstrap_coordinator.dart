import 'dart:async';
import 'dart:io' show Platform;

import 'package:background_fetch/background_fetch.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../turn/turn_server_config.dart';
import 'app_file_logger.dart';
import 'contacts_repository.dart';
import 'network_dependencies.dart';
import 'server_health_coordinator.dart';
import 'storage_service.dart';

class AppBootstrapCoordinator {
  final StorageService storage;
  final NetworkDependencies deps;

  AppBootstrapCoordinator({required this.storage, required this.deps});

  Future<void> postBootstrap({
    required Future<void> Function() configureBackgroundFetch,
  }) async {
    await configureBackgroundFetch();
    _autoConfigureBootstrap();
    _autoConfigureRelay();
    _autoConfigureTurn();
    await ServerHealthCoordinator(
      facade: deps.nodeFacade,
      storage: storage,
    ).initialize();
    _disableAutoConnectContacts();
  }

  static Future<void> configureBackgroundFetch({
    required Future<void> Function() onFetch,
    required Future<void> Function(String taskId) onHeadlessTask,
  }) async {
    try {
      final status = await BackgroundFetch.status;
      if (status != BackgroundFetch.STATUS_AVAILABLE) {
        AppFileLogger.log('[background_fetch] unavailable status=$status');
        return;
      }

      await BackgroundFetch.configure(
        BackgroundFetchConfig(
          minimumFetchInterval: 15,
          stopOnTerminate: false,
          enableHeadless: true,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresStorageNotLow: false,
          requiresDeviceIdle: false,
          requiredNetworkType: NetworkType.ANY,
        ),
        (String taskId) async {
          AppFileLogger.log('[background_fetch] onFetch task=$taskId');
          try {
            await onFetch();
          } catch (e) {
            AppFileLogger.log('[background_fetch] onFetch pollRelay error=$e');
          }
          BackgroundFetch.finish(taskId);
        },
        (String taskId) async {
          AppFileLogger.log('[background_fetch] timeout task=$taskId');
          BackgroundFetch.finish(taskId);
        },
      );

      if (!kIsWeb && Platform.isAndroid) {
        BackgroundFetch.registerHeadlessTask(onHeadlessTask);
      }
    } on PlatformException catch (error, stackTrace) {
      AppFileLogger.log(
        '[background_fetch] configure skipped error=$error',
        stackTrace: stackTrace,
      );
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '[background_fetch] unexpected configure error=$error',
        stackTrace: stackTrace,
      );
    }
  }

  void _autoConfigureBootstrap() {
    final raw = storage.getSettings().get('bootstrap_servers');
    if (raw is! List) {
      return;
    }
    final endpoints = raw.whereType<String>().toList();
    if (endpoints.isEmpty) {
      return;
    }
    unawaited(deps.nodeFacade.configureBootstrapServers(endpoints));
  }

  void _autoConfigureRelay() {
    final raw = storage.getSettings().get('relay_servers');
    if (raw is! List) {
      unawaited(deps.nodeFacade.configureRelayServers(const <String>[]));
      return;
    }
    final endpoints = raw.whereType<String>().toList();
    if (endpoints.isEmpty) {
      unawaited(deps.nodeFacade.configureRelayServers(const <String>[]));
      return;
    }
    unawaited(deps.nodeFacade.configureRelayServers(endpoints));
  }

  void _autoConfigureTurn() {
    final raw = storage.getSettings().get('turn_servers');
    if (raw is! List) {
      return;
    }

    final servers = raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .map(TurnServerConfig.fromJson)
        .where((entry) => entry.url.trim().isNotEmpty)
        .toList(growable: false);

    if (servers.isEmpty) {
      return;
    }

    unawaited(deps.nodeFacade.configureTurnServers(servers));
  }

  void _disableAutoConnectContacts() {
    final contactCount = ContactsRepository(storage: storage).count();
    AppFileLogger.log(
      '[main] autoConnectContacts disabled contacts=$contactCount',
    );
  }
}
