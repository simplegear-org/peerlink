// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'package:peerlink/core/runtime/app_data_cleaner_service.dart';
import 'package:peerlink/core/runtime/app_storage_stats.dart';
import 'settings_server_config_service.dart';

class SettingsStorageMaintenanceService {
  static const Duration _breakdownCacheTtl = Duration(seconds: 30);

  final AppDataCleanerService dataCleaner;
  final SettingsServerConfigService serverConfigService;
  final Future<AppStorageBreakdown> Function() loadStorageBreakdownImpl;
  AppStorageBreakdown? _cachedBreakdown;
  DateTime? _cachedBreakdownAt;
  Future<AppStorageBreakdown>? _breakdownInFlight;

  SettingsStorageMaintenanceService({
    required this.dataCleaner,
    required this.serverConfigService,
    required this.loadStorageBreakdownImpl,
  });

  Future<AppStorageBreakdown> loadStorageBreakdown() {
    final cached = _cachedBreakdown;
    final cachedAt = _cachedBreakdownAt;
    final now = DateTime.now();
    if (cached != null &&
        cachedAt != null &&
        now.difference(cachedAt) < _breakdownCacheTtl) {
      return Future.value(cached);
    }

    final inFlight = _breakdownInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = loadStorageBreakdownImpl();
    _breakdownInFlight = future;
    future
        .then((breakdown) {
          _cachedBreakdown = breakdown;
          _cachedBreakdownAt = DateTime.now();
        }, onError: (_) {})
        .whenComplete(() {
          if (identical(_breakdownInFlight, future)) {
            _breakdownInFlight = null;
          }
        });
    return future;
  }

  Future<void> clearManagedMediaStorage() async {
    await dataCleaner.clearManagedMediaStorage();
    _clearBreakdownCache();
  }

  Future<void> clearMessagesDatabase() async {
    await dataCleaner.clearMessagesDatabase();
    _clearBreakdownCache();
  }

  Future<void> clearSettingsAndServiceData() async {
    await dataCleaner.clearSettingsAndServiceData();
    await serverConfigService.clearSettingsOwnedServerData();
    _clearBreakdownCache();
  }

  void _clearBreakdownCache() {
    _cachedBreakdown = null;
    _cachedBreakdownAt = null;
  }
}
