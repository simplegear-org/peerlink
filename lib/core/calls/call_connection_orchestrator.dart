import 'dart:async';

import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import 'audio_call_peer.dart';
import 'call_connect_orchestration_helper.dart';
import 'call_models.dart';
import 'call_network_policy_helper.dart';

class CallConnectionOrchestrator {
  CallConnectionOrchestrator({
    required CallNetworkPolicyHelper networkPolicyHelper,
    required TurnAllocator? turnAllocator,
    required Future<AudioCallPeer?> Function({
      required String peerId,
      required String callId,
    })
    ensurePeer,
    required bool Function(String peerId, String callId) matchesCurrentCall,
    required void Function(CallState state) emit,
    required CallState Function() getState,
    required int Function() getCurrentEpoch,
    required CallMediaType Function() getActiveMediaType,
    required void Function(String message) log,
    required Future<void> Function(String error) failAndReset,
    required void Function() clearMediaReadyTimeout,
    required void Function() resetMediaRuntimeTracking,
    required Future<void> Function() disposePeer,
    required void Function(AudioCallPeer? peer) setPeer,
    CallConnectOrchestrationHelper helper =
        const CallConnectOrchestrationHelper(),
  }) : _networkPolicyHelper = networkPolicyHelper,
       _turnAllocator = turnAllocator,
       _ensurePeer = ensurePeer,
       _matchesCurrentCall = matchesCurrentCall,
       _emit = emit,
       _getState = getState,
       _getCurrentEpoch = getCurrentEpoch,
       _getActiveMediaType = getActiveMediaType,
       _log = log,
       _failAndReset = failAndReset,
       _clearMediaReadyTimeout = clearMediaReadyTimeout,
       _resetMediaRuntimeTracking = resetMediaRuntimeTracking,
       _disposePeer = disposePeer,
       _setPeer = setPeer,
       _helper = helper;

  final CallNetworkPolicyHelper _networkPolicyHelper;
  final TurnAllocator? _turnAllocator;
  final Future<AudioCallPeer?> Function({
    required String peerId,
    required String callId,
  })
  _ensurePeer;
  final bool Function(String peerId, String callId) _matchesCurrentCall;
  final void Function(CallState state) _emit;
  final CallState Function() _getState;
  final int Function() _getCurrentEpoch;
  final CallMediaType Function() _getActiveMediaType;
  final void Function(String message) _log;
  final Future<void> Function(String error) _failAndReset;
  final void Function() _clearMediaReadyTimeout;
  final void Function() _resetMediaRuntimeTracking;
  final Future<void> Function() _disposePeer;
  final void Function(AudioCallPeer? peer) _setPeer;
  final CallConnectOrchestrationHelper _helper;

  Timer? _connectAttemptTimeout;
  bool _turnFallbackAttempted = false;

  bool get turnFallbackAttempted => _turnFallbackAttempted;

  Future<TransportMode> preferredInitialMode() {
    return _networkPolicyHelper.preferredInitialMode(log: _log);
  }

  Future<void> startPeerConnection({
    required String peerId,
    required String callId,
    required TransportMode initialMode,
  }) {
    return _helper.startPeerConnection(
      peerId: peerId,
      callId: callId,
      initialMode: initialMode,
      ensurePeer: _ensurePeer,
      matchesCurrentCall: _matchesCurrentCall,
      emit: _emit,
      getState: _getState,
      transportLabelFor: _networkPolicyHelper.transportLabelFor,
      getActiveMediaType: _getActiveMediaType,
      log: _log,
      retryViaTurn: retryViaTurn,
      failAndReset: _failAndReset,
      armConnectAttemptTimeout: _armConnectAttemptTimeout,
    );
  }

  void cancelConnectAttemptTimeout() {
    _connectAttemptTimeout?.cancel();
    _connectAttemptTimeout = null;
  }

  void resetRuntimeTracking() {
    _turnFallbackAttempted = false;
  }

  void dispose() {
    cancelConnectAttemptTimeout();
  }

  void _armConnectAttemptTimeout({
    required String peerId,
    required String callId,
    required TransportMode mode,
  }) {
    cancelConnectAttemptTimeout();
    _connectAttemptTimeout = _helper.armConnectAttemptTimeout(
      timeout: _networkPolicyHelper.timeoutForMode(mode),
      peerId: peerId,
      callId: callId,
      mode: mode,
      expectedEpoch: _getCurrentEpoch(),
      getState: _getState,
      getCurrentEpoch: _getCurrentEpoch,
      getTurnFallbackAttempted: () => _turnFallbackAttempted,
      hasTurnAvailableNow: () => _turnAllocator?.allocate() != null,
      log: _log,
      retryViaTurn: retryViaTurn,
      failAndReset: _failAndReset,
    );
  }

  Future<void> retryViaTurn({
    required String peerId,
    required String callId,
    required String reason,
  }) {
    return _helper.retryViaTurn(
      peerId: peerId,
      callId: callId,
      reason: reason,
      getTurnFallbackAttempted: () => _turnFallbackAttempted,
      setTurnFallbackAttempted: (value) => _turnFallbackAttempted = value,
      cancelConnectAttemptTimeout: cancelConnectAttemptTimeout,
      clearMediaReadyTimeout: _clearMediaReadyTimeout,
      resetMediaRuntimeTracking: _resetMediaRuntimeTracking,
      hasTurnAvailable: _hasTurnAvailable,
      emit: _emit,
      getState: _getState,
      failAndReset: _failAndReset,
      log: _log,
      disposePeer: _disposePeer,
      setPeer: _setPeer,
      ensurePeer: _ensurePeer,
      matchesCurrentCall: _matchesCurrentCall,
      getActiveMediaType: _getActiveMediaType,
      armConnectAttemptTimeout: _armConnectAttemptTimeout,
    );
  }

  Future<bool> _hasTurnAvailable() {
    return _networkPolicyHelper.hasTurnAvailable(log: _log);
  }
}
