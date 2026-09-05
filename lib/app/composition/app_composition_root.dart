// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:peerlink/core/notification/app_badge_service.dart';
import 'package:peerlink/core/notification/notification_service.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:peerlink/core/runtime/network_dependencies.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/ui/state/app_appearance_controller.dart';
import 'package:peerlink/ui/state/app_locale_controller.dart';

import 'app_dependencies.dart';
import 'app_ui_dependencies.dart';

typedef StorageServiceFactory = StorageService Function();
typedef NetworkDependenciesFactory =
    Future<NetworkDependencies> Function({required StorageService storage});

class AppCompositionRoot {
  AppCompositionRoot({
    StorageServiceFactory? storageFactory,
    NetworkDependenciesFactory? networkFactory,
  }) : _storageFactory = storageFactory ?? (() => StorageService()),
       _networkFactory =
           networkFactory ??
           (({required storage}) =>
               NetworkDependencies.create(storage: storage));

  final StorageServiceFactory _storageFactory;
  final NetworkDependenciesFactory _networkFactory;

  Future<AppBaseDependencies> createBaseDependencies() async {
    AppFileLogger.log('[composition] creating StorageService');
    final storage = _storageFactory();
    AppFileLogger.log('[composition] initializing StorageService');
    await storage.init();
    NotificationService.instance.configureStorage(storage);
    await AppFileLogger.configureFromStorage(storage);
    await AppBadgeService(storage: storage).syncFromStorage();
    AppFileLogger.log('[composition] StorageService initialized');

    final appearanceController = AppAppearanceController(storage: storage);
    await appearanceController.initialize();
    final localeController = AppLocaleController(storage: storage);
    await localeController.initialize();

    return AppBaseDependencies(
      storage: storage,
      appearanceController: appearanceController,
      localeController: localeController,
    );
  }

  Future<AppDependencies> createRuntimeDependencies({
    required AppBaseDependencies base,
    Duration? timeout,
  }) async {
    AppFileLogger.log('[composition] creating NetworkDependencies');
    final networkFuture = _networkFactory(storage: base.storage);
    final network = timeout == null
        ? await networkFuture
        : await networkFuture.timeout(
            timeout,
            onTimeout: () {
              throw TimeoutException(
                'NetworkDependencies.create timed out after '
                '${timeout.inSeconds}s',
              );
            },
          );
    AppFileLogger.log('[composition] NetworkDependencies created');
    final ui = AppUiDependencies.create(
      facade: network.nodeFacade,
      storage: base.storage,
    );

    return AppDependencies(base: base, network: network, ui: ui);
  }

  Future<AppDependencies> create({Duration? networkTimeout}) async {
    final base = await createBaseDependencies();
    return createRuntimeDependencies(base: base, timeout: networkTimeout);
  }
}
