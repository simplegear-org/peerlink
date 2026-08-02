import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../firebase/firebase_push_servers_merge_orchestrator.dart';
import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import 'call_audio_mute_sender.dart';
import 'audio_call_peer.dart';
import 'call_control_signal_helper.dart';
import 'call_command_helper.dart';
import 'call_connection_orchestrator.dart';
import 'call_control_signal_router.dart';
import 'call_heartbeat_controller.dart';
import 'call_incoming_runtime_enrichment.dart';
import 'call_network_policy_helper.dart';
import 'call_media_readiness_controller.dart';
import 'call_models.dart';
import 'call_pending_remote_end_registry.dart';
import 'call_peer_invariant_helper.dart';
import 'call_peer_bootstrap_controller.dart';
import 'call_recovery_coordinator.dart';
import 'call_remote_control_handler.dart';
import 'call_runtime_tracking.dart';
import 'call_session_epoch.dart';
import 'call_signal_transition_serializer.dart';
import 'call_state_factory_helper.dart';
import 'call_state_update_helper.dart';
import 'call_terminal_lifecycle_controller.dart';
import 'call_runtime_logger.dart';

class CallService {
  static const Duration _directConnectAttemptTimeoutDuration = Duration(
    seconds: 8,
  );
  static const Duration _turnConnectAttemptTimeoutDuration = Duration(
    seconds: 20,
  );

  final String selfPeerId;
  final SignalingService signaling;
  final TurnAllocator? turnAllocator;
  final Connectivity _connectivity = Connectivity();

  final StreamController<CallState> _stateController =
      StreamController<CallState>.broadcast();

  CallState _state = CallState.idle;
  AudioCallPeer? _peer;
  Timer? _outgoingTimeout;
  final CallRuntimeTracking _runtimeTracking = CallRuntimeTracking();
  CallSessionEpoch _callEpoch = CallSessionEpoch.initial();
  FutureOr<Map<String, dynamic>> Function(String peerId)
  _buildCallInviteMetadata = (_) => const <String, dynamic>{};
  static const Duration _pendingRemoteEndTtl = Duration(minutes: 2);
  static const FirebasePushServersMergeOrchestrator _serversMergeOrchestrator =
      FirebasePushServersMergeOrchestrator();
  static const Duration _heartbeatMediaActiveGrace = Duration(seconds: 6);
  late final CallPendingRemoteEndRegistry _pendingRemoteEndedCalls;
  late final CallControlSignalHelper _controlSignalHelper;
  late final CallControlSignalRouter _controlSignalRouter;
  late final CallHeartbeatController _heartbeatController;
  late final CallNetworkPolicyHelper _networkPolicyHelper;
  late final CallConnectionOrchestrator _connectionOrchestrator;
  late final CallRemoteControlHandler _remoteControlHandler;
  late final CallMediaReadinessController _mediaReadinessController;
  late final CallTerminalLifecycleController _terminalLifecycleController;
  late final CallPeerBootstrapController _peerBootstrapController;
  late final CallAudioMuteSender _audioMuteSender;
  late final CallSignalTransitionSerializer _signalTransitionSerializer;
  static const CallCommandHelper _commandHelper = CallCommandHelper();
  static const CallPeerInvariantHelper _peerInvariantHelper =
      CallPeerInvariantHelper();
  static const CallStateFactoryHelper _stateFactoryHelper =
      CallStateFactoryHelper();
  static const CallStateUpdateHelper _stateUpdateHelper =
      CallStateUpdateHelper();
  static const CallIncomingRuntimeEnrichment _incomingRuntimeEnrichment =
      CallIncomingRuntimeEnrichment();
  late final CallRuntimeLogger _logger;

