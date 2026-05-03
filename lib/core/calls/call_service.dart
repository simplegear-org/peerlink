import 'dart:async';
import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';
import 'audio_call_peer.dart';
import 'call_models.dart';

class CallService {
  static const Duration _directConnectAttemptTimeoutDuration = Duration(seconds: 8);
  static const Duration _turnConnectAttemptTimeoutDuration = Duration(seconds: 20);

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
  int _mediaRecoveryAttempt = 0;
  int _statsOffsetSent = 0;
  int _statsOffsetReceived = 0;
  int _lastPeerSentBytes = 0;
  int _lastPeerReceivedBytes = 0;
  int _logSeq = 0;

  CallService({
    required this.selfPeerId,
    required this.signaling,
    required this.turnAllocator,
  });

  Stream<CallState> get stateStream => _stateController.stream;
  CallState get state => _state;

  Future<void> startOutgoingCall(
    String peerId, {
    CallMediaType mediaType = CallMediaType.audio,
  }) async {
    if (_state.isBusy) {
      throw StateError('Call already in progress');
    }

    final callId = DateTime.now().microsecondsSinceEpoch.toString();
    _turnFallbackAttempted = false;
    _localMediaReady = false;
    _remoteMediaReady = false;
    _mediaRecoveryAttempt = 0;
    _statsOffsetSent = 0;
    _statsOffsetReceived = 0;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    _emit(
      CallState(
        phase: CallPhase.outgoingRinging,
        callId: callId,
        peerId: peerId,
        direction: CallDirection.outgoing,
        mediaType: CallMediaType.audio,
        debugStatus: 'Подготавливаем звонок',
      ),
    );

    try {
      await _waitForSignalingReady('исходящий звонок');
    } catch (error) {
      await _failAndReset(error.toString());
      return;
    }

    _emit(
      _state.copyWith(
        debugStatus: 'Отправляем приглашение на звонок',
      ),
    );

    _outgoingTimeout?.cancel();
    _outgoingTimeout = Timer(const Duration(seconds: 30), () {
      if (_state.callId == callId && _state.phase == CallPhase.outgoingRinging) {
        unawaited(_endAndReset('Без ответа'));
      }
    });

    await signaling.sendSignal(peerId, 'call_invite', {
      'callId': callId,
      'signalScope': 'call',
      'mediaType': mediaType.name,
      'videoCapable': true,
    });
    _log('invite:sent peerId=$peerId callId=$callId');
  }

  Future<void> acceptIncomingCall() async {
    final peerId = _state.peerId;
    final callId = _state.callId;
    if (!_state.isIncoming || peerId == null || callId == null) {
      return;
    }

    _emit(_state.copyWith(debugStatus: 'Восстанавливаем signaling перед ответом'));
    _localMediaReady = false;
    _remoteMediaReady = false;
    _mediaRecoveryAttempt = 0;
    _statsOffsetSent = 0;
    _statsOffsetReceived = 0;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    await _waitForSignalingReady('ответ на звонок');

    await signaling.sendSignal(peerId, 'call_accept', {
      'callId': callId,
      'signalScope': 'call',
    });
    _emit(
      _state.copyWith(
        phase: CallPhase.connecting,
        mediaType: CallMediaType.audio,
      ),
    );
    _emit(_state.copyWith(debugStatus: 'Собеседник принял вызов, поднимаем video-capable сессию'));
    _log('accept:sent peerId=$peerId callId=$callId');
  }

  Future<void> rejectIncomingCall() async {
    final peerId = _state.peerId;
    final callId = _state.callId;
    if (!_state.isIncoming || peerId == null || callId == null) {
      return;
    }

    await _waitForSignalingReady('отклонение звонка');
    await signaling.sendSignal(peerId, 'call_reject', {
      'callId': callId,
      'signalScope': 'call',
    });
    await _endAndReset('Отклонен');
  }

  Future<void> endCall() async {
    final peerId = _state.peerId;
    final callId = _state.callId;
    if (peerId != null && callId != null) {
      await _sendControlSignalBestEffort(
        peerId,
        'call_end',
        {
          'callId': callId,
          'signalScope': 'call',
        },
        purpose: 'завершение звонка',
      );
    }
    final status = _state.isActive ? 'Завершен' : 'Отменен';
    await _endAndReset(status);
  }

  Future<void> setMuted(bool muted) async {
    await _peer?.setMuted(muted);
    _emit(_state.copyWith(isMuted: muted));
  }

