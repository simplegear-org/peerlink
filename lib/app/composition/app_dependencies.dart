// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/network_dependencies.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/ui/state/app_appearance_controller.dart';
import 'package:peerlink/ui/state/app_locale_controller.dart';

import 'app_ui_dependencies.dart';

class AppBaseDependencies {
  AppBaseDependencies({
    required this.storage,
    required this.appearanceController,
    required this.localeController,
  });

  final StorageService storage;
  final AppAppearanceController appearanceController;
  final AppLocaleController localeController;

  Future<void> dispose() async {
    appearanceController.dispose();
    localeController.dispose();
  }
}

class AppDependencies {
  AppDependencies({
    required this.base,
    required this.network,
    required this.ui,
  });

  final AppBaseDependencies base;
  final NetworkDependencies network;
  final AppUiDependencies ui;

  StorageService get storage => base.storage;
  AppAppearanceController get appearanceController => base.appearanceController;
  AppLocaleController get localeController => base.localeController;
  NodeFacade get nodeFacade => network.nodeFacade;

  Future<void> dispose() async {
    await ui.dispose();
    await base.dispose();
  }
}