  CallService({
    required this.selfPeerId,
    required this.signaling,
    required this.turnAllocator,
  }) {
    _logger = CallRuntimeLogger(
      channel: 'call',
      getOwnerId: () => selfPeerId,
      getContext: () => (
        peerId: _state.peerId,
        callId: _state.callId,
        epoch: _callEpoch.value,
        role: _state.direction?.name ?? 'idle',
        mediaType: _state.mediaType,
        transportMode: _state.transportMode,
        phase: _state.phase,
        signalingState: 'n/a',
      ),
    );
    _pendingRemoteEndedCalls = CallPendingRemoteEndRegistry(
      ttl: _pendingRemoteEndTtl,
    );
    _controlSignalHelper = CallControlSignalHelper(
      signaling: signaling,
      emitWaitingState: () {
        _emit(_state.copyWith(debugStatus: 'Ожидаем восстановление signaling'));
      },
      log: _log,
      logError: _logger.log,
    );
    _signalTransitionSerializer = CallSignalTransitionSerializer(log: _log);
    _networkPolicyHelper = CallNetworkPolicyHelper(
      connectivity: _connectivity,
      turnAllocator: turnAllocator,
      directConnectAttemptTimeout: _directConnectAttemptTimeoutDuration,
      turnConnectAttemptTimeout: _turnConnectAttemptTimeoutDuration,
    );
    _mediaReadinessController = CallMediaReadinessController(
      getState: () => _state,
      getCurrentEpoch: () => _callEpoch.value,
      getPeer: () => _peer,
      matchesCurrentCall: _matchesCurrentCall,
      emit: _emit,
      log: _log,
    );
    _terminalLifecycleController = CallTerminalLifecycleController(
      getState: () => _state,
      getCurrentEpoch: () => _callEpoch.value,
      getPeer: () => _peer,
      setPeer: (peer) => _peer = peer,
      emit: _emit,
      log: _log,
      cancelOutgoingTimeout: () {
        _outgoingTimeout?.cancel();
        _outgoingTimeout = null;
      },
      cancelConnectAttemptTimeout: () {
        _connectionOrchestrator.cancelConnectAttemptTimeout();
      },
      clearMediaReadyTimeout: _mediaReadinessController.clearMediaReadyTimeout,
      resetRuntimeTracking: _resetRuntimeTracking,
      beginRecovery: _mediaReadinessController.beginRecovery,
      sendDetachedSignal: _controlSignalHelper.sendDetached,
    );
    _audioMuteSender = CallAudioMuteSender(
      controlSignalHelper: _controlSignalHelper,
      runtimeTracking: _runtimeTracking,
      getState: () => _state,
      log: _log,
    );
    _connectionOrchestrator = CallConnectionOrchestrator(
      networkPolicyHelper: _networkPolicyHelper,
      turnAllocator: turnAllocator,
      ensurePeer: _ensurePeerForIncomingSignal,
      matchesCurrentCall: _matchesCurrentCall,
      emit: _emit,
      getState: () => _state,
      getCurrentEpoch: () => _callEpoch.value,
      getActiveMediaType: () => _activeMediaType,
      log: _log,
      failAndReset: _terminalLifecycleController.failAndReset,
      clearMediaReadyTimeout: _mediaReadinessController.clearMediaReadyTimeout,
      resetMediaRuntimeTracking: _mediaReadinessController.resetRuntimeTracking,
      disposePeer: () async {
        await _peer?.dispose();
      },
      setPeer: (peer) => _peer = peer,
    );
    _heartbeatController = CallHeartbeatController(
      sendSignal: signaling.sendSignal,
      isSignalingConnected: () =>
          signaling.connectionStatus == SignalingConnectionStatus.connected,
      onHeartbeatMissed: _handleHeartbeatMissed,
      log: _log,
      isMediaRecentlyActive: _isMediaRecentlyActiveForHeartbeat,
    );
    _remoteControlHandler = CallRemoteControlHandler(
      heartbeatController: _heartbeatController,
      runtimeTracking: _runtimeTracking,
      getState: () => _state,
      getPeer: () => _peer,
      emit: _emit,
      log: _log,
      markRemoteMediaReady: _mediaReadinessController.markRemoteMediaReady,
      cancelMediaReadyTimeout: _mediaReadinessController.clearMediaReadyTimeout,
      updateActiveState: _mediaReadinessController.updateActiveState,
      armMediaReadyTimeout: _mediaReadinessController.armMediaReadyTimeout,
      streamHasVideo: _streamHasVideo,
    );
    _peerBootstrapController = CallPeerBootstrapController(
      localPeerId: selfPeerId,
      signaling: signaling,
      turnAllocator: turnAllocator,
      networkPolicyHelper: _networkPolicyHelper,
      runtimeTracking: _runtimeTracking,
      getState: () => _state,
      getPeer: () => _peer,
      setPeer: (peer) => _peer = peer,
      isCurrentPeerInstance: _isCurrentPeerInstance,
      cancelConnectAttemptTimeout:
          _connectionOrchestrator.cancelConnectAttemptTimeout,
      markLocalMediaReady: _mediaReadinessController.markLocalMediaReady,
      markRemoteMediaTimeoutHandled:
          _mediaReadinessController.markRemoteMediaTimeoutHandled,
      updateActiveState: _mediaReadinessController.updateActiveState,
      armMediaReadyTimeout: _mediaReadinessController.armMediaReadyTimeout,
      handleIceRecoveryState: _mediaReadinessController.handleIceRecoveryState,
      sendBestEffortSignal: _controlSignalHelper.sendBestEffort,
      applyStats: _applyPeerStats,
      streamHasVideo: _streamHasVideo,
      getTurnFallbackAttempted: () =>
          _connectionOrchestrator.turnFallbackAttempted,
      retryViaTurn: _connectionOrchestrator.retryViaTurn,
      failAndReset: _terminalLifecycleController.handlePeerError,
      resetPeerStatsTracking: _resetPeerStatsTracking,
      sendAudioMuteState: _sendAudioMuteState,
      emit: _emit,
      log: _log,
    );
    _controlSignalRouter = CallControlSignalRouter(
      sendSignal: signaling.sendSignal,
      isPendingRemoteEndedCall:
          ({required String peerId, required String callId}) =>
              _pendingRemoteEndedCalls.contains(peerId: peerId, callId: callId),
      rememberPendingRemoteEndedCall:
          ({required String peerId, required String callId}) =>
              _pendingRemoteEndedCalls.remember(peerId: peerId, callId: callId),
      parseMediaType: _parseMediaType,
      cancelOutgoingTimeout: () => _outgoingTimeout?.cancel(),
      emit: _emit,
      log: _log,
      endAndReset: _terminalLifecycleController.endAndReset,
      applyInviteRuntimeMetadata: _applyIncomingInviteRuntimeMetadata,
      preferredInitialMode: _preferredInitialMode,
      startPeerConnection: _startPeerConnection,
      onRemoteMediaReady: _remoteControlHandler.handleRemoteMediaReady,
      onRemoteHeartbeat: _remoteControlHandler.handleRemoteHeartbeat,
      onRemoteAudioMuteState: _remoteControlHandler.handleRemoteAudioMuteState,
      onRemoteVideoState: _remoteControlHandler.handleRemoteVideoState,
      onRemoteVideoStateAck: _remoteControlHandler.handleRemoteVideoStateAck,
      onRemoteVideoFlowAck: _remoteControlHandler.handleRemoteVideoFlowAck,
    );
  }