  Future<void> toggleMuted() {
    return setMuted(!_state.isMuted);
  }

  Future<void> setSpeakerOn(bool enabled) async {
    await _peer?.setSpeakerOn(enabled);
    _emit(_state.copyWith(speakerOn: enabled));
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
      _state.copyWith(
        videoToggleInProgress: true,
        debugStatus: targetEnabled
            ? 'Включаем камеру'
            : 'Выключаем камеру',
      ),
    );
    try {
      final nextMediaType = await peer.toggleVideo();
      _emit(
        _state.copyWith(
          mediaType: nextMediaType,
          localVideoEnabled: nextMediaType == CallMediaType.video,
          videoToggleInProgress: false,
          debugStatus: nextMediaType == CallMediaType.video
              ? 'Камера включена'
              : 'Камера выключена',
        ),
      );
    } catch (error) {
      _emit(
        _state.copyWith(
          videoToggleInProgress: false,
          debugStatus: 'Не удалось переключить камеру',
          error: error.toString(),
        ),
      );
    }
  }

  Future<void> flipCamera() async {
    await _peer?.flipCamera();
  }

  Future<void> handleControlSignal(SignalingMessage message) async {
    final peerId = message.fromPeerId;
    final data = message.data;
    final callId = data['callId']?.toString();
    if (callId == null || callId.isEmpty) {
      return;
    }

    switch (message.type) {
      case 'call_invite':
        if (_state.isBusy) {
          await signaling.sendSignal(peerId, 'call_busy', {
            'callId': callId,
            'signalScope': 'call',
          });
          return;
        }
        _emit(
          CallState(
            phase: CallPhase.incomingRinging,
            callId: callId,
            peerId: peerId,
            direction: CallDirection.incoming,
            mediaType: CallMediaType.audio,
            debugStatus: 'Входящий звонок',
          ),
        );
        _log('invite:recv peerId=$peerId callId=$callId');
        return;
      case 'call_accept':
        if (_state.phase != CallPhase.outgoingRinging ||
            _state.callId != callId ||
            _state.peerId != peerId) {
          return;
        }
        _outgoingTimeout?.cancel();
        TransportMode preferredMode;
        try {
          preferredMode = await _preferredInitialMode();
        } catch (error) {
          await _failAndReset(error.toString());
          return;
        }
        _emit(
          _state.copyWith(
            phase: CallPhase.connecting,
            mediaType: CallMediaType.audio,
            debugStatus: 'Собеседник принял вызов, используем TURN',
          ),
        );
        await _startPeerConnection(
          peerId: peerId,
          callId: callId,
          initialMode: preferredMode,
        );
        return;
      case 'call_reject':
        if (_state.callId == callId && _state.peerId == peerId) {
          await _endAndReset('Отклонен');
        }
        return;
      case 'call_busy':
        if (_state.callId == callId && _state.peerId == peerId) {
          await _endAndReset('Занят');
        }
        return;
      case 'call_end':
        if (_state.callId == callId && _state.peerId == peerId) {
          if (_state.isActive) {
            await _endAndReset('Завершен');
          } else if (_state.isIncoming) {
            await _endAndReset('Пропущен');
          } else {
            await _endAndReset('Без ответа');
          }
        }
        return;
      case 'call_media_ready':
        if (_state.callId == callId && _state.peerId == peerId) {
          _log('mediaReady:recv peerId=$peerId callId=$callId');
          _remoteMediaReady = true;
          _mediaReadyTimeout?.cancel();
          _updateActiveState();
          _armMediaReadyTimeout();
        } else {
          _log(
            'mediaReady:ignored peerId=$peerId callId=$callId '
            'currentPeerId=${_state.peerId} currentCallId=${_state.callId}',
          );
        }
        return;
      case 'call_video_state':
        if (_state.callId != callId || _state.peerId != peerId) {
          return;
        }
        final enabled = message.data['enabled'] == true;
        final version = message.data['version'] is int
            ? message.data['version'] as int
            : int.tryParse(message.data['version']?.toString() ?? '') ?? 0;
        _emit(
          _state.copyWith(
            remoteVideoEnabled: enabled,
            remoteVideoAvailable: enabled
                ? _streamHasVideo(_state.remoteStream)
                : false,
            remoteVideoActive: enabled ? _state.remoteVideoActive : false,
            debugStatus: enabled
                ? 'Собеседник включает видео'
                : 'Собеседник выключил видео',
          ),
        );
        await _peer?.handleRemoteVideoState(
          enabled: enabled,
          version: version,
          peerId: peerId,
          callId: callId,
        );
        return;
      case 'call_video_state_ack':
        if (_state.callId != callId || _state.peerId != peerId) {
          return;
        }
        final enabled = message.data['enabled'] == true;
        final version = message.data['version'] is int
            ? message.data['version'] as int
            : int.tryParse(message.data['version']?.toString() ?? '') ?? 0;
        _peer?.handleVideoStateAck(enabled: enabled, version: version);
        return;
      case 'call_video_flow_ack':
        if (_state.callId != callId || _state.peerId != peerId) {
          return;
        }
        final version = message.data['version'] is int
            ? message.data['version'] as int
            : int.tryParse(message.data['version']?.toString() ?? '') ?? 0;
        _peer?.handleVideoFlowAck(version: version);
        return;
    }
  }

  Future<void> handleMediaSignal(SignalingMessage message) async {
    final peerId = message.fromPeerId;
    final callId = message.data['callId']?.toString();
    if (callId == null || callId.isEmpty) {
      return;
    }

    if (_state.peerId != peerId || _state.callId != callId) {
      if (!_state.isIncoming) {
        return;
      }
      _emit(
        _state.copyWith(
          phase: CallPhase.connecting,
          peerId: peerId,
          callId: callId,
          debugStatus: 'Получили media-signal, поднимаем аудиоканал',
        ),
      );
    }

    final peer = await _ensurePeerForIncomingSignal(
      peerId: peerId,
      callId: callId,
    );
    await peer?.handleSignal(message);
  }

  Future<void> dispose() async {
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
    try {
      final peer = await _ensurePeerForIncomingSignal(
        peerId: peerId,
        callId: callId,
      );
      if (peer == null || !_matchesCurrentCall(peerId, callId)) {
        return;
      }
      try {
        _emit(
          _state.copyWith(
            phase: CallPhase.connecting,
            transportMode: initialMode,
            transportLabel: _transportLabelFor(initialMode),
            debugStatus: initialMode == TransportMode.turn
                ? 'Текущая сеть mobile, сразу используем TURN'
                : 'Пробуем прямое соединение (STUN/direct)',
          ),
        );
        await peer.startOutgoing(
          peerId: peerId,
          callId: callId,
          mode: initialMode,
          mediaType: CallMediaType.audio,
        );
        _armConnectAttemptTimeout(
          peerId: peerId,
          callId: callId,
          mode: initialMode,
        );
      } catch (error) {
        _log('${initialMode.name} failed: $error');
        if (initialMode == TransportMode.direct) {
          await _retryViaTurn(
            peerId: peerId,
            callId: callId,
            reason: 'Direct не удался: $error',
          );
          return;
        }
        rethrow;
      }
    } catch (error) {
      await _failAndReset('Не удалось установить звонок: $error');
    }
  }

  Future<TransportMode> _preferredInitialMode() async {
    if (!await _hasTurnAvailable()) {
      _log('networkPolicy: TURN unavailable, cannot start call');
      throw StateError('TURN is not available');
    }

    try {
      final results = await _connectivity.checkConnectivity();
      _log(
        'networkPolicy: connectivity=$results preferredMode=${TransportMode.turn.name}',
      );
    } catch (error) {
      _log('networkPolicy: connectivity check failed error=$error preferredMode=turn');
    }
    return TransportMode.turn;
  }

  Future<bool> _hasTurnAvailable() async {
    try {
      await turnAllocator?.refreshSelectionIfNeeded();
    } catch (error) {
      _log('networkPolicy: TURN refresh failed error=$error');
    }
    final available = turnAllocator?.allocate() != null;
    _log('networkPolicy: TURN available=$available');
    return available;
  }

  Future<AudioCallPeer?> _ensurePeerForIncomingSignal({
    required String peerId,
    required String callId,
  }) async {
    if (_peer != null) {
      return _peer;
    }

    if (!_matchesCurrentCall(peerId, callId)) {
      return null;
    }

    late final AudioCallPeer peer;
    peer = AudioCallPeer(
      signaling: signaling,
      turnAllocator: turnAllocator,
      onConnected: (mode) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _connectAttemptTimeout?.cancel();
        _emit(
          _state.copyWith(
            transportMode: mode,
            transportLabel: _transportLabelFor(mode),
            debugStatus: mode == TransportMode.turn
                ? 'Транспорт через TURN готов, аудио уже поднимается, видеоканал подготовлен'
                : 'Прямой транспорт готов, аудио уже поднимается, видеоканал подготовлен',
          ),
        );
        _updateActiveState();
        _armMediaReadyTimeout();
      },
      onMediaFlow: () async {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _localMediaReady = true;
        _updateActiveState();
        final currentPeerId = _state.peerId;
        final currentCallId = _state.callId;
        if (currentPeerId != null && currentCallId != null) {
          await _sendControlSignalBestEffort(
            currentPeerId,
            'call_media_ready',
            {
              'callId': currentCallId,
              'signalScope': 'call',
            },
            purpose: 'подтверждение аудио',
          );
          _armMediaReadyTimeout();
        }
      },
      onStats: ({required int sentBytes, required int receivedBytes}) {
        if (!_isCurrentPeerInstance(peer, peerId, callId) || _state.isIdle) {
          return;
        }
        if (sentBytes < _lastPeerSentBytes) {
          _statsOffsetSent += _lastPeerSentBytes;
        }
        if (receivedBytes < _lastPeerReceivedBytes) {
          _statsOffsetReceived += _lastPeerReceivedBytes;
        }
        _lastPeerSentBytes = sentBytes;
        _lastPeerReceivedBytes = receivedBytes;
        final totalSent = _statsOffsetSent + sentBytes;
        final totalReceived = _statsOffsetReceived + receivedBytes;
        _emit(
          _state.copyWith(
            bytesSent: totalSent,
            bytesReceived: totalReceived,
          ),
        );
      },
      onMediaTypeChanged: (mediaType) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _emit(
          _state.copyWith(
            mediaType: mediaType,
            localVideoEnabled: mediaType == CallMediaType.video,
          ),
        );
      },
      onLocalStream: (stream) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _emit(
          _state.copyWith(
            localStream: stream,
            localVideoAvailable: _streamHasVideo(stream),
            isFrontCamera: _peer?.isFrontCamera ?? _state.isFrontCamera,
          ),
        );
      },
      onRemoteStream: (stream) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        final remoteVideoAvailable = _streamHasVideo(stream);
        _emit(
          _state.copyWith(
            remoteStream: stream,
            remoteVideoAvailable: remoteVideoAvailable,
            remoteVideoActive: remoteVideoAvailable && _state.remoteVideoEnabled
                ? true
                : (remoteVideoAvailable ? _state.remoteVideoActive : false),
          ),
        );
      },
      onRemoteVideoFlowChanged: (active) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _emit(
          _state.copyWith(
            remoteVideoActive: active,
            debugStatus: active
                ? 'Собеседник передает видео'
                : (_state.remoteVideoEnabled
                    ? 'Ожидаем видеопоток'
                    : _state.debugStatus),
          ),
        );
      },
      onRemoteVideoTrackChanged: (trackId) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _emit(
          _state.copyWith(
            remoteVideoTrackId: trackId,
            clearRemoteVideoTrackId: trackId == null,
          ),
        );
      },
      onVideoCodecChanged: (codec) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        _emit(
          _state.copyWith(
            videoCodec: codec,
            clearVideoCodec: codec == null || codec.isEmpty,
          ),
        );
      },
      onError: (error) {
        if (!_isCurrentPeerInstance(peer, peerId, callId)) {
          return;
        }
        if (_state.phase != CallPhase.active &&
            _state.transportMode != TransportMode.turn &&
            !_turnFallbackAttempted &&
            turnAllocator?.allocate() != null) {
          unawaited(
            _retryViaTurn(
              peerId: peerId,
              callId: callId,
              reason: error,
            ),
          );
          return;
        }
        unawaited(_failAndReset(error));
      },
    );

    _peer = peer;
    _statsOffsetSent = _state.bytesSent;
    _statsOffsetReceived = _state.bytesReceived;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;

    await peer.setMuted(_state.isMuted);
    await peer.setSpeakerOn(_state.speakerOn);
    if (!_matchesCurrentCall(peerId, callId)) {
      if (identical(_peer, peer)) {
        _peer = null;
      }
      await peer.dispose();
      return null;
    }
    _emit(
      _state.copyWith(
        phase: CallPhase.connecting,
        peerId: peerId,
        callId: callId,
        debugStatus: 'Готовим WebRTC сессию аудио + видео',
        localVideoEnabled: false,
        localVideoAvailable: false,
        remoteVideoEnabled: false,
        remoteVideoAvailable: false,
        remoteVideoActive: false,
        clearRemoteVideoTrackId: true,
        clearVideoCodec: true,
        videoToggleInProgress: false,
        localStream: null,
        remoteStream: null,
      ),
    );
    return peer;
  }

  bool _isCurrentPeerInstance(
    AudioCallPeer peer,
    String peerId,
    String callId,
  ) {
    return identical(_peer, peer) && _matchesCurrentCall(peerId, callId);
  }

  Future<void> _failAndReset(String error) async {
    final peerId = _state.peerId;
    final callId = _state.callId;
    if (peerId != null && callId != null) {
      await _sendControlSignalBestEffort(
        peerId,
        'call_end',
        {
          'callId': callId,
          'signalScope': 'call',
          'reason': error,
        },
        purpose: 'сбой звонка',
      );
    }
    _emit(
      _state.copyWith(
        phase: CallPhase.failed,
        error: error,
        debugStatus: error,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _resetToIdle();
  }

  Future<void> _endAndReset(String status) async {
    _emit(
      _state.copyWith(
        phase: CallPhase.ended,
        debugStatus: status,
        clearError: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await _resetToIdle();
  }

  Future<void> _resetToIdle() async {
    _outgoingTimeout?.cancel();
    _outgoingTimeout = null;
    _connectAttemptTimeout?.cancel();
    _connectAttemptTimeout = null;
    _mediaReadyTimeout?.cancel();
    _mediaReadyTimeout = null;
    _turnFallbackAttempted = false;
    _localMediaReady = false;
    _remoteMediaReady = false;
    _mediaRecoveryAttempt = 0;
    _statsOffsetSent = 0;
    _statsOffsetReceived = 0;
    _lastPeerSentBytes = 0;
    _lastPeerReceivedBytes = 0;
    await _peer?.dispose();
    _peer = null;
    _emit(
      const CallState(
        phase: CallPhase.idle,
      ),
    );
  }

  void _emit(CallState next) {
    _state = next;
    _stateController.add(next);
    _log(
      'state phase=${next.phase.name} peerId=${next.peerId} mode=${next.transportMode?.name}',
    );
  }

  void _log(String message) {
    AppFileLogger.log('[call][$selfPeerId][${_logSeq++}] $message');
  }

  bool _streamHasVideo(MediaStream? stream) {
    return stream?.getVideoTracks().isNotEmpty ?? false;
  }

  void _armConnectAttemptTimeout({
    required String peerId,
    required String callId,
    required TransportMode mode,
  }) {
    _connectAttemptTimeout?.cancel();
    final timeout = _timeoutForMode(mode);
    _connectAttemptTimeout = Timer(timeout, () {
      if (_state.peerId != peerId ||
          _state.callId != callId ||
          _state.phase == CallPhase.active) {
        return;
      }

      if (mode == TransportMode.direct &&
          !_turnFallbackAttempted &&
          turnAllocator?.allocate() != null) {
        _log('connect timeout: switching to TURN');
        unawaited(
          _retryViaTurn(
            peerId: peerId,
            callId: callId,
            reason: 'Direct timeout',
          ),
        );
        return;
      }

      unawaited(_failAndReset('Не удалось установить $mode соединение'));
    });
    _log(
      'connect timeout armed mode=${mode.name} timeoutMs=${timeout.inMilliseconds}',
    );
  }

  Future<void> _retryViaTurn({
    required String peerId,
    required String callId,
    required String reason,
  }) async {
    if (_turnFallbackAttempted) {
      return;
    }
    _turnFallbackAttempted = true;
    _connectAttemptTimeout?.cancel();
    _mediaReadyTimeout?.cancel();
    _mediaReadyTimeout = null;
    _localMediaReady = false;
    _remoteMediaReady = false;
    _mediaRecoveryAttempt = 0;

    if (!await _hasTurnAvailable()) {
      _emit(
        _state.copyWith(
          debugStatus: 'TURN недоступен после ошибки: $reason',
        ),
      );
      await _failAndReset('TURN недоступен');
      return;
    }

    _log('retryViaTurn reason=$reason');
    _emit(
      _state.copyWith(
        phase: CallPhase.connecting,
        transportMode: TransportMode.turn,
        transportLabel: 'TURN relay',
        debugStatus: 'Direct не удался, переключаемся на TURN',
      ),
    );

    await _peer?.dispose();
    _peer = null;
    final peer = await _ensurePeerForIncomingSignal(
      peerId: peerId,
      callId: callId,
    );
    if (peer == null || !_matchesCurrentCall(peerId, callId)) {
      return;
    }
    await peer.startOutgoing(
      peerId: peerId,
      callId: callId,
      mode: TransportMode.turn,
      mediaType: CallMediaType.audio,
    );
    _armConnectAttemptTimeout(
      peerId: peerId,
      callId: callId,
      mode: TransportMode.turn,
    );
  }

  String _transportLabelFor(TransportMode mode) {
    switch (mode) {
      case TransportMode.direct:
        return 'Прямое соединение';
      case TransportMode.turn:
        return 'TURN relay';
    }
  }

  Duration _timeoutForMode(TransportMode mode) {
    switch (mode) {
      case TransportMode.direct:
        return _directConnectAttemptTimeoutDuration;
      case TransportMode.turn:
        return _turnConnectAttemptTimeoutDuration;
    }
  }

  Future<void> _waitForSignalingReady(String purpose) async {
    if (signaling.connectionStatus == SignalingConnectionStatus.connected) {
      return;
    }

    _log('waitForSignaling:start purpose=$purpose status=${signaling.connectionStatus}');
      _emit(
        _state.copyWith(
          debugStatus: 'Ожидаем восстановление signaling',
      ),
    );

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

  Future<void> _sendControlSignalBestEffort(
    String peerId,
    String type,
    Map<String, dynamic> data, {
    required String purpose,
  }) async {
    try {
      await _waitForSignalingReady(purpose);
      await signaling.sendSignal(peerId, type, data);
    } catch (error, stackTrace) {
      _log('controlSignal:skip type=$type purpose=$purpose error=$error');
      AppFileLogger.log(
        '[call] controlSignal:skip type=$type purpose=$purpose error=$error',
        name: 'call',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _updateActiveState() {
    if (_state.isIdle) {
      return;
    }
    if (_localMediaReady && _remoteMediaReady) {
      if (_state.phase != CallPhase.active) {
        _mediaReadyTimeout?.cancel();
        _mediaReadyTimeout = null;
        _emit(
          _state.copyWith(
            phase: CallPhase.active,
            debugStatus: _state.transportMode == TransportMode.turn
                ? 'Звонок через TURN активен, видеоканал готов'
                : 'Звонок активен, видеоканал готов',
            connectedAt: DateTime.now(),
          ),
        );
      }
      return;
    }
    final waitingFor = <String>[];
    if (!_localMediaReady) {
      waitingFor.add('локальный входящий аудиопоток');
    }
    if (!_remoteMediaReady) {
      waitingFor.add('подтверждение второй стороны');
    }
    _emit(
      _state.copyWith(
        phase: CallPhase.connecting,
        debugStatus: 'Ждем ${waitingFor.join(' и ')}',
      ),
    );
  }

  void _armMediaReadyTimeout() {
    if (_state.isActive || (_localMediaReady && _remoteMediaReady)) {
      return;
    }
    final expectedPeerId = _state.peerId;
    final expectedCallId = _state.callId;
    final expectedPeer = _peer;
    if (expectedPeerId == null || expectedCallId == null || expectedPeer == null) {
      return;
    }
    _mediaReadyTimeout?.cancel();
    _mediaReadyTimeout = Timer(const Duration(seconds: 6), () {
      if (!identical(_peer, expectedPeer) ||
          !_matchesCurrentCall(expectedPeerId, expectedCallId)) {
        return;
      }
      if (_state.isActive || (_localMediaReady && _remoteMediaReady)) {
        return;
      }
      _mediaRecoveryAttempt += 1;
      final attempt = _mediaRecoveryAttempt;
      if (attempt == 1) {
        _log(
          'mediaReady timeout: restarting ICE local=$_localMediaReady remote=$_remoteMediaReady',
        );
        unawaited(expectedPeer.restartIce('Remote media confirmation timeout'));
        _armMediaReadyTimeout();
        return;
      }
      if (attempt == 2) {
        _log(
          'mediaReady timeout: forcing renegotiation local=$_localMediaReady remote=$_remoteMediaReady',
        );
        unawaited(
          expectedPeer.forceRenegotiation('Audio flow missing after ICE restart'),
        );
        _armMediaReadyTimeout();
        return;
      }
      _log(
        'mediaReady timeout: giving up local=$_localMediaReady remote=$_remoteMediaReady',
      );
      unawaited(_failAndReset('Не удалось восстановить двусторонний аудиоканал'));
    });
  }

  bool _matchesCurrentCall(String peerId, String callId) {
    return !_state.isIdle && _state.peerId == peerId && _state.callId == callId;
  }
}
