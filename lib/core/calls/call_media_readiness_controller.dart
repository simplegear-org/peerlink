import 'dart:async';

import 'audio_call_peer.dart';
import 'call_media_readiness_helper.dart';
import 'call_media_timeout_helper.dart';
import 'call_models.dart';
import 'call_recovery_coordinator.dart';
import 'call_recovery_state_helper.dart';

class CallMediaReadinessController {
  CallMediaReadinessController({
    required CallState Function() getState,
    required int Function() getCurrentEpoch,
    required AudioCallPeer? Function() getPeer,
    required bool Function(String peerId, String callId) matchesCurrentCall,
    required void Function(CallState state) emit,
    required void Function(String message) log,
  }) : _getState = getState,
       _getCurrentEpoch = getCurrentEpoch,
       _getPeer = getPeer,
       _matchesCurrentCall = matchesCurrentCall,
       _emit = emit,
       _log = log;

  static const CallRecoveryStateHelper _recoveryStateHelper =
      CallRecoveryStateHelper();
  static const CallMediaReadinessHelper _mediaReadinessHelper =
      CallMediaReadinessHelper();
  static const CallMediaTimeoutHelper _mediaTimeoutHelper =
      CallMediaTimeoutHelper();

  final CallState Function() _getState;
  final int Function() _getCurrentEpoch;
  final AudioCallPeer? Function() _getPeer;
  final bool Function(String peerId, String callId) _matchesCurrentCall;
  final void Function(CallState state) _emit;
  final void Function(String message) _log;

  Timer? _mediaReadyTimeout;
  bool _localMediaReady = false;
  bool _remoteMediaReady = false;
  int _mediaRecoveryAttempt = 0;

  void markLocalMediaReady() {
    _localMediaReady = true;
  }

  void markRemoteMediaReady() {
    _remoteMediaReady = true;
  }

  void markRemoteMediaTimeoutHandled() {
    clearMediaReadyTimeout();
  }

  void clearMediaReadyTimeout() {
    _mediaReadyTimeout?.cancel();
    _mediaReadyTimeout = null;
  }

  void resetRuntimeTracking() {
    _localMediaReady = false;
    _remoteMediaReady = false;
    _mediaRecoveryAttempt = 0;
    clearMediaReadyTimeout();
  }

  void handleIceRecoveryState({
    required bool recovering,
    required String status,
  }) {
    if (_getState().isIdle) {
      return;
    }
    if (recovering) {
      beginRecovery(kind: CallRecoveryKind.ice, status: status);
      return;
    }
    completeRecovery(status: status);
  }

  void beginRecovery({required CallRecoveryKind kind, required String status}) {
    final state = _getState();
    if (state.isIdle) {
      return;
    }
    _emit(
      _recoveryStateHelper.startRecovery(
        currentState: state,
        kind: kind,
        status: status,
      ),
    );
  }

  void completeRecovery({required String status}) {
    final state = _getState();
    if (!state.isRecovering && state.recoveryKind == null) {
      return;
    }
    _emit(
      _recoveryStateHelper.completeRecovery(
        currentState: state,
        status: status,
      ),
    );
    updateActiveState();
  }

  void updateActiveState() {
    final state = _getState();
    if (state.isIdle) {
      return;
    }
    final nextState = _mediaReadinessHelper.buildReadinessState(
      currentState: state,
      localMediaReady: _localMediaReady,
      remoteMediaReady: _remoteMediaReady,
      now: DateTime.now(),
    );
    if (nextState.phase == CallPhase.active) {
      final clearIceRecovery = state.recoveryKind == CallRecoveryKind.ice;
      if (state.phase != CallPhase.active || clearIceRecovery) {
        clearMediaReadyTimeout();
        _emit(
          clearIceRecovery
              ? nextState.copyWith(
                  recoveryAttempt: 0,
                  clearRecoveryKind: true,
                  clearRecoveryReturnPhase: true,
                )
              : nextState,
        );
      }
      return;
    }
    _emit(nextState);
  }

  void armMediaReadyTimeout() {
    final state = _getState();
    if (state.isIdle) {
      return;
    }
    if (_mediaReadyTimeout?.isActive ?? false) {
      return;
    }
    final expectedPeer = _getPeer();
    final expectedPeerId = state.peerId;
    final expectedCallId = state.callId;
    if (expectedPeerId == null || expectedCallId == null) {
      return;
    }
    final expectedEpoch = _getCurrentEpoch();
    _mediaReadyTimeout = _mediaTimeoutHelper.armMediaReadyTimeout(
      timeout: const Duration(seconds: 6),
      getState: _getState,
      getLocalMediaReady: () => _localMediaReady,
      getRemoteMediaReady: () => _remoteMediaReady,
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: _getCurrentEpoch,
      expectedPeer: expectedPeer,
      expectedPeerId: expectedPeerId,
      expectedCallId: expectedCallId,
      matchesCurrentCall: _matchesCurrentCall,
      getPeer: _getPeer,
      getMediaRecoveryAttempt: () => _mediaRecoveryAttempt,
      setMediaRecoveryAttempt: (value) => _mediaRecoveryAttempt = value,
      onMediaReadyTimeout: _handleMediaReadyTimeout,
      log: _log,
      rearmMediaReadyTimeout: armMediaReadyTimeout,
    );
  }

  Future<CallRecoveryDisposition> _handleMediaReadyTimeout({
    required int attempt,
    required bool localMediaReady,
    required bool remoteMediaReady,
  }) async {
    final peer = _getPeer();
    if (peer == null) {
      return CallRecoveryDisposition.none;
    }
    return peer.observeRecovery(
      CallRecoveryObservation(
        kind: CallRecoveryObservationKind.mediaReadyTimeout,
        reason: 'Remote media confirmation timeout',
        attempt: attempt,
        localMediaReady: localMediaReady,
        remoteMediaReady: remoteMediaReady,
      ),
    );
  }
}
