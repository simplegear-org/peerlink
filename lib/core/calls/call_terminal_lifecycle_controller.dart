import 'audio_call_peer.dart';
import 'call_lifecycle_reset_helper.dart';
import 'call_models.dart';
import 'call_peer_lifecycle_helper.dart';

class CallTerminalLifecycleController {
  CallTerminalLifecycleController({
    required CallState Function() getState,
    required int Function() getCurrentEpoch,
    required AudioCallPeer? Function() getPeer,
    required void Function(AudioCallPeer? peer) setPeer,
    required void Function(CallState state) emit,
    required void Function(String message) log,
    required void Function() cancelOutgoingTimeout,
    required void Function() cancelConnectAttemptTimeout,
    required void Function() clearMediaReadyTimeout,
    required void Function() resetRuntimeTracking,
    required void Function({
      required CallRecoveryKind kind,
      required String status,
    })
    beginRecovery,
    required CallLifecycleSignalSender sendDetachedSignal,
  }) : _getState = getState,
       _getCurrentEpoch = getCurrentEpoch,
       _getPeer = getPeer,
       _setPeer = setPeer,
       _emit = emit,
       _log = log,
       _cancelOutgoingTimeout = cancelOutgoingTimeout,
       _cancelConnectAttemptTimeout = cancelConnectAttemptTimeout,
       _clearMediaReadyTimeout = clearMediaReadyTimeout,
       _resetRuntimeTracking = resetRuntimeTracking,
       _beginRecovery = beginRecovery,
       _sendDetachedSignal = sendDetachedSignal;

  static const CallLifecycleResetHelper _lifecycleResetHelper =
      CallLifecycleResetHelper();
  static const CallPeerLifecycleHelper _peerLifecycleHelper =
      CallPeerLifecycleHelper();

  final CallState Function() _getState;
  final int Function() _getCurrentEpoch;
  final AudioCallPeer? Function() _getPeer;
  final void Function(AudioCallPeer? peer) _setPeer;
  final void Function(CallState state) _emit;
  final void Function(String message) _log;
  final void Function() _cancelOutgoingTimeout;
  final void Function() _cancelConnectAttemptTimeout;
  final void Function() _clearMediaReadyTimeout;
  final void Function() _resetRuntimeTracking;
  final void Function({required CallRecoveryKind kind, required String status})
  _beginRecovery;
  final CallLifecycleSignalSender _sendDetachedSignal;

  bool _terminalTransitionInFlight = false;

  void resetRuntimeTracking() {
    _terminalTransitionInFlight = false;
  }

  Future<void> handlePeerError(String error) async {
    final state = _getState();
    if (state.isIdle) {
      return;
    }
    if (error.startsWith('ICE connection')) {
      final iceAttempts = state.recoveryKind == CallRecoveryKind.ice
          ? state.recoveryAttempt
          : 0;
      if (iceAttempts < 2) {
        _beginRecovery(
          kind: CallRecoveryKind.ice,
          status: 'Восстанавливаем соединение: $error',
        );
        return;
      }
    }
    await failAndReset(error);
  }

  Future<void> failAndReset(String error) async {
    final state = _getState();
    if (state.isIdle) {
      _log('terminal:skip fail reason=idle error=$error');
      return;
    }
    if (_terminalTransitionInFlight) {
      _log('terminal:skip fail reason=in_flight error=$error');
      return;
    }
    _terminalTransitionInFlight = true;
    final expectedEpoch = _getCurrentEpoch();
    await _getPeer()?.releaseLocalMediaForTeardown();
    _emitTerminalMediaReleasedState();
    await _lifecycleResetHelper
        .failAndReset(
          currentState: _getState(),
          error: error,
          expectedEpoch: expectedEpoch,
          getCurrentEpoch: _getCurrentEpoch,
          emit: _emit,
          resetToIdle: resetToIdle,
          sendDetachedSignal: _sendDetachedSignal,
        )
        .whenComplete(() {
          _terminalTransitionInFlight = false;
        });
  }

  Future<void> endAndReset(String status) async {
    final state = _getState();
    if (state.isIdle) {
      _log('terminal:skip end reason=idle status=$status');
      return;
    }
    if (_terminalTransitionInFlight) {
      _log('terminal:skip end reason=in_flight status=$status');
      return;
    }
    _terminalTransitionInFlight = true;
    final expectedEpoch = _getCurrentEpoch();
    await _getPeer()?.releaseLocalMediaForTeardown();
    _emitTerminalMediaReleasedState();
    await _lifecycleResetHelper
        .endAndReset(
          currentState: _getState(),
          status: status,
          expectedEpoch: expectedEpoch,
          getCurrentEpoch: _getCurrentEpoch,
          emit: _emit,
          resetToIdle: resetToIdle,
        )
        .whenComplete(() {
          _terminalTransitionInFlight = false;
        });
  }

  Future<void> resetToIdle() async {
    await _peerLifecycleHelper.resetToIdle(
      cancelOutgoingTimeout: _cancelOutgoingTimeout,
      cancelConnectAttemptTimeout: _cancelConnectAttemptTimeout,
      clearMediaReadyTimeout: _clearMediaReadyTimeout,
      resetRuntimeTracking: _resetRuntimeTracking,
      disposePeer: () async {
        await _getPeer()?.dispose();
      },
      setPeer: _setPeer,
      emit: _emit,
    );
  }

  void _emitTerminalMediaReleasedState() {
    final state = _getState();
    if (state.isIdle) {
      return;
    }
    _emit(
      state.copyWith(
        localVideoEnabled: false,
        localVideoAvailable: false,
        remoteVideoEnabled: false,
        remoteVideoAvailable: false,
        remoteVideoActive: false,
        clearRemoteVideoTrackId: true,
        clearLocalStream: true,
        clearRemoteStream: true,
      ),
    );
  }
}