  Stream<CallState> get stateStream => _stateController.stream;
  CallState get state => _state;

  void setCallInviteMetadataBuilder(
    FutureOr<Map<String, dynamic>> Function(String peerId) builder,
  ) {
    _buildCallInviteMetadata = builder;
  }

  Future<void> startOutgoingCall(
    String peerId, {
    CallMediaType mediaType = CallMediaType.audio,
    String? callId,
  }) async {
    _controlSignalHelper.ensureOutgoingSignalingReady('исходящий звонок');
    final inviteMetadata = await _buildCallInviteMetadata(peerId);
    await _commandHelper.startOutgoingCall(
      currentState: _state,
      peerId: peerId,
      mediaType: mediaType,
      callId: callId,
      inviteMetadata: inviteMetadata,
      resetRuntimeTracking: _resetRuntimeTracking,
      emit: _emit,
      waitForSignalingReady: _controlSignalHelper.waitForSignalingReady,
      failAndReset: _terminalLifecycleController.failAndReset,
      setOutgoingTimeout: (timer) {
        _outgoingTimeout?.cancel();
        _outgoingTimeout = timer;
      },
      expectedEpoch: _callEpoch.value,
      getCurrentEpoch: () => _callEpoch.value,
      endAndReset: (status) async {
        if (_state.peerId == peerId &&
            _state.phase == CallPhase.outgoingRinging) {
          await _terminalLifecycleController.endAndReset(status);
        }
      },
      sendSignal: signaling.sendSignal,
      log: _log,
    );
  }

  Future<void> _applyIncomingInviteRuntimeMetadata(
    Map<String, dynamic> data,
  ) async {
    await _serversMergeOrchestrator.applyIfPresent(
      data,
      source: 'bootstrap-call-invite',
      logName: 'call',
      logPrefix: '[call][servers]',
    );
  }

