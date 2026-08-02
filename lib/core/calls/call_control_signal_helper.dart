import 'dart:async';

import '../signaling/signaling_service.dart';

class CallControlSignalHelper {
  CallControlSignalHelper({
    required this.signaling,
    required this.emitWaitingState,
    required this.log,
    required this.logError,
  });

  final SignalingService signaling;
  final void Function() emitWaitingState;
  final void Function(String message) log;
  final void Function(String message, {Object? error, StackTrace? stackTrace})
  logError;

  void ensureOutgoingSignalingReady(String purpose) {
    final status = signaling.connectionStatus;
    if (status == SignalingConnectionStatus.connected) {
      return;
    }
    log('waitForSignaling:deny purpose=$purpose status=$status');
    throw StateError('Сигналинг еще не готов. Попробуйте через пару секунд.');
  }

  Future<void> waitForSignalingReady(String purpose) async {
    if (signaling.connectionStatus == SignalingConnectionStatus.connected) {
      return;
    }

    log(
      'waitForSignaling:start purpose=$purpose status=${signaling.connectionStatus}',
    );
    emitWaitingState();

    final completer = Completer<void>();
    late final StreamSubscription<SignalingConnectionStatus> subscription;
    subscription = signaling.connectionStatusStream.listen((status) {
      if (status == SignalingConnectionStatus.connected &&
          !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      await completer.future.timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw StateError('Signaling не восстановился вовремя: $purpose');
    } finally {
      await subscription.cancel();
    }
  }

  void sendDetached(
    String peerId,
    String type,
    Map<String, dynamic> data, {
    required String purpose,
  }) {
    unawaited(sendBestEffort(peerId, type, data, purpose: purpose));
  }

  Future<void> sendBestEffort(
    String peerId,
    String type,
    Map<String, dynamic> data, {
    required String purpose,
  }) async {
    try {
      await waitForSignalingReady(purpose);
      await signaling.sendSignal(peerId, type, data);
    } catch (error, stackTrace) {
      log('controlSignal:skip type=$type purpose=$purpose error=$error');
      logError(
        'controlSignal:skip type=$type purpose=$purpose error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
