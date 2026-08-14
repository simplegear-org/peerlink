// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

class CallRenegotiationOrchestrator {
  CallRenegotiationOrchestrator({
    required void Function(String message) log,
    required Future<void> Function(String reason) runRenegotiation,
  }) : _log = log,
       _runRenegotiation = runRenegotiation;

  final void Function(String message) _log;
  final Future<void> Function(String reason) _runRenegotiation;

  bool _inProgress = false;
  String? _pendingReason;

  bool get inProgress => _inProgress;

  void setInProgress(bool value) {
    _inProgress = value;
  }

  void setPendingReason(String? value) {
    _pendingReason = value;
  }

  void reset() {
    _inProgress = false;
    _pendingReason = null;
  }

  Future<void> run(String reason) async {
    if (_inProgress) {
      _pendingReason = reason;
      _log('renegotiation:queued already-in-progress reason="$reason"');
      return;
    }
    _inProgress = true;
    try {
      await _runRenegotiation(reason);
    } finally {
      _inProgress = false;
    }
    final pendingReason = _pendingReason;
    if (pendingReason != null) {
      _pendingReason = null;
      await run(pendingReason);
    }
  }
}
