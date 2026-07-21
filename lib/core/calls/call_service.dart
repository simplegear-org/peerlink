import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../firebase/firebase_push_servers_merge_orchestrator.dart';
import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import 'audio_call_peer.dart';
import '../firebase/firebase_push_callback_registry.dart';
import 'call_control_signal_helper.dart';
import 'call_command_helper.dart';
import 'call_connect_orchestration_helper.dart';
import 'call_control_signal_router.dart';
import 'call_heartbeat_controller.dart';
import 'call_lifecycle_reset_helper.dart';
import 'call_network_policy_helper.dart';
import 'call_media_readiness_helper.dart';
import 'call_media_timeout_helper.dart';
import 'call_models.dart';
import 'incoming_call_bootstrap_policy.dart';
import 'call_pending_remote_end_registry.dart';
import 'call_peer_binding_helper.dart';
import 'call_peer_invariant_helper.dart';
import 'call_peer_lifecycle_helper.dart';
import 'call_recovery_coordinator.dart';
import 'call_recovery_state_helper.dart';
import 'call_session_epoch.dart';
import 'call_state_factory_helper.dart';
import 'call_state_update_helper.dart';
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
  Timer? _connectAttemptTimeout;
  Timer? _mediaReadyTimeout;
  bool _turnFallbackAttempted = false;
  bool _localMediaReady = false;
  bool _remoteMediaReady = false;
  DateTime? _lastMediaStatsAdvancedAt;
  int _mediaRecoveryAttempt = 0;
  int _statsOffsetSent = 0;
  int _statsOffsetReceived = 0;
  int _lastPeerSentBytes = 0;
  int _lastPeerReceivedBytes = 0;
  int _localAudioMuteVersion = 0;
  bool _remoteAudioMuted = false;
  int _remoteAudioMuteVersion = -1;
  CallSessionEpoch _callEpoch = CallSessionEpoch.initial();
  bool _terminalTransitionInFlight = false;
  Future<void> _orchestrationSignalQueue = Future<void>.value();
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
  static const CallCommandHelper _commandHelper = CallCommandHelper();
  static const CallConnectOrchestrationHelper _connectOrchestrationHelper =
      CallConnectOrchestrationHelper();
  static const CallPeerBindingHelper _peerBindingHelper =
      CallPeerBindingHelper();
  static const CallPeerInvariantHelper _peerInvariantHelper =
      CallPeerInvariantHelper();
  static const CallPeerLifecycleHelper _peerLifecycleHelper =
      CallPeerLifecycleHelper();
  static const CallRecoveryStateHelper _recoveryStateHelper =
      CallRecoveryStateHelper();
  static const CallLifecycleResetHelper _lifecycleResetHelper =
      CallLifecycleResetHelper();
  static const CallMediaReadinessHelper _mediaReadinessHelper =
      CallMediaReadinessHelper();
  static const CallMediaTimeoutHelper _mediaTimeoutHelper =
      CallMediaTimeoutHelper();
  static const CallStateFactoryHelper _stateFactoryHelper =
      CallStateFactoryHelper();
  static const CallStateUpdateHelper _stateUpdateHelper =
      CallStateUpdateHelper();
  static const IncomingCallBootstrapPolicy _incomingBootstrapPolicy =
      IncomingCallBootstrapPolicy();
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
    _networkPolicyHelper = CallNetworkPolicyHelper(
      connectivity: _connectivity,
      turnAllocator: turnAllocator,
      directConnectAttemptTimeout: _directConnectAttemptTimeoutDuration,
      turnConnectAttemptTimeout: _turnConnectAttemptTimeoutDuration,
    );
    _heartbeatController = CallHeartbeatController(
      sendSignal: signaling.sendSignal,
      isSignalingConnected: () =>
          signaling.connectionStatus == SignalingConnectionStatus.connected,
      onHeartbeatMissed: _handleHeartbeatMissed,
      log: _log,
      isMediaRecentlyActive: _isMediaRecentlyActiveForHeartbeat,
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
      endAndReset: _endAndReset,
      applyInviteRuntimeMetadata: _applyIncomingInviteRuntimeMetadata,
      preferredInitialMode: _preferredInitialMode,
      startPeerConnection: _startPeerConnection,
      onRemoteMediaReady: _handleRemoteMediaReady,
      onRemoteHeartbeat: _handleRemoteHeartbeat,
      onRemoteAudioMuteState: _handleRemoteAudioMuteState,
      onRemoteVideoState: _handleRemoteVideoState,
      onRemoteVideoStateAck: _handleRemoteVideoStateAck,
      onRemoteVideoFlowAck: _handleRemoteVideoFlowAck,
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
      failAndReset: _failAndReset,
      setOutgoingTimeout: (timer) {
        _outgoingTimeout?.cancel();
        _outgoingTimeout = timer;
      },
      endAndReset: (status) async {
        if (_state.peerId == peerId &&
            _state.phase == CallPhase.outgoingRinging) {
          await _endAndReset(status);
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
      endAndReset: _endAndReset,
    );
  }

  Future<void> endCall() async {
    await _commandHelper.endCall(
      currentState: _state,
      sendDetachedSignal: _controlSignalHelper.sendDetached,
      endAndReset: _endAndReset,
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
      endAndReset: _endAndReset,
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
    _beginRecovery(
      kind: CallRecoveryKind.camera,
      status: 'Переключаем камеру и удерживаем медиасессию',
    );
    try {
      await _peer?.flipCamera();
      _completeRecovery(status: 'Камера переключена');
    } catch (error) {
      await _handlePeerError('Не удалось переключить камеру: $error');
    }
  }

  Future<void> handleControlSignal(SignalingMessage message) async {
    await _serializeOrchestrationSignalTransition(
      label: 'control:${message.type}',
      action: () async {
        try {
          await _controlSignalRouter.handle(
            currentState: _state,
            message: message,
          );
        } catch (error) {
          await _failAndReset(error.toString());
        }
      },
    );
  }

  Future<void> handleMediaSignal(SignalingMessage message) async {
    await _serializeOrchestrationSignalTransition(
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
    _connectAttemptTimeout?.cancel();
    await _peer?.dispose();
    _peer = null;
    await _stateController.close();
  }

  Future<void> _startPeerConnection({
    required String peerId,
    required String callId,
    required TransportMode initialMode,
  }) async {
    await _connectOrchestrationHelper.startPeerConnection(
      peerId: peerId,
      callId: callId,
      initialMode: initialMode,
      ensurePeer: _ensurePeerForIncomingSignal,
      matchesCurrentCall: _matchesCurrentCall,
      emit: _emit,
      getState: () => _state,
      transportLabelFor: _networkPolicyHelper.transportLabelFor,
      getActiveMediaType: () => _activeMediaType,
      log: _log,
      retryViaTurn: _retryViaTurn,
      failAndReset: _failAndReset,
      armConnectAttemptTimeout: _armConnectAttemptTimeout,
    );
  }

  Future<TransportMode> _preferredInitialMode() async {
    return _networkPolicyHelper.preferredInitialMode(log: _log);
  }

  Future<bool> _hasTurnAvailable() async {
    return _networkPolicyHelper.hasTurnAvailable(log: _log);
  }

  Future<AudioCallPeer?> _ensurePeerForIncomingSignal({
    required String peerId,
    required String callId,
  }) async {
    _log(
      'ensurePeer:start peerId=$peerId callId=$callId hasPeer=${_peer != null} '
      'matchesCurrent=${_matchesCurrentCall(peerId, callId)}',
    );
    if (_peerInvariantHelper.hasForeignPeerForActiveCallId(
      currentState: _state,
      peerId: peerId,
      callId: callId,
    )) {
      _log(
        'ensurePeer:skip foreign-peer same-callId peerId=$peerId callId=$callId '
        'currentPeerId=${_state.peerId}',
      );
      return null;
    }

    if (_peer != null &&
        _peerInvariantHelper.matchesCurrentCall(
          currentState: _state,
          peerId: peerId,
          callId: callId,
        )) {
      _log('ensurePeer:reuse existing peerId=$peerId callId=$callId');
      return _peer;
    }

    if (!_matchesCurrentCall(peerId, callId)) {
      _log('ensurePeer:skip mismatch peerId=$peerId callId=$callId');
      return null;
    }

    _log('ensurePeer:create peerId=$peerId callId=$callId');
    final peer = _peerBindingHelper.createPeer(
      localPeerId: selfPeerId,
      signaling: signaling,
      turnAllocator: turnAllocator,
      peerId: peerId,
      callId: callId,
      isCurrentPeerInstance: _isCurrentPeerInstance,
      getState: () => _state,
      cancelConnectAttemptTimeout: () {
        _connectAttemptTimeout?.cancel();
      },
      transportLabelFor: _networkPolicyHelper.transportLabelFor,
      emit: _emit,
      markLocalMediaReady: () {
        _localMediaReady = true;
      },
      markRemoteMediaTimeoutHandled: () {
        _mediaReadyTimeout?.cancel();
        _mediaReadyTimeout = null;
      },
      updateActiveState: _updateActiveState,
      armMediaReadyTimeout: _armMediaReadyTimeout,
      handleIceRecoveryState: _handleIceRecoveryState,
      sendBestEffortSignal: _controlSignalHelper.sendBestEffort,
      applyStats: _applyPeerStats,
      streamHasVideo: _streamHasVideo,
      getTurnFallbackAttempted: () => _turnFallbackAttempted,
      retryViaTurn: _retryViaTurn,
      failAndReset: _handlePeerError,
    );

    _log('ensurePeer:attach begin peerId=$peerId callId=$callId');
    final attached = await _peerLifecycleHelper.attachAndPreparePeer(
      peer: peer,
      peerId: peerId,
      callId: callId,
      currentState: _state,
      matchesCurrentCall: _matchesCurrentCall,
      setPeer: (nextPeer) => _peer = nextPeer,
      resetPeerStatsTracking: _resetPeerStatsTracking,
      emit: _emit,
      log: _log,
    );
    _log(
      'ensurePeer:attach done peerId=$peerId callId=$callId '
      'attached=${attached != null}',
    );
    if (attached != null && _remoteAudioMuteVersion >= 0) {
      await attached.handleRemoteAudioMuteState(
        muted: _remoteAudioMuted,
        version: _remoteAudioMuteVersion,
      );
    }
    if (attached != null && _state.isMuted) {
      _sendAudioMuteState(
        _state.isMuted,
        purpose: 'синхронизация mute после attach',
      );
    }
    return attached;
  }

  bool _isCurrentPeerInstance(
    AudioCallPeer peer,
    String peerId,
    String callId,
  ) {
    return identical(_peer, peer) && _matchesCurrentCall(peerId, callId);
  }

  void _handleIceRecoveryState({
    required bool recovering,
    required String status,
  }) {
    if (_state.isIdle) {
      return;
    }
    if (recovering) {
      _beginRecovery(kind: CallRecoveryKind.ice, status: status);
      return;
    }
    _completeRecovery(status: status);
  }

  void _beginRecovery({
    required CallRecoveryKind kind,
    required String status,
  }) {
    if (_state.isIdle) {
      return;
    }
    _emit(
      _recoveryStateHelper.startRecovery(
        currentState: _state,
        kind: kind,
        status: status,
      ),
    );
  }

  void _completeRecovery({required String status}) {
    if (!_state.isRecovering && _state.recoveryKind == null) {
      return;
    }
    _emit(
      _recoveryStateHelper.completeRecovery(
        currentState: _state,
        status: status,
      ),
    );
    _updateActiveState();
  }

  Future<void> _handlePeerError(String error) async {
    if (_state.isIdle) {
      return;
    }
    if (error.startsWith('ICE connection')) {
      final iceAttempts = _state.recoveryKind == CallRecoveryKind.ice
          ? _state.recoveryAttempt
          : 0;
      if (iceAttempts < 2) {
        _beginRecovery(
          kind: CallRecoveryKind.ice,
          status: 'Восстанавливаем соединение: $error',
        );
        return;
      }
    }
    await _failAndReset(error);
  }

  Future<void> _failAndReset(String error) async {
    if (_state.isIdle) {
      _log('terminal:skip fail reason=idle error=$error');
      return;
    }
    if (_terminalTransitionInFlight) {
      _log('terminal:skip fail reason=in_flight error=$error');
      return;
    }
    _terminalTransitionInFlight = true;
    final expectedEpoch = _callEpoch.value;
    await _peer?.releaseLocalMediaForTeardown();
    _emitTerminalMediaReleasedState();
    await _lifecycleResetHelper
        .failAndReset(
          currentState: _state,
          error: error,
          expectedEpoch: expectedEpoch,
          getCurrentEpoch: () => _callEpoch.value,
          emit: _emit,
          resetToIdle: _resetToIdle,
          sendDetachedSignal: _controlSignalHelper.sendDetached,
        )
        .whenComplete(() {
          _terminalTransitionInFlight = false;
        });
  }

  Future<void> _endAndReset(String status) async {
    if (_state.isIdle) {
      _log('terminal:skip end reason=idle status=$status');
      return;
    }
    if (_terminalTransitionInFlight) {
      _log('terminal:skip end reason=in_flight status=$status');
      return;
    }
    _terminalTransitionInFlight = true;
    final expectedEpoch = _callEpoch.value;
    await _peer?.releaseLocalMediaForTeardown();
    _emitTerminalMediaReleasedState();
    await _lifecycleResetHelper
        .endAndReset(
          currentState: _state,
          status: status,
          expectedEpoch: expectedEpoch,
          getCurrentEpoch: () => _callEpoch.value,
          emit: _emit,
          resetToIdle: _resetToIdle,
        )
        .whenComplete(() {
          _terminalTransitionInFlight = false;
        });
  }

  Future<void> _resetToIdle() async {
    await _peerLifecycleHelper.resetToIdle(
      cancelOutgoingTimeout: () {
        _outgoingTimeout?.cancel();
        _outgoingTimeout = null;
      },
      cancelConnectAttemptTimeout: () {
        _connectAttemptTimeout?.cancel();
        _connectAttemptTimeout = null;
      },
      clearMediaReadyTimeout: () {
        _mediaReadyTimeout?.cancel();
        _mediaReadyTimeout = null;
      },
      resetRuntimeTracking: _resetRuntimeTracking,
      disposePeer: () async {
        await _peer?.dispose();
      },
      setPeer: (peer) => _peer = peer,
      emit: _emit,
    );
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

  void _emitTerminalMediaReleasedState() {
    if (_state.isIdle) {
      return;
    }
    _emit(
      _state.copyWith(
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

  void _resetRuntimeTracking() {
    _heartbeatController.stop();
    _callEpoch = _callEpoch.next();
    _terminalTransitionInFlight = false;
    _turnFallbackAttempted = false;
    _localMediaReady = false;
    _remoteMediaReady = false;
    _lastMediaStatsAdvancedAt = null;
    _mediaRecoveryAttempt = 0;
    _statsOffsetSent = 0;
    _statsOffsetReceived = 0;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    _localAudioMuteVersion = 0;
    _remoteAudioMuted = false;
    _remoteAudioMuteVersion = -1;
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
    final result = _stateUpdateHelper.applyPeerStats(
      currentState: _state,
      sentBytes: sentBytes,
      receivedBytes: receivedBytes,
      statsOffsetSent: _statsOffsetSent,
      statsOffsetReceived: _statsOffsetReceived,
      lastPeerSentBytes: _lastPeerSentBytes,
      lastPeerReceivedBytes: _lastPeerReceivedBytes,
    );
    _statsOffsetSent = result.statsOffsetSent;
    _statsOffsetReceived = result.statsOffsetReceived;
    _lastPeerSentBytes = result.lastPeerSentBytes;
    _lastPeerReceivedBytes = result.lastPeerReceivedBytes;
    if (result.state.bytesSent == _state.bytesSent &&
        result.state.bytesReceived == _state.bytesReceived) {
      return;
    }
    _lastMediaStatsAdvancedAt = DateTime.now();
    _emit(result.state);
  }

  void _resetPeerStatsTracking() {
    _statsOffsetSent = _state.bytesSent;
    _statsOffsetReceived = _state.bytesReceived;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    _lastMediaStatsAdvancedAt = null;
  }

  bool _isMediaRecentlyActiveForHeartbeat() {
    final lastAdvancedAt = _lastMediaStatsAdvancedAt;
    if (lastAdvancedAt == null) {
      return false;
    }
    return DateTime.now().difference(lastAdvancedAt) <=
        _heartbeatMediaActiveGrace;
  }

  Future<void> _handleRemoteMediaReady({
    required String peerId,
    required String callId,
  }) async {
    _remoteMediaReady = true;
    _mediaReadyTimeout?.cancel();
    _updateActiveState();
    _armMediaReadyTimeout();
  }

  Future<void> _handleRemoteHeartbeat({
    required String peerId,
    required String callId,
    required int seq,
    required int sentAtMs,
  }) async {
    _heartbeatController.markRemoteHeartbeat(
      peerId: peerId,
      callId: callId,
      seq: seq,
      sentAtMs: sentAtMs,
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

  Future<void> _handleRemoteAudioMuteState({
    required String peerId,
    required String callId,
    required bool muted,
    required int version,
  }) async {
    if (version <= _remoteAudioMuteVersion) {
      _log(
        'audioMute:remote ignored peerId=$peerId callId=$callId '
        'muted=$muted version=$version lastVersion=$_remoteAudioMuteVersion',
      );
      return;
    }
    _remoteAudioMuted = muted;
    _remoteAudioMuteVersion = version;
    _log(
      'audioMute:remote peerId=$peerId callId=$callId '
      'muted=$muted version=$version',
    );
    await _peer?.handleRemoteAudioMuteState(muted: muted, version: version);
  }

  void _sendAudioMuteState(bool muted, {required String purpose}) {
    if (_state.isIdle) {
      return;
    }
    final peerId = _state.peerId;
    final callId = _state.callId;
    if (peerId == null || callId == null) {
      return;
    }
    _localAudioMuteVersion += 1;
    final version = _localAudioMuteVersion;
    _log(
      'audioMute:send peerId=$peerId callId=$callId '
      'muted=$muted version=$version purpose="$purpose"',
    );
    _controlSignalHelper.sendDetached(peerId, 'call_audio_mute_state', {
      'callId': callId,
      'signalScope': 'call',
      'muted': muted,
      'version': version,
    }, purpose: purpose);
  }

  Future<void> _handleRemoteVideoState({
    required String peerId,
    required String callId,
    required bool enabled,
    required int version,
  }) async {
    _emit(
      _stateUpdateHelper.applyRemoteVideoState(
        currentState: _state,
        enabled: enabled,
        streamHasVideo: _streamHasVideo,
      ),
    );
    await _peer?.handleRemoteVideoState(
      enabled: enabled,
      version: version,
      peerId: peerId,
      callId: callId,
    );
  }

  Future<void> _handleRemoteVideoStateAck({
    required String peerId,
    required String callId,
    required bool enabled,
    required int version,
  }) async {
    await _peer?.handleVideoStateAck(enabled: enabled, version: version);
  }

  Future<void> _handleRemoteVideoFlowAck({
    required String peerId,
    required String callId,
    required int version,
  }) async {
    await _peer?.handleVideoFlowAck(version: version);
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

  void _armConnectAttemptTimeout({
    required String peerId,
    required String callId,
    required TransportMode mode,
  }) {
    final expectedEpoch = _callEpoch.value;
    _connectAttemptTimeout?.cancel();
    _connectAttemptTimeout = _connectOrchestrationHelper
        .armConnectAttemptTimeout(
          timeout: _networkPolicyHelper.timeoutForMode(mode),
          peerId: peerId,
          callId: callId,
          mode: mode,
          expectedEpoch: expectedEpoch,
          getState: () => _state,
          getCurrentEpoch: () => _callEpoch.value,
          getTurnFallbackAttempted: () => _turnFallbackAttempted,
          hasTurnAvailableNow: () => turnAllocator?.allocate() != null,
          log: _log,
          retryViaTurn: _retryViaTurn,
          failAndReset: _failAndReset,
        );
  }

  Future<void> _retryViaTurn({
    required String peerId,
    required String callId,
    required String reason,
  }) async {
    await _connectOrchestrationHelper.retryViaTurn(
      peerId: peerId,
      callId: callId,
      reason: reason,
      getTurnFallbackAttempted: () => _turnFallbackAttempted,
      setTurnFallbackAttempted: (value) => _turnFallbackAttempted = value,
      cancelConnectAttemptTimeout: () {
        _connectAttemptTimeout?.cancel();
      },
      clearMediaReadyTimeout: () {
        _mediaReadyTimeout?.cancel();
        _mediaReadyTimeout = null;
      },
      resetMediaRuntimeTracking: () {
        _localMediaReady = false;
        _remoteMediaReady = false;
        _mediaRecoveryAttempt = 0;
      },
      hasTurnAvailable: _hasTurnAvailable,
      emit: _emit,
      getState: () => _state,
      failAndReset: _failAndReset,
      log: _log,
      disposePeer: () async {
        await _peer?.dispose();
      },
      setPeer: (peer) => _peer = peer,
      ensurePeer: _ensurePeerForIncomingSignal,
      matchesCurrentCall: _matchesCurrentCall,
      getActiveMediaType: () => _activeMediaType,
      armConnectAttemptTimeout: _armConnectAttemptTimeout,
    );
  }

  CallMediaType get _activeMediaType => _state.mediaType;

  CallMediaType _parseMediaType(Object? raw) {
    final normalized = raw?.toString().trim().toLowerCase() ?? '';
    return normalized == CallMediaType.video.name
        ? CallMediaType.video
        : CallMediaType.audio;
  }

  void _updateActiveState() {
    if (_state.isIdle) {
      return;
    }
    final nextState = _mediaReadinessHelper.buildReadinessState(
      currentState: _state,
      localMediaReady: _localMediaReady,
      remoteMediaReady: _remoteMediaReady,
      now: DateTime.now(),
    );
    if (nextState.phase == CallPhase.active) {
      final clearIceRecovery = _state.recoveryKind == CallRecoveryKind.ice;
      if (_state.phase != CallPhase.active || clearIceRecovery) {
        _mediaReadyTimeout?.cancel();
        _mediaReadyTimeout = null;
        _emit(
          clearIceRecovery
              ? nextState.copyWith(
                  recoveryAttempt: 0,
                  clearRecoveryKind: true,
                  clearRecoveryReturnPhase: true,
                  clearError: true,
                )
              : nextState,
        );
      }
      return;
    }
    _emit(nextState);
  }

  void _armMediaReadyTimeout() {
    if (_state.isActive || (_localMediaReady && _remoteMediaReady)) {
      return;
    }
    final expectedPeerId = _state.peerId;
    final expectedCallId = _state.callId;
    final expectedPeer = _peer;
    if (expectedPeerId == null ||
        expectedCallId == null ||
        expectedPeer == null) {
      return;
    }
    _mediaReadyTimeout?.cancel();
    final expectedEpoch = _callEpoch.value;
    _mediaReadyTimeout = _mediaTimeoutHelper.armMediaReadyTimeout(
      timeout: const Duration(seconds: 6),
      getState: () => _state,
      getLocalMediaReady: () => _localMediaReady,
      getRemoteMediaReady: () => _remoteMediaReady,
      expectedEpoch: expectedEpoch,
      getCurrentEpoch: () => _callEpoch.value,
      expectedPeer: expectedPeer,
      expectedPeerId: expectedPeerId,
      expectedCallId: expectedCallId,
      matchesCurrentCall: _matchesCurrentCall,
      getPeer: () => _peer,
      getMediaRecoveryAttempt: () => _mediaRecoveryAttempt,
      setMediaRecoveryAttempt: (value) => _mediaRecoveryAttempt = value,
      onMediaReadyTimeout: _handleMediaReadyTimeout,
      log: _log,
      rearmMediaReadyTimeout: _armMediaReadyTimeout,
    );
  }

  Future<CallRecoveryDisposition> _handleMediaReadyTimeout({
    required int attempt,
    required bool localMediaReady,
    required bool remoteMediaReady,
  }) async {
    final peer = _peer;
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

  bool _matchesCurrentCall(String peerId, String callId) {
    return _peerInvariantHelper.matchesCurrentCall(
      currentState: _state,
      peerId: peerId,
      callId: callId,
    );
  }

  Future<void> _waitForIncomingRuntimeEnrichment() async {
    if (!_state.isIncoming) {
      return;
    }
    await _incomingBootstrapPolicy.waitForAcceptRuntimeEnrichment(
      waitForPendingRuntimeEnrichment: (timeout) {
        return FirebasePushCallbackRegistry.waitForPendingServersApply(
          timeout: timeout,
        );
      },
      log: _log,
    );
  }

  Future<void> _serializeOrchestrationSignalTransition({
    required String label,
    required Future<void> Function() action,
  }) async {
    final completer = Completer<void>();
    final previous = _orchestrationSignalQueue;
    _orchestrationSignalQueue = completer.future;
    try {
      await previous;
      _log('signal-orchestration:start label=$label');
      await action();
    } finally {
      _log('signal-orchestration:done label=$label');
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  }
}
