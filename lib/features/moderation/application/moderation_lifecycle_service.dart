// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'moderation_reports_api.dart';

class ModerationLifecycleService {
  ModerationLifecycleService({
    required ModerationReportsApi reports,
    Stream<List<ConnectivityResult>>? connectivityChanges,
    required void Function(String message) log,
  }) : _reports = reports,
       _connectivityChanges =
           connectivityChanges ?? Connectivity().onConnectivityChanged,
       _log = log;

  final ModerationReportsApi _reports;
  final Stream<List<ConnectivityResult>> _connectivityChanges;
  final void Function(String message) _log;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  void start() {
    unawaited(_retryPendingReports(reason: 'startup'));
    _connectivitySubscription = _connectivityChanges.listen((results) {
      if (_hasNetworkConnectivity(results)) {
        unawaited(_retryPendingReports(reason: 'connectivity'));
      }
    });
  }

  void handleAppResumed() {
    unawaited(_retryPendingReports(reason: 'resume'));
  }

  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
  }

  Future<void> _retryPendingReports({required String reason}) async {
    try {
      await _reports.retryPendingReports();
    } catch (error) {
      _log('moderation retry deferred reason=$reason error=$error');
    }
  }

  bool _hasNetworkConnectivity(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.mobile ||
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet ||
          result == ConnectivityResult.vpn ||
          result == ConnectivityResult.other,
    );
  }
}
