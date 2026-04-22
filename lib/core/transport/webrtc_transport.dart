import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../signaling/signaling_message.dart';
import '../signaling/signaling_service.dart';
import '../turn/turn_allocator.dart';
import '../turn/turn_credentials.dart';
import 'transport.dart';
import 'transport_mode.dart';

/// WebRTC-транспорт с обменом signaling сообщениями и DataChannel.
class WebRtcTransport implements Transport {
  @override
  final TransportMode mode;

  final TurnAllocator? turnAllocator;
  final SignalingService _signaling;
  final void Function(Uint8List data)? _onIncomingMessage;
  final void Function(String peerId, TransportMode mode)? _onConnected;
  final bool Function()? _canSignal;

  RTCPeerConnection? _peer;
  RTCDataChannel? _dataChannel;
  final List<_PendingOutbound> _pendingOutbound = [];
  StreamSubscription<SignalingMessage>? _signalSubscription;
  String? _remotePeerId;
  Completer<void>? _connectCompleter;

  bool _healthy = false;
  bool _connectedNotified = false;
  bool _iceConnected = false;
  bool _dataChannelReady = false;

  TurnCredentials? _activeTurn;
  int _logSeq = 0;
  final List<RTCIceCandidate> _pendingIce = [];
  Timer? _answerRetryTimer;
  int _answerRetryAttempts = 0;
  Map<String, dynamic>? _lastAnswerPayload;
  String? _lastAnswerPeerId;
  Timer? _offerRetryTimer;
  int _offerRetryAttempts = 0;
  Map<String, dynamic>? _lastOfferPayload;
  String? _lastOfferPeerId;
  bool _remoteDescriptionSet = false;
  final List<Map<String, dynamic>> _localIceBuffer = [];

  WebRtcTransport({
    required this.mode,
    this.turnAllocator,
    required SignalingService signaling,
    void Function(Uint8List data)? onIncomingMessage,
    void Function(String peerId, TransportMode mode)? onConnected,
    bool Function()? canSignal,
    bool subscribeToSignaling = true,
  })  : _signaling = signaling,
        _onIncomingMessage = onIncomingMessage,
        _onConnected = onConnected,
        _canSignal = canSignal {
    if (subscribeToSignaling) {
      _signalSubscription = _signaling.messages.listen(handleSignal);
    }
  }

  @override
  bool get isHealthy => _healthy;