  Future<void> presentIncomingCallFromPush({
    required String peerId,
    required String callId,
    CallMediaType mediaType = CallMediaType.audio,
  }) async {
    _commandHelper.presentIncomingCallFromPush(
      currentState: _state,
      peerId: peerId,
      callId: callId,
      mediaType: mediaType,
      isPendingRemoteEndedCall:
          ({required String peerId, required String callId}) =>
              _pendingRemoteEndedCalls.contains(peerId: peerId, callId: callId),
      resetRuntimeTracking: _resetRuntimeTracking,
      emit: _emit,
      log: _log,
    );
  }

  Future<void> acceptIncomingCall() async {
    await _commandHelper.acceptIncomingCall(
      currentState: _state,
      resetRuntimeTracking: _resetRuntimeTracking,
      emit: _emit,
      waitForSignalingReady: _controlSignalHelper.waitForSignalingReady,
      waitForRuntimeEnrichment: _waitForIncomingRuntimeEnrichment,
      sendSignal: signaling.sendSignal,
      getActiveMediaType: () => _activeMediaType,
      log: _log,
    );
  }

  Future<void> rejectIncomingCall() async {
    await _commandHelper.rejectIncomingCall(
      currentState: _state,
      sendDetachedSignal: _controlSignalHelper.sendDetached,
      endAndReset: _terminalLifecycleController.endAndReset,
    );
  }

  Future<void> endCall() async {
    await _commandHelper.endCall(
      currentState: _state,
      sendDetachedSignal: _controlSignalHelper.sendDetached,
      endAndReset: _terminalLifecycleController.endAndReset,
    );
  }

  Future<void> endCallFromRemotePush({
    required String peerId,
    required String callId,
  }) async {
    await _commandHelper.endCallFromRemotePush(
      currentState: _state,
      peerId: peerId,
      callId: callId,
      rememberPendingRemoteEndedCall:
          ({required String peerId, required String callId}) =>
              _pendingRemoteEndedCalls.remember(peerId: peerId, callId: callId),
      endAndReset: _terminalLifecycleController.endAndReset,
    );
  }

  Future<void> setMuted(bool muted) async {
    await _peer?.setMuted(muted);
    _emit(_stateFactoryHelper.applyMuted(_state, muted));
    _sendAudioMuteState(muted, purpose: 'состояние микрофона');
  }

  Future<void> toggleMuted() {
    return setMuted(!_state.isMuted);
  }

  Future<void> setSpeakerOn(bool enabled) async {
    await _peer?.setSpeakerOn(enabled);
    _emit(_stateFactoryHelper.applySpeakerOn(_state, enabled));
  }

  Future<void> toggleVideo() async {
    if (_state.isIdle ||
        _state.isIncoming ||
        !_state.isActive ||
        _state.videoToggleInProgress) {
      return;
    }

    final peer = _peer;
    if (peer == null) {
      return;
    }

    final targetEnabled = !_state.localVideoEnabled;
    _emit(
      _stateFactoryHelper.videoToggleStarted(
        currentState: _state,
        targetEnabled: targetEnabled,
      ),
    );
    try {
      final nextMediaType = await peer.toggleVideo();
      _emit(
        _stateFactoryHelper.videoToggleSucceeded(
          currentState: _state,
          nextMediaType: nextMediaType,
        ),
      );
    } catch (error) {
      _emit(
        _stateFactoryHelper.videoToggleFailed(
          currentState: _state,
          error: error,
        ),
      );
    }
  }

  Future<void> flipCamera() async {
    if (_state.isIdle || _peer == null) {
      return;
    }
    if (_state.isRecovering) {
      _log(
        'flipCamera:skip recovery kind=${_state.recoveryKind?.name ?? 'unknown'} '
        'attempt=${_state.recoveryAttempt}',
      );
      return;
    }
    _mediaReadinessController.beginRecovery(
      kind: CallRecoveryKind.camera,
      status: 'Переключаем камеру и удерживаем медиасессию',
    );
    try {
      await _peer?.flipCamera();
      _mediaReadinessController.completeRecovery(status: 'Камера переключена');
    } catch (error) {
      await _terminalLifecycleController.handlePeerError(
        'Не удалось переключить камеру: $error',
      );
    }
  }

  Future<void> handleControlSignal(SignalingMessage message) async {
    await _signalTransitionSerializer.serialize(
      label: 'control:${message.type}',
      action: () async {
        try {
          await _controlSignalRouter.handle(
            currentState: _state,
            message: message,
          );
        } catch (error) {
          await _terminalLifecycleController.failAndReset(error.toString());
        }
      },
    );
  }

