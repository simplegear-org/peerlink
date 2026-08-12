import 'dart:async';

import 'reliable_pending_operation_store.dart';

typedef ReliableRetryOperation =
    Future<bool> Function(ReliablePendingOperation operation);

class ReliableRetryScheduler {
  static const int defaultMaxOperationsPerTick = 16;
  static const int defaultMaxAttempts = 3;

  final bool Function() _isDisposed;
  final bool Function() _isRelayEnabled;
  final bool Function() _hasPendingOperations;
  final List<ReliablePendingOperation> Function() _pendingOperations;
  final Future<void> Function(String operationId) _removeOperation;
  final Future<void> Function() _persistOperations;
  final ReliableRetryOperation _retryOperation;
  final void Function(ReliablePendingOperation operation, Object error)
  _onError;
  final void Function(ReliablePendingOperation operation) _onGiveUp;
  final void Function(String message) _log;
  final int _maxOperationsPerTick;
  final int _maxAttempts;
  Timer? _timer;
  bool _retryInProgress = false;

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
    required void Function(ReliablePendingOperation operation) onGiveUp,
    required void Function(String message) log,
    int maxOperationsPerTick = defaultMaxOperationsPerTick,
    int maxAttempts = defaultMaxAttempts,
  }) : _isDisposed = isDisposed,
       _isRelayEnabled = isRelayEnabled,
       _hasPendingOperations = hasPendingOperations,
       _pendingOperations = pendingOperations,
       _removeOperation = removeOperation,
       _persistOperations = persistOperations,
       _retryOperation = retryOperation,
       _onError = onError,
       _onGiveUp = onGiveUp,
       _log = log,
       _maxOperationsPerTick = maxOperationsPerTick,
       _maxAttempts = maxAttempts;

  void schedule() {
    if (_isDisposed()) {
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(retryDueOperations());
    });
  }

  Future<void> retryDueOperations() async {
    if (_retryInProgress) {
      _log('pending:retry skipped reason=in-progress');
      return;
    }
    if (_isDisposed() || !_isRelayEnabled() || !_hasPendingOperations()) {
      if (!_hasPendingOperations()) {
        cancel();
      }
      return;
    }

    _retryInProgress = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final operations = _pendingOperations()
        ..sort((a, b) => a.nextAttemptMs.compareTo(b.nextAttemptMs));
      final dueCount = operations
          .where((operation) => operation.nextAttemptMs <= nowMs)
          .length;
      final capped = dueCount > _maxOperationsPerTick;
      _log(
        'pending:retry tick total=${operations.length} due=$dueCount '
        'max=$_maxOperationsPerTick capped=$capped '
        'relayEnabled=${_isRelayEnabled()}',
      );

      var processed = 0;
      for (final operation in operations) {
        if (operation.nextAttemptMs > nowMs) {
          continue;
        }
        if (processed >= _maxOperationsPerTick) {
          break;
        }
        processed += 1;
        _log('pending:retry due ${operation.diagnosticsSummary(nowMs: nowMs)}');
        if (operation.attempts >= _maxAttempts) {
          await _giveUp(operation, reason: 'max-attempts-before-send');
          continue;
        }
        try {
          final sent = await _retryOperation(operation);
          if (sent) {
            _log(
              'pending:retry sent ${operation.diagnosticsSummary(nowMs: nowMs)}',
            );
            await _removeOperation(operation.operationId);
            continue;
          }
          operation.registerFailure();
          if (operation.attempts >= _maxAttempts) {
            await _giveUp(operation, reason: 'max-attempts');
            continue;
          }
          _log('pending:retry deferred ${operation.diagnosticsSummary()}');
          await _persistOperations();
        } catch (error) {
          operation.registerFailure();
          if (operation.attempts >= _maxAttempts) {
            await _giveUp(operation, reason: 'max-attempts', error: error);
            continue;
          }
          _log(
            'pending:retry exception ${operation.diagnosticsSummary()} '
            'error=$error',
          );
          await _persistOperations();
          _onError(operation, error);
        }
      }

      if (!_hasPendingOperations()) {
        cancel();
      }
    } finally {
      _retryInProgress = false;
    }
  }

  Future<void> _giveUp(
    ReliablePendingOperation operation, {
    required String reason,
    Object? error,
  }) async {
    _log(
      'pending:retry giveup reason=$reason '
      '${operation.diagnosticsSummary()}'
      '${error == null ? "" : " error=$error"}',
    );
    await _removeOperation(operation.operationId);
    _onGiveUp(operation);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
