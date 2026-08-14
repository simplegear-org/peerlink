// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'app_file_logger.dart';
import 'server_update.dart';

class ServerUpdateCallbackRegistry {
  static Future<void> Function(ServerUpdate update)? onServersUpdate;
  static Future<void>? _pendingServersApplyFuture;

  static void trackPendingServersApply(Future<void> future) {
    _pendingServersApplyFuture = future;
    future.whenComplete(() {
      if (identical(_pendingServersApplyFuture, future)) {
        _pendingServersApplyFuture = null;
      }
    });
  }

  static Future<void> waitForPendingServersApply({
    Duration timeout = const Duration(seconds: 5),
    String logName = 'servers',
    String logPrefix = '[servers]',
  }) async {
    final pending = _pendingServersApplyFuture;
    if (pending == null) {
      return;
    }
    try {
      await pending.timeout(timeout);
    } catch (error, stackTrace) {
      AppFileLogger.log(
        '$logPrefix wait pending servers apply failed error=$error',
        name: logName,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