  Future<void> handleMediaSignal(SignalingMessage message) async {
    await _signalTransitionSerializer.serialize(
      label: 'media:${message.type}',
      action: () async {
        final peerId = message.fromPeerId;
        final callId = message.data['callId']?.toString();
        if (callId == null || callId.isEmpty) {
          return;
        }

        if (_peerInvariantHelper.hasForeignPeerForActiveCallId(
          currentState: _state,
          peerId: peerId,
          callId: callId,
        )) {
          _log(
            'mediaSignal:ignored foreign-peer same-callId peerId=$peerId callId=$callId '
            'currentPeerId=${_state.peerId} phase=${_state.phase.name}',
          );
          return;
        }

        if (_state.peerId != peerId || _state.callId != callId) {
          _log(
            'mediaSignal:ignored mismatched peerId=$peerId callId=$callId '
            'currentPeerId=${_state.peerId} currentCallId=${_state.callId} '
            'phase=${_state.phase.name}',
          );
          return;
        }

        final peer = await _ensurePeerForIncomingSignal(
          peerId: peerId,
          callId: callId,
        );
        await peer?.handleSignal(message);
      },
    );
  }

  Future<void> dispose() async {
    _heartbeatController.stop();
    _outgoingTimeout?.cancel();
    _connectionOrchestrator.dispose();
    await _peer?.dispose();
    _peer = null;
    await _stateController.close();
  }

  Future<void> _startPeerConnection({
    required String peerId,
    required String callId,
    required TransportMode initialMode,
  }) async {
    await _connectionOrchestrator.startPeerConnection(
      peerId: peerId,
      callId: callId,
      initialMode: initialMode,
    );
  }

  Future<TransportMode> _preferredInitialMode() async {
    return _connectionOrchestrator.preferredInitialMode();
  }

  Future<AudioCallPeer?> _ensurePeerForIncomingSignal({
    required String peerId,
    required String callId,
  }) async {
    return _peerBootstrapController.ensurePeer(peerId: peerId, callId: callId);
  }

  bool _isCurrentPeerInstance(
    AudioCallPeer peer,
    String peerId,
    String callId,
  ) {
    return identical(_peer, peer) && _matchesCurrentCall(peerId, callId);
  }

  void _emit(CallState next) {
    final previous = _state;
    if (_sameState(previous, next)) {
      return;
    }
    _state = next;
    _syncHeartbeatForState(next);
    _stateController.add(next);
    if (_isStatsOnlyStateChange(previous, next)) {
      return;
    }
    _log(
      'state phase=${next.phase.name} peerId=${next.peerId} mode=${next.transportMode?.name}',
    );
  }

  void _resetRuntimeTracking() {
    _heartbeatController.stop();
    _callEpoch = _callEpoch.next();
    _connectionOrchestrator.resetRuntimeTracking();
    _mediaReadinessController.resetRuntimeTracking();
    _terminalLifecycleController.resetRuntimeTracking();
    _runtimeTracking.reset();
  }

  void _log(String message) {
    _logger.log(message);
  }

  bool _sameState(CallState left, CallState right) {
    return left.phase == right.phase &&
        left.callId == right.callId &&
        left.peerId == right.peerId &&
        left.direction == right.direction &&
        left.mediaType == right.mediaType &&
        left.isMuted == right.isMuted &&
        left.speakerOn == right.speakerOn &&
        left.transportMode == right.transportMode &&
        left.transportLabel == right.transportLabel &&
        left.debugStatus == right.debugStatus &&
        left.error == right.error &&
        left.connectedAt == right.connectedAt &&
        left.bytesSent == right.bytesSent &&
        left.bytesReceived == right.bytesReceived &&
        left.localVideoEnabled == right.localVideoEnabled &&
        left.localVideoAvailable == right.localVideoAvailable &&
        left.remoteVideoEnabled == right.remoteVideoEnabled &&
        left.remoteVideoAvailable == right.remoteVideoAvailable &&
        left.remoteVideoActive == right.remoteVideoActive &&
        left.remoteVideoTrackId == right.remoteVideoTrackId &&
        left.videoCodec == right.videoCodec &&
        left.videoToggleInProgress == right.videoToggleInProgress &&
        left.recoveryKind == right.recoveryKind &&
        left.recoveryAttempt == right.recoveryAttempt &&
        left.recoveryReturnPhase == right.recoveryReturnPhase &&
        left.isFrontCamera == right.isFrontCamera &&
        left.localStream?.id == right.localStream?.id &&
        left.remoteStream?.id == right.remoteStream?.id;
  }

