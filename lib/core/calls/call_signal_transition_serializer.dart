// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

class CallSignalTransitionSerializer {
  CallSignalTransitionSerializer({
    required void Function(String message) log,
    String logPrefix = 'signal-orchestration',
    void Function()? onAfterTransition,
  }) : _log = log,
       _logPrefix = logPrefix,
       _onAfterTransition = onAfterTransition;

  final void Function(String message) _log;
  final String _logPrefix;
  final void Function()? _onAfterTransition;
  Future<void> _queue = Future<void>.value();

  Future<void> serialize({
    required String label,
    required Future<void> Function() action,
    bool Function()? shouldRun,
  }) async {
    final completer = Completer<void>();
    final previous = _queue;
    _queue = completer.future;
    try {
      await previous;
      if (shouldRun != null && !shouldRun()) {
        _log('$_logPrefix:skip label=$label');
        return;
      }
      _log('$_logPrefix:start label=$label');
      await action();
    } finally {
      _log('$_logPrefix:done label=$label');
      if (!completer.isCompleted) {
        completer.complete();
      }
      _onAfterTransition?.call();
    }
  }
}
