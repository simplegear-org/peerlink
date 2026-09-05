// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// SPDX-License-Identifier: MPL-2.0

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../runtime/runtime_servers_merge_orchestrator.dart';
import '../runtime/peer_access_control_service.dart';
import '../turn/turn_allocator.dart';
import 'call_audio_mute_sender.dart';
import 'audio_call_peer.dart';
import 'call_control_transport.dart';
import 'call_control_signal_helper.dart';
import 'call_control_reliable_payload.dart';
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
  static const Duration _outgoingInviteRetryInterval = Duration(seconds: 4);
  static const Duration _controlRetryInterval = Duration(seconds: 3);
  static const int _controlRetryMaxAttempts = 8;

  final String selfPeerId;
  final SignalingService signaling;
  final TurnAllocator? turnAllocator;
  final IncomingInteractionDecision Function(String peerId)?
  incomingCallAccessDecision;
  final IncomingInteractionDecision Function(String peerId)?
  outgoingCallAccessDecision;
  final Connectivity _connectivity = Connectivity();

  final StreamController<CallState> _stateController =
      StreamController<CallState>.broadcast();

  CallState _state = CallState.idle;
  AudioCallPeer? _peer;
  Timer? _outgoingTimeout;
  Timer? _outgoingInviteRetryTimer;
  Timer? _incomingAcceptRetryTimer;
  Timer? _terminalControlRetryTimer;
  bool _outgoingInviteRetryInFlight = false;
  final CallRuntimeTracking _runtimeTracking = CallRuntimeTracking();
  CallSessionEpoch _callEpoch = CallSessionEpoch.initial();
  FutureOr<Map<String, dynamic>> Function(String peerId)
  _buildCallInviteMetadata = (_) => const <String, dynamic>{};
  CallControlReliableSender? _reliableControlSender;
  final CallControlTransport? _callControlTransport;
  static const Duration _pendingRemoteEndTtl = Duration(minutes: 2);
  final RuntimeServersMergeOrchestrator? _serversMergeOrchestrator;
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
  static const CallControlReliablePayload _reliablePayload =
      CallControlReliablePayload();
  late final CallRuntimeLogger _logger;

  CallService({
    required this.selfPeerId,
    required this.signaling,
    required this.turnAllocator,
    RuntimeServersMergeOrchestrator? serversMergeOrchestrator,
    CallControlTransport? callControlTransport,
    this.incomingCallAccessDecision,
    this.outgoingCallAccessDecision,
  }) : _serversMergeOrchestrator = serversMergeOrchestrator,
       _callControlTransport = callControlTransport {
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
        _cancelOutgoingInviteRetry();
        _cancelIncomingAcceptRetry();
      },
      cancelConnectAttemptTimeout: () {
        _connectionOrchestrator.cancelConnectAttemptTimeout();
      },
      clearMediaReadyTimeout: _mediaReadinessController.clearMediaReadyTimeout,
      resetRuntimeTracking: _resetRuntimeTracking,
      beginRecovery: _mediaReadinessController.beginRecovery,
      sendDetachedSignal: _sendDetachedControl,
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
    callControlTransport?.setIncomingHandler(_handleIncomingReliableControl);
  }

  Stream<CallState> get stateStream => _stateController.stream;
  CallState get state => _state;

  void setCallInviteMetadataBuilder(
    FutureOr<Map<String, dynamic>> Function(String peerId) builder,
  ) {
    _buildCallInviteMetadata = builder;
  }

  void setReliableControlSender(CallControlReliableSender? sender) {
    _reliableControlSender = sender;
  }

  Future<void> startOutgoingCall(
    String peerId, {
    CallMediaType mediaType = CallMediaType.audio,
    String? callId,
  }) async {
    final decision = outgoingCallAccessDecision?.call(peerId);
    if (decision != null && decision != IncomingInteractionDecision.allow) {
      _log('outgoing:blocked access=${decision.name} peerId=$peerId');
      throw StateError('Peer is blocked');
    }
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
    if (_state.phase == CallPhase.outgoingRinging &&
        _state.peerId == peerId &&
        _state.callId != null) {
      _sendReliableControl(
        peerId: peerId,
        type: 'call_invite',
        callId: _state.callId!,
        data: _outgoingInvitePayload(
          callId: _state.callId!,
          mediaType: mediaType,
          inviteMetadata: inviteMetadata,
        ),
        purpose: 'резервное приглашение звонка',
      );
    }
    _startOutgoingInviteRetry(inviteMetadata);
  }

  Future<void> _applyIncomingInviteRuntimeMetadata(
    Map<String, dynamic> data,
  ) async {
    await _serversMergeOrchestrator?.applyIfPresent(
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
    final decision = incomingCallAccessDecision?.call(peerId);
    if (decision != null && decision != IncomingInteractionDecision.allow) {
      _log(
        'pushInvite:drop access=${decision.name} peerId=$peerId '
        'callId=$callId',
      );
      return;
    }
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
    final incomingState = _state;
    final peerId = incomingState.peerId;
    final callId = incomingState.callId;
    if (incomingState.isIncoming && peerId != null && callId != null) {
      _sendReliableControl(
        peerId: peerId,
        type: 'call_accept',
        callId: callId,
        data: _reliablePayload.terminalData(callId: callId),
        purpose: 'резервный ответ на звонок',
      );
    }
    if (incomingState.isIncoming &&
        peerId != null &&
        callId != null &&
        signaling.connectionStatus != SignalingConnectionStatus.connected) {
      _emit(
        incomingState.copyWith(
          debugStatus: 'Подготавливаем runtime-конфиг перед ответом',
        ),
      );
      await _waitForIncomingRuntimeEnrichment();
      _resetRuntimeTracking();
      final connectingState = incomingState.copyWith(
        phase: CallPhase.connecting,
        mediaType: _activeMediaType,
      );
      _emit(connectingState);
      _emit(
        connectingState.copyWith(
          debugStatus:
              'Ответ отправлен резервным каналом, ждем восстановление signaling',
        ),
      );
      _startIncomingAcceptRetry(peerId: peerId, callId: callId);
      _log('accept:reliable queued peerId=$peerId callId=$callId');
      return;
    }
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
    if (incomingState.isIncoming && peerId != null && callId != null) {
      _startIncomingAcceptRetry(peerId: peerId, callId: callId);
    }
  }

  Future<void> rejectIncomingCall() async {
    final incomingState = _state;
    await _commandHelper.rejectIncomingCall(
      currentState: _state,
      sendDetachedSignal: _controlSignalHelper.sendDetached,
      endAndReset: _terminalLifecycleController.endAndReset,
    );
    final peerId = incomingState.peerId;
    final callId = incomingState.callId;
    if (incomingState.isIncoming && peerId != null && callId != null) {
      _sendReliableControl(
        peerId: peerId,
        type: 'call_reject',
        callId: callId,
        data: _reliablePayload.terminalData(callId: callId),
        purpose: 'резервное отклонение звонка',
      );
      _startTerminalControlRetry(
        peerId: peerId,
        callId: callId,
        type: 'call_reject',
        purpose: 'повтор отклонения звонка',
      );
    }
  }

  Future<void> endCall() async {
    final stateBeforeEnd = _state;
    await _commandHelper.endCall(
      currentState: _state,
      sendDetachedSignal: _controlSignalHelper.sendDetached,
      endAndReset: _terminalLifecycleController.endAndReset,
    );
    final peerId = stateBeforeEnd.peerId;
    final callId = stateBeforeEnd.callId;
    if (!stateBeforeEnd.isIdle && peerId != null && callId != null) {
      _sendReliableControl(
        peerId: peerId,
        type: 'call_end',
        callId: callId,
        data: _reliablePayload.terminalData(callId: callId),
        purpose: 'резервное завершение звонка',
      );
      _startTerminalControlRetry(
        peerId: peerId,
        callId: callId,
        type: 'call_end',
        purpose: 'повтор завершения звонка',
      );
    }
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
    if (message.type == 'call_invite') {
      final decision = incomingCallAccessDecision?.call(message.fromPeerId);
      if (decision != null && decision != IncomingInteractionDecision.allow) {
        _log(
          'invite:drop access=${decision.name} peerId=${message.fromPeerId} '
          'callId=${message.data['callId']}',
        );
        return;
      }
    }
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

  Future<bool> handleReliableControlPayload({
    required String fromPeerId,
    required String text,
  }) async {
    final message = _reliablePayload.decode(
      fromPeerId: fromPeerId,
      toPeerId: selfPeerId,
      text: text,
    );
    if (message == null) {
      return false;
    }
    _log(
      'reliableControl:recv type=${message.type} peerId=$fromPeerId '
      'callId=${message.data['callId']}',
    );
    await handleControlSignal(message);
    return true;
  }

  Future<bool> _handleIncomingReliableControl(CallControlPayload payload) {
    return handleReliableControlPayload(
      fromPeerId: payload.fromPeerId,
      text: payload.text,
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
        if (message.type == 'offer' &&
            _state.peerId == peerId &&
            _state.callId == callId) {
          _cancelIncomingAcceptRetry();
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
    _cancelOutgoingInviteRetry();
    _cancelIncomingAcceptRetry();
    _cancelTerminalControlRetry();
    _connectionOrchestrator.dispose();
    _callControlTransport?.setIncomingHandler(null);
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
    if (!next.isIdle &&
        next.callId != null &&
        (previous.callId == null || previous.callId != next.callId)) {
      _cancelTerminalControlRetry();
    }
    if (previous.phase == CallPhase.outgoingRinging &&
        next.phase != CallPhase.outgoingRinging) {
      _cancelOutgoingInviteRetry();
    }
    if (previous.phase == CallPhase.connecting &&
        previous.direction == CallDirection.incoming &&
        next.phase != CallPhase.connecting) {
      _cancelIncomingAcceptRetry();
    }
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

  void _startOutgoingInviteRetry(Map<String, dynamic> inviteMetadata) {
    _cancelOutgoingInviteRetry();
    final peerId = _state.peerId;
    final callId = _state.callId;
    if (_state.phase != CallPhase.outgoingRinging ||
        peerId == null ||
        callId == null) {
      return;
    }
    final mediaType = _state.mediaType;
    final metadata = Map<String, dynamic>.from(inviteMetadata);
    _outgoingInviteRetryTimer = Timer.periodic(
      _outgoingInviteRetryInterval,
      (_) => unawaited(
        _sendOutgoingInviteRetry(
          peerId: peerId,
          callId: callId,
          mediaType: mediaType,
          inviteMetadata: metadata,
        ),
      ),
    );
  }

  void _cancelOutgoingInviteRetry() {
    _outgoingInviteRetryTimer?.cancel();
    _outgoingInviteRetryTimer = null;
  }

  void _startIncomingAcceptRetry({
    required String peerId,
    required String callId,
  }) {
    _cancelIncomingAcceptRetry();
    var attempts = 0;
    _incomingAcceptRetryTimer = Timer.periodic(_controlRetryInterval, (timer) {
      if (_state.peerId != peerId ||
          _state.callId != callId ||
          _state.direction != CallDirection.incoming ||
          _state.phase != CallPhase.connecting) {
        timer.cancel();
        if (identical(_incomingAcceptRetryTimer, timer)) {
          _incomingAcceptRetryTimer = null;
        }
        return;
      }
      attempts += 1;
      if (attempts > _controlRetryMaxAttempts) {
        timer.cancel();
        if (identical(_incomingAcceptRetryTimer, timer)) {
          _incomingAcceptRetryTimer = null;
        }
        return;
      }
      _controlSignalHelper.sendDetached(
        peerId,
        'call_accept',
        <String, dynamic>{'callId': callId, 'signalScope': 'call'},
        purpose: 'повтор ответа на звонок',
      );
      _sendReliableControl(
        peerId: peerId,
        type: 'call_accept',
        callId: callId,
        data: _reliablePayload.terminalData(callId: callId),
        purpose: 'резервный повтор ответа на звонок',
      );
      _log('accept:retry peerId=$peerId callId=$callId attempt=$attempts');
    });
  }

  void _cancelIncomingAcceptRetry() {
    _incomingAcceptRetryTimer?.cancel();
    _incomingAcceptRetryTimer = null;
  }

  void _startTerminalControlRetry({
    required String peerId,
    required String callId,
    required String type,
    required String purpose,
  }) {
    _cancelTerminalControlRetry();
    var attempts = 0;
    _terminalControlRetryTimer = Timer.periodic(_controlRetryInterval, (timer) {
      attempts += 1;
      if (attempts > _controlRetryMaxAttempts) {
        timer.cancel();
        if (identical(_terminalControlRetryTimer, timer)) {
          _terminalControlRetryTimer = null;
        }
        return;
      }
      _controlSignalHelper.sendDetached(peerId, type, <String, dynamic>{
        'callId': callId,
        'signalScope': 'call',
      }, purpose: purpose);
      _sendReliableControl(
        peerId: peerId,
        type: type,
        callId: callId,
        data: _reliablePayload.terminalData(callId: callId),
        purpose: 'резервный $purpose',
      );
      _log('$type:retry peerId=$peerId callId=$callId attempt=$attempts');
    });
  }

  void _cancelTerminalControlRetry() {
    _terminalControlRetryTimer?.cancel();
    _terminalControlRetryTimer = null;
  }

  Future<void> _sendOutgoingInviteRetry({
    required String peerId,
    required String callId,
    required CallMediaType mediaType,
    required Map<String, dynamic> inviteMetadata,
  }) async {
    if (_outgoingInviteRetryInFlight) {
      return;
    }
    _outgoingInviteRetryInFlight = true;
    try {
      await _controlSignalHelper.waitForSignalingReady(
        'повтор приглашения звонка',
      );
      if (_state.phase != CallPhase.outgoingRinging ||
          _state.peerId != peerId ||
          _state.callId != callId) {
        return;
      }
      await signaling.sendSignal(
        peerId,
        'call_invite',
        _outgoingInvitePayload(
          callId: callId,
          mediaType: mediaType,
          inviteMetadata: inviteMetadata,
        ),
      );
      _sendReliableControl(
        peerId: peerId,
        type: 'call_invite',
        callId: callId,
        data: _outgoingInvitePayload(
          callId: callId,
          mediaType: mediaType,
          inviteMetadata: inviteMetadata,
        ),
        purpose: 'резервный повтор приглашения звонка',
      );
      _log('invite:retry peerId=$peerId callId=$callId');
    } catch (error, stackTrace) {
      _logger.log(
        'invite:retry failed peerId=$peerId callId=$callId error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _outgoingInviteRetryInFlight = false;
    }
  }

  Map<String, dynamic> _outgoingInvitePayload({
    required String callId,
    required CallMediaType mediaType,
    required Map<String, dynamic> inviteMetadata,
  }) {
    return _reliablePayload.inviteData(
      callId: callId,
      mediaType: mediaType,
      inviteMetadata: inviteMetadata,
    );
  }

  void _sendReliableControl({
    required String peerId,
    required String type,
    required String callId,
    required Map<String, dynamic> data,
    required String purpose,
  }) {
    final transport = _callControlTransport;
    final sender = _reliableControlSender;
    if (!CallControlReliablePayload.criticalTypes.contains(type) ||
        (transport == null && sender == null)) {
      return;
    }
    final text = _reliablePayload.encode(
      controlType: type,
      callId: callId,
      data: data,
    );
    unawaited(
      (transport?.send(peerId, text) ?? sender!(peerId, text))
          .then((_) {
            _log(
              '$type:reliable sent peerId=$peerId callId=$callId purpose=$purpose',
            );
          })
          .catchError((Object error, StackTrace stackTrace) {
            _logger.log(
              '$type:reliable failed peerId=$peerId callId=$callId purpose=$purpose error=$error',
              error: error,
              stackTrace: stackTrace,
            );
          }),
    );
  }

  void _sendDetachedControl(
    String peerId,
    String type,
    Map<String, dynamic> data, {
    required String purpose,
  }) {
    _controlSignalHelper.sendDetached(peerId, type, data, purpose: purpose);
    final callId = (data['callId'] as String? ?? '').trim();
    if (callId.isEmpty) {
      return;
    }
    _sendReliableControl(
      peerId: peerId,
      type: type,
      callId: callId,
      data: data,
      purpose: 'резервный $purpose',
    );
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
