import 'dart:async';

import 'reliable_pending_operation_store.dart';

typedef ReliableRetryOperation =
    Future<bool> Function(ReliablePendingOperation operation);

class ReliableRetryScheduler {
  final bool Function() _isDisposed;
  final bool Function() _isRelayEnabled;
  final bool Function() _hasPendingOperations;
  final List<ReliablePendingOperation> Function() _pendingOperations;
  final Future<void> Function(String operationId) _removeOperation;
  final Future<void> Function() _persistOperations;
  final ReliableRetryOperation _retryOperation;
  final void Function(ReliablePendingOperation operation, Object error)
  _onError;
  Timer? _timer;

  ReliableRetryScheduler({
    required bool Function() isDisposed,
    required bool Function() isRelayEnabled,
    required bool Function() hasPendingOperations,
    required List<ReliablePendingOperation> Function() pendingOperations,
    required Future<void> Function(String operationId) removeOperation,
    required Future<void> Function() persistOperations,
    required ReliableRetryOperation retryOperation,
    required void Function(ReliablePendingOperation operation, Object error)
    onError,
  }) : _isDisposed = isDisposed,
       _isRelayEnabled = isRelayEnabled,
       _hasPendingOperations = hasPendingOperations,
       _pendingOperations = pendingOperations,
       _removeOperation = removeOperation,
       _persistOperations = persistOperations,
       _retryOperation = retryOperation,
       _onError = onError;

  void schedule() {
    if (_isDisposed()) {
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(retryDueOperations());
    });
  }

  Future<void> retryDueOperations() async {
    if (_isDisposed() || !_isRelayEnabled() || !_hasPendingOperations()) {
      if (!_hasPendingOperations()) {
        cancel();
      }
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final operations = _pendingOperations()
      ..sort((a, b) => a.nextAttemptMs.compareTo(b.nextAttemptMs));

    for (final operation in operations) {
      if (operation.nextAttemptMs > nowMs) {
        continue;
      }
      try {
        final sent = await _retryOperation(operation);
        if (sent) {
          await _removeOperation(operation.operationId);
          continue;
        }
        operation.registerFailure();
        await _persistOperations();
      } catch (error) {
        operation.registerFailure();
        await _persistOperations();
        _onError(operation, error);
      }
    }

    if (!_hasPendingOperations()) {
      cancel();
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