  /// Инициирует WebRTC-соединение и отправляет offer через signaling.
  @override
  Future<void> connect(String peerId) async {
    _connectCompleter = Completer<void>();
    _remotePeerId = peerId;
    _remoteDescriptionSet = false;
    _pendingIce.clear();
    _localIceBuffer.clear();
    _iceConnected = false;
    _dataChannelReady = false;
    _connectedNotified = false;
    _healthy = false;

    _log('connect:start peerId=$peerId mode=${mode.name}');
    final config = await _buildRtcConfig();

    _peer = await createPeerConnection(config);
    _bindPeerEvents();

    _dataChannel = await _peer!.createDataChannel(
      'data',
      RTCDataChannelInit()
        ..ordered = true
        ..maxRetransmits = 30,
    );

    _dataChannel!.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) {
        _onMessage(msg.binary);
      }
    };

    final offer = await _peer!.createOffer();
    await _peer!.setLocalDescription(offer);
    _log('connect:localOffer set transportMode=${mode.name}');

    _lastOfferPeerId = peerId;
    _lastOfferPayload = {
      ...offer.toMap(),
      'transportMode': mode.name,
    };

    if (!_canSendSignaling('offer', peerId)) {
      throw Exception('Transport signaling is suspended');
    }
    await _signaling.sendOffer(peerId, _lastOfferPayload!);
    _log('connect:offer sent');
    _scheduleOfferRetry();

    final completer = _connectCompleter;
    if (completer == null) {
      return;
    }
    try {
      await completer.future.timeout(const Duration(seconds: 20));
      _log('connect:completed');
    } on TimeoutException catch (e) {
      _log('connect:timeout error=$e');
      _healthy = false;
      await close();
      rethrow;
    } catch (e) {
      _log('connect:wait failed error=$e');
      _healthy = false;
      await close();
      rethrow;
    }
  }

  /// Формирует ICE-конфигурацию для direct/turn режимов.
  Future<Map<String, dynamic>> _buildRtcConfig() async {
    final iceServers = <Map<String, dynamic>>[];

    if (mode == TransportMode.turn) {
      await turnAllocator?.refreshSelectionIfNeeded();
      final turnCredentials = turnAllocator?.allocateAll() ?? const <TurnCredentials>[];

      if (turnCredentials.isEmpty) {
        throw Exception('TURN mode selected but no TURN available');
      }

      _activeTurn = turnCredentials.first;
      final configuredUrls = <String>[];
      for (final creds in turnCredentials) {
        final urls = creds.url
            .split(';')
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
        configuredUrls.addAll(urls);
        iceServers.add({
          'urls': urls,
          'username': creds.username,
          'credential': creds.password,
          'tlsCertPolicy': 'insecureNoCheck',
          'skpStrictTlsChecking': true,
        });
      }
      _log(
        'rtcConfig turn urls=${configuredUrls.join(',')} '
        'servers=${turnCredentials.length} username=${turnCredentials.first.username}',
      );
    } else {
      // Direct mode: use STUN only
      iceServers.add({'urls': ['stun:stun.l.google.com:19302']});
    }

    final config = <String, dynamic>{
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
    };
    if (mode == TransportMode.turn) {
      config['iceTransportPolicy'] = 'relay';
    }
    _log(
      'rtcConfig mode=${mode.name} policy=${config['iceTransportPolicy'] ?? 'all'} servers=${iceServers.length}',
    );
    return config;
  }

  bool _hasTurnAvailable() {
    if (mode != TransportMode.turn) {
      return true;
    }
    return turnAllocator?.allocate() != null;
  }

  /// Отправляет бинарные данные по открытому DataChannel.
  @override
  Future<void> send(Uint8List data) async {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      final pending = _PendingOutbound(data);
      _pendingOutbound.add(pending);
      if (_pendingOutbound.length > 100) {
        _pendingOutbound.removeAt(0);
        _log('send:drop oldest pending (queue limit)');
      }
      try {
        await pending.completer.future.timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            _log('send:timeout datachannel not open');
          },
        );
      } catch (e) {
        _log('send:drop reason=$e');
      }
      return;
    }

    _dataChannel!.send(RTCDataChannelMessage.fromBinary(data));
  }

  /// Привязывает обработчики состояния peer connection и ICE.
  void _bindPeerEvents() {
    _peer!.onIceConnectionState = (state) {
      _log('iceConnectionState=$state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _iceConnected = true;
        _maybeMarkConnected();
        _stopAnswerRetry();
        _stopOfferRetry();

        if (_activeTurn != null) {
          turnAllocator?.reportSuccess(_activeTurn!.url);
        }
      }

      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _iceConnected = false;
        _healthy = false;

        if (_activeTurn != null) {
          turnAllocator?.reportFailure(_activeTurn!.url);
        }
      }
    };

    _peer!.onDataChannel = (channel) {
      _log('onDataChannel label=${channel.label}');
      _dataChannel = channel;
      _bindDataChannelHandlers(channel);
    };

    if (_dataChannel != null) {
      _bindDataChannelHandlers(_dataChannel!);
    }

    _peer!.onIceCandidate = (candidate) {
      if (_remotePeerId == null) return;

      _log('iceCandidate:local ${candidate.candidate}');
      final payload = <String, dynamic>{
        ...Map<String, dynamic>.from(candidate.toMap()),
        'transportMode': mode.name,
      };
      if (!_remoteDescriptionSet) {
        _localIceBuffer.add(payload);
        _log('iceCandidate:buffered (remote not set)');
        return;
      }
      if (!_canSendSignaling('ice', _remotePeerId!)) {
        return;
      }
      _signaling.sendIce(_remotePeerId!, payload);
    };
  }

  /// Привязывает обработчики DataChannel состояния и входящих сообщений.
  void _bindDataChannelHandlers(RTCDataChannel channel) {
    channel.onDataChannelState = (state) {
      _log('dataChannelState=$state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _dataChannelReady = true;
        _maybeMarkConnected();
        _stopAnswerRetry();
        _stopOfferRetry();
        _flushPendingOutbound();
      }

      if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _dataChannelReady = false;
        _healthy = false;
      }
    };

    channel.onMessage = (RTCDataChannelMessage msg) {
      if (msg.isBinary) {
        _onMessage(msg.binary);
      }
    };
  }

  /// Унифицированная точка обработки входящего signaling сообщения.
  Future<void> handleSignal(SignalingMessage msg) async {
    if (_remotePeerId != null && msg.fromPeerId != _remotePeerId) {
      return;
    }

    if (mode == TransportMode.turn && !_hasTurnAvailable()) {
      _log('signal:drop type=${msg.type} reason=no turn available');
      return;
    }

    try {
      if (msg.type == 'offer') {
        _log('signal:offer from=${msg.fromPeerId}');
        await _handleOffer(msg);
        return;
      }

      if (msg.type == 'answer') {
        _log('signal:answer from=${msg.fromPeerId}');
        await _handleAnswer(msg);
        return;
      }

      if (msg.type == 'ice') {
        _log('signal:ice from=${msg.fromPeerId}');
        await _handleIce(msg);
        return;
      }
    } catch (e) {
      _log('signal:drop type=${msg.type} error=$e');
    }
  }

  /// Завершает ожидание connect(), когда канал считается готовым.
  void _maybeMarkConnected() {
    _healthy = _iceConnected && _dataChannelReady;
    if (!_healthy) {
      return;
    }

    final completer = _connectCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    final peerId = _remotePeerId;
    if (peerId != null && !_connectedNotified) {
      _connectedNotified = true;
      _onConnected?.call(peerId, mode);
    }
  }

  /// Обрабатывает входящий offer и отправляет answer.
  Future<void> _handleOffer(SignalingMessage msg) async {
    _remotePeerId = msg.fromPeerId;
    _remoteDescriptionSet = false;
    _pendingIce.clear();
    _localIceBuffer.clear();
    _iceConnected = false;
    _dataChannelReady = false;
    _connectedNotified = false;
    _healthy = false;

    final config = await _buildRtcConfig();
    _peer = await createPeerConnection(config);
    _bindPeerEvents();

    final offer = RTCSessionDescription(
      msg.data['sdp'],
      msg.data['type'],
    );

    await _peer!.setRemoteDescription(offer);
    _remoteDescriptionSet = true;
    _log('handleOffer:remote set');
    await _drainPendingIce();

    final answer = await _peer!.createAnswer();

    await _peer!.setLocalDescription(answer);
    _log('handleOffer:localAnswer set');

    _lastAnswerPeerId = msg.fromPeerId;
    _lastAnswerPayload = {
      ...answer.toMap(),
      'transportMode': mode.name,
    };

    if (!_canSendSignaling('answer', msg.fromPeerId)) {
      return;
    }
    await _signaling.sendAnswer(
      msg.fromPeerId,
      _lastAnswerPayload!,
    );
    _log('handleOffer:answer sent');
    _scheduleAnswerRetry();
    _flushLocalIceBuffer();
  }

  /// Применяет входящий answer от удаленного peer.
  Future<void> _handleAnswer(SignalingMessage msg) async {
    if (_peer == null) {
      _log('handleAnswer:drop peer not ready');
      return;
    }
    if (_remoteDescriptionSet) {
      _log('handleAnswer:skip already set');
      await _drainPendingIce();
      _flushLocalIceBuffer();
      _maybeMarkConnected();
      _stopOfferRetry();
      return;
    }
    final answer = RTCSessionDescription(
      msg.data['sdp'],
      msg.data['type'],
    );

    try {
      await _peer!.setRemoteDescription(answer);
      _remoteDescriptionSet = true;
      _log('handleAnswer:remote set');
      await _drainPendingIce();
      _maybeMarkConnected();
      _stopOfferRetry();
      _flushLocalIceBuffer();
    } catch (e) {
      _log('handleAnswer:drop error=$e');
    }
  }

  /// Добавляет входящий ICE candidate в peer connection.
  Future<void> _handleIce(SignalingMessage msg) async {
    final candidate = RTCIceCandidate(
      msg.data['candidate'],
      msg.data['sdpMid'],
      msg.data['sdpMLineIndex'],
    );

    final peer = _peer;
    if (peer == null || !_remoteDescriptionSet) {
      _pendingIce.add(candidate);
      _log('handleIce:queued (peer not ready) ${candidate.candidate}');
      return;
    }

    try {
      await peer.addCandidate(candidate);
      _log('handleIce:remote added ${candidate.candidate}');
    } catch (e) {
      _pendingIce.add(candidate);
      _log('handleIce:queue after addCandidate error=$e ${candidate.candidate}');
    }
  }

  Future<void> _drainPendingIce() async {
    final peer = _peer;
    if (peer == null || !_remoteDescriptionSet || _pendingIce.isEmpty) {
      return;
    }

    _log('handleIce:drain count=${_pendingIce.length}');
    final queued = List<RTCIceCandidate>.from(_pendingIce);
    for (final candidate in queued) {
      try {
        await peer.addCandidate(candidate);
        _pendingIce.remove(candidate);
      } catch (e) {
        _log('handleIce:drain failed error=$e ${candidate.candidate}');
        break;
      }
    }
  }

  /// Закрывает signaling подписки и ресурсы WebRTC соединения.
  @override
  Future<void> close() async {
    await _signalSubscription?.cancel();
    await _dataChannel?.close();
    await _peer?.close();
    _stopAnswerRetry();
    _stopOfferRetry();

    _healthy = false;
    _iceConnected = false;
    _dataChannelReady = false;
    _remoteDescriptionSet = false;
    _connectedNotified = false;
    _localIceBuffer.clear();
    _pendingIce.clear();
    _failPendingOutbound();
  }

  /// Пробрасывает входящее бинарное сообщение в верхний слой.
  void _onMessage(Uint8List data) {
    _log('recv bytes=${data.length}');
    _onIncomingMessage?.call(data);
  }

  void _log(String message) {
    final peer = _remotePeerId ?? 'unknown';
    developer.log(
      '[webrtc:${mode.name}][$peer][${_logSeq++}] $message',
      name: 'WebRtcTransport',
    );
  }

  void _scheduleAnswerRetry() {
    if (_lastAnswerPayload == null || _lastAnswerPeerId == null) {
      return;
    }
    _stopAnswerRetry();
    _answerRetryAttempts = 0;
    _answerRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_healthy) {
        _stopAnswerRetry();
        return;
      }
      if (_answerRetryAttempts >= 5) {
        _log('answerRetry:give up');
        _stopAnswerRetry();
        return;
      }
      _answerRetryAttempts += 1;
      _log('answerRetry:resend attempt=$_answerRetryAttempts');
      if (!_canSendSignaling('answer-retry', _lastAnswerPeerId!)) {
        return;
      }
      await _signaling.sendAnswer(_lastAnswerPeerId!, _lastAnswerPayload!);
    });
  }

  void _stopAnswerRetry() {
    _answerRetryTimer?.cancel();
    _answerRetryTimer = null;
  }

  void _scheduleOfferRetry() {
    if (_lastOfferPayload == null || _lastOfferPeerId == null) {
      return;
    }
    _stopOfferRetry();
    _offerRetryAttempts = 0;
    _offerRetryTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_healthy) {
        _stopOfferRetry();
        return;
      }
      if (_offerRetryAttempts >= 5) {
        _log('offerRetry:give up');
        _stopOfferRetry();
        return;
      }
      _offerRetryAttempts += 1;
      _log('offerRetry:resend attempt=$_offerRetryAttempts');
      if (!_canSendSignaling('offer-retry', _lastOfferPeerId!)) {
        return;
      }
      await _signaling.sendOffer(_lastOfferPeerId!, _lastOfferPayload!);
    });
  }

  void _stopOfferRetry() {
    _offerRetryTimer?.cancel();
    _offerRetryTimer = null;
  }

  void _flushLocalIceBuffer() {
    if (_remotePeerId == null || _localIceBuffer.isEmpty) {
      return;
    }
    final queued = List<Map<String, dynamic>>.from(_localIceBuffer);
    for (final payload in queued) {
      if (!_canSendSignaling('ice-flush', _remotePeerId!)) {
        continue;
      }
      _signaling.sendIce(_remotePeerId!, payload);
      _localIceBuffer.remove(payload);
    }
  }

  void _flushPendingOutbound() {
    if (_dataChannel == null ||
        _dataChannel!.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }

    for (final pending in List<_PendingOutbound>.from(_pendingOutbound)) {
      _dataChannel!.send(RTCDataChannelMessage.fromBinary(pending.data));
      pending.completer.complete();
      _pendingOutbound.remove(pending);
    }
  }

  void _failPendingOutbound() {
    for (final pending in List<_PendingOutbound>.from(_pendingOutbound)) {
      pending.completer.completeError(Exception('DataChannel closed'));
      _pendingOutbound.remove(pending);
    }
  }

  bool _canSendSignaling(String type, String peerId) {
    final allowed = _canSignal?.call() ?? true;
    if (!allowed) {
      _log('signal:$type suppressed peerId=$peerId');
    }
    return allowed;
  }
}

class _PendingOutbound {
  final Uint8List data;
  final Completer<void> completer = Completer<void>();

  _PendingOutbound(this.data);
}