  bool _isStatsOnlyStateChange(CallState previous, CallState next) {
    return previous.phase == next.phase &&
        previous.callId == next.callId &&
        previous.peerId == next.peerId &&
        previous.direction == next.direction &&
        previous.mediaType == next.mediaType &&
        previous.isMuted == next.isMuted &&
        previous.speakerOn == next.speakerOn &&
        previous.transportMode == next.transportMode &&
        previous.transportLabel == next.transportLabel &&
        previous.debugStatus == next.debugStatus &&
        previous.error == next.error &&
        previous.connectedAt == next.connectedAt &&
        previous.localVideoEnabled == next.localVideoEnabled &&
        previous.localVideoAvailable == next.localVideoAvailable &&
        previous.remoteVideoEnabled == next.remoteVideoEnabled &&
        previous.remoteVideoAvailable == next.remoteVideoAvailable &&
        previous.remoteVideoActive == next.remoteVideoActive &&
        previous.remoteVideoTrackId == next.remoteVideoTrackId &&
        previous.videoCodec == next.videoCodec &&
        previous.videoToggleInProgress == next.videoToggleInProgress &&
        previous.recoveryKind == next.recoveryKind &&
        previous.recoveryAttempt == next.recoveryAttempt &&
        previous.recoveryReturnPhase == next.recoveryReturnPhase &&
        previous.isFrontCamera == next.isFrontCamera &&
        previous.localStream?.id == next.localStream?.id &&
        previous.remoteStream?.id == next.remoteStream?.id &&
        (previous.bytesSent != next.bytesSent ||
            previous.bytesReceived != next.bytesReceived);
  }

  void _applyPeerStats({required int sentBytes, required int receivedBytes}) {
    final result = _runtimeTracking.applyPeerStats(
      currentState: _state,
      sentBytes: sentBytes,
      receivedBytes: receivedBytes,
      stateUpdateHelper: _stateUpdateHelper,
    );
    if (result.state.bytesSent == _state.bytesSent &&
        result.state.bytesReceived == _state.bytesReceived) {
      return;
    }
    _emit(result.state);
  }

  void _resetPeerStatsTracking() {
    _runtimeTracking.resetPeerStatsTracking(_state);
  }

  bool _isMediaRecentlyActiveForHeartbeat() {
    return _runtimeTracking.isMediaRecentlyActive(
      grace: _heartbeatMediaActiveGrace,
    );
  }

  Future<void> _handleHeartbeatMissed(String reason) async {
    if (!_state.isActive && !_state.isRecovering) {
      _log('callHeartbeat:recovery skip inactive reason="$reason"');
      return;
    }
    final peer = _peer;
    if (peer == null) {
      _log('callHeartbeat:recovery skip peer=false reason="$reason"');
      return;
    }
    if (_state.isRecovering) {
      _log(
        'callHeartbeat:recovery skip already-recovering '
        'kind=${_state.recoveryKind?.name ?? 'unknown'} reason="$reason"',
      );
      return;
    }
    await peer.observeRecovery(
      CallRecoveryObservation(
        kind: CallRecoveryObservationKind.heartbeatMissed,
        reason: reason,
      ),
    );
  }

  void _sendAudioMuteState(bool muted, {required String purpose}) {
    _audioMuteSender.send(muted, purpose: purpose);
  }

  bool _streamHasVideo(MediaStream? stream) {
    return stream?.getVideoTracks().isNotEmpty ?? false;
  }

  void _syncHeartbeatForState(CallState state) {
    final peerId = state.peerId;
    final callId = state.callId;
    final shouldRun = state.isActive || state.isRecovering;
    if (shouldRun && peerId != null && callId != null) {
      _heartbeatController.start(peerId: peerId, callId: callId);
      return;
    }
    _heartbeatController.stop();
  }

  CallMediaType get _activeMediaType => _state.mediaType;

  CallMediaType _parseMediaType(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    return normalized == CallMediaType.video.name
        ? CallMediaType.video
        : CallMediaType.audio;
  }

  bool _matchesCurrentCall(String peerId, String callId) {
    return _peerInvariantHelper.matchesCurrentCall(
      currentState: _state,
      peerId: peerId,
      callId: callId,
    );
  }

  Future<void> _waitForIncomingRuntimeEnrichment() async {
    await _incomingRuntimeEnrichment.waitIfIncoming(
      getState: () => _state,
      log: _log,
    );
  }
}
