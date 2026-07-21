import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:peerlink/core/runtime/app_file_logger.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'bootstrap_signaling_connectivity_controller.dart';
import 'bootstrap_signaling_models.dart';
import 'bootstrap_signaling_protocol_controller.dart';
import 'bootstrap_signaling_reconnect_controller.dart';
import 'bootstrap_signaling_runtime_state.dart';
import 'bootstrap_signaling_session_controller.dart';
import 'signaling_message.dart';
import 'signaling_service.dart';

/// Signaling через внешний bootstrap WebSocket сервер с выделенным IP.
///
/// Протокол сообщений описан в BOOTSTRAP_SIGNALING_PROTOCOL.md.
class BootstrapSignalingService implements SignalingService {
  static const String _protocolVersion = '1';
  static const Duration _registrationTimeoutDuration = Duration(seconds: 4);
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const Duration _peersRequestInterval = Duration(seconds: 15);
  static const Duration _channelCloseTimeout = Duration(seconds: 1);
  static const int _maxSignalAttempts = 6;
  static const Duration _minReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 15);
  static const int _connectFailureCircuitBreakerThreshold = 3;
  static const Duration _connectFailureCooldown = Duration(seconds: 45);

  final int instanceId = identityHashCode(Object());
  final String _selfPeerId;
  final Future<BootstrapRegisterProof?> Function()? _registerProofBuilder;
  final Duration _registrationTimeoutDurationOverride;
  final Connectivity _connectivity = Connectivity();
  final BootstrapSignalingRuntimeState _state =
      BootstrapSignalingRuntimeState();

  late final BootstrapSignalingConnectivityController _connectivityController;
  late final BootstrapSignalingReconnectController _reconnectController;
  late final BootstrapSignalingProtocolController _protocolController;
  late final BootstrapSignalingSessionController _sessionController;

  BootstrapSignalingService(
    this._selfPeerId, {
    Future<BootstrapRegisterProof?> Function()? registerProofBuilder,
    Duration? registrationTimeoutDuration,
  }) : _registerProofBuilder = registerProofBuilder,
       _registrationTimeoutDurationOverride =
           registrationTimeoutDuration ?? _registrationTimeoutDuration {
    _reconnectController = BootstrapSignalingReconnectController(
      state: _state,
      minReconnectDelay: _minReconnectDelay,
      maxReconnectDelay: _maxReconnectDelay,
      connectFailureCircuitBreakerThreshold:
          _connectFailureCircuitBreakerThreshold,
      connectFailureCooldown: _connectFailureCooldown,
      reconnect: setServer,
      log: _log,
    );
    _protocolController = BootstrapSignalingProtocolController(
      state: _state,
      selfPeerId: _selfPeerId,
      protocolVersion: _protocolVersion,
      heartbeatInterval: _heartbeatInterval,
      peersRequestInterval: _peersRequestInterval,
      channelCloseTimeout: _channelCloseTimeout,
      maxSignalAttempts: _maxSignalAttempts,
      registerProofBuilder: _registerProofBuilder,
      setError: _setError,
      setStatus: _setStatus,
      resetConnectFailureCircuit:
          _reconnectController.resetConnectFailureCircuit,
      resetReconnectAttempt: () => _state.reconnectAttempt = 0,
      stopReconnectStopwatch: _reconnectController.stopReconnectStopwatch,
      scheduleReconnect: _reconnectController.scheduleReconnect,
      handleConnectionFailure: _handleConnectionFailure,
      newFrameId: _newFrameId,
      log: _log,
      isUnsupportedPeersRequest: _isUnsupportedPeersRequest,
      isAlreadyRegistered: _isAlreadyRegistered,
      parsePeerNotConnected: _parsePeerNotConnected,
      isCallScopedSignal: _isCallScopedSignal,
    );
    _connectivityController = BootstrapSignalingConnectivityController(
      state: _state,
      checkConnectivity: _connectivity.checkConnectivity,
      connectivityChanges: _connectivity.onConnectivityChanged,
      handleNetworkBecameUnavailable: _handleNetworkBecameUnavailable,
      fastReconnectAfterNetworkChange: _fastReconnectAfterNetworkChange,
      log: _log,
    );
    _sessionController = BootstrapSignalingSessionController(
      state: _state,
      protocolController: _protocolController,
      reconnectController: _reconnectController,
      registrationTimeoutDuration: _registrationTimeoutDurationOverride,
      parseEndpointUri: _parseEndpointUri,
      isSafeBootstrapUri: _isSafeBootstrapUri,
      disconnect: _disconnect,
      handleConnectionFailure: _handleConnectionFailure,
      connectWebSocket: _connectWebSocket,
      handleServerMessage: _handleServerMessage,
      setStatus: _setStatus,
      setError: _setError,
      log: _log,
    );
    _log('construct instance=$instanceId');
    unawaited(_initializeConnectivityWatch());
  }

  @override
  Stream<SignalingMessage> get messages => _state.messagesController.stream;

  @override
  Stream<List<String>> get peersStream => _state.peersController.stream;

  @override
  SignalingConnectionStatus get connectionStatus => _state.status;

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      _state.statusController.stream;

  @override
  String? get lastError => _state.lastError;

  @override
  Stream<String?> get lastErrorStream => _state.errorController.stream;

  String? get serverEndpoint => _state.serverEndpoint;

  @override
  Future<void> setServer(String endpoint) {
    return _sessionController.setServer(endpoint);
  }

  @override
  Future<void> configureServers(List<String> endpoints) async {
    final normalized = endpoints
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (normalized.isEmpty) {
      await close();
      return;
    }
    await setServer(normalized.first);
  }

  Future<void> _handleConnectionFailure(String reason) async {
    if (reason == 'register_ack timeout') {
      _state.reconnectAttempt = 0;
    }
    _reconnectController.markReconnectPhase('failure:$reason');
    _setError(reason);
    _setStatus(SignalingConnectionStatus.error);
    await _teardownActiveChannel();
    _reconnectController.scheduleReconnect(reason);
  }

  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) {
    return sendSignal(peerId, 'offer', offer);
  }

  @override
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) {
    return sendSignal(peerId, 'answer', answer);
  }

  @override
  Future<void> sendIce(String peerId, Map<String, dynamic> candidate) {
    return sendSignal(peerId, 'ice', candidate);
  }

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) {
    return _protocolController.send(peerId, type, data);
  }

  @override
  Future<void> close() async {
    _state.manualCloseRequested = true;
    _reconnectController.stopReconnectTimer();
    _state.networkChangeTimer?.cancel();
    _state.networkChangeTimer = null;
    await _state.connectivitySubscription?.cancel();
    _state.connectivitySubscription = null;
    await _protocolController.disconnect();
  }

  Future<void> _initializeConnectivityWatch() async {
    await _connectivityController.initializeWatch();
    _state.connectivitySubscription = _connectivityController.subscription;
  }

  Future<void> _disconnect() => _protocolController.disconnect();

  Future<void> _handleServerMessage(dynamic raw) {
    return _protocolController.handleServerMessage(raw);
  }

  Future<void> _teardownActiveChannel() {
    return _protocolController.teardownActiveChannel();
  }

  Future<void> _handleNetworkBecameUnavailable() async {
    _reconnectController.startReconnectStopwatch('network unavailable');
    _state.networkChangeTimer?.cancel();
    _state.networkChangeTimer = null;
    _state.registrationTimeout?.cancel();
    _state.registrationTimeout = null;
    _protocolController.stopHeartbeat();
    _reconnectController.stopReconnectTimer();
    _state.reconnectAttempt = 0;
    _reconnectController.markReconnectPhase('teardown:start no-network');
    await _teardownActiveChannel();
    _reconnectController.markReconnectPhase('teardown:done no-network');
    _setError('network unavailable');
    _setStatus(SignalingConnectionStatus.disconnected);
  }

  Future<void> _fastReconnectAfterNetworkChange() async {
    if (_state.manualCloseRequested) {
      return;
    }
    final endpoint = _state.serverEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      return;
    }
    _reconnectController.startReconnectStopwatch('network changed');
    _log('network:fast reconnect endpoint=$endpoint');
    _state.reconnectAttempt = 0;
    _state.registrationTimeout?.cancel();
    _state.registrationTimeout = null;
    _protocolController.stopHeartbeat();
    _reconnectController.stopReconnectTimer();
    _reconnectController.markReconnectPhase('teardown:start fast-reconnect');
    await _teardownActiveChannel();
    _reconnectController.markReconnectPhase('teardown:done fast-reconnect');
    _setError('network changed');
    _setStatus(SignalingConnectionStatus.connecting);
    _reconnectController.markReconnectPhase('setServer:start fast-reconnect');
    await setServer(endpoint);
  }

  Uri _parseEndpointUri(String endpoint) {
    final withScheme = endpoint.contains('://') ? endpoint : 'ws://$endpoint';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      throw FormatException('Invalid bootstrap endpoint: $endpoint');
    }

    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      throw FormatException(
        'Bootstrap endpoint must use ws:// or wss://: $endpoint',
      );
    }

    return uri;
  }

  String _newFrameId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  bool _isUnsupportedPeersRequest(Map<String, dynamic> payload) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString() ?? '';
    final unsupported =
        code == 'UNKNOWN_TYPE' && message.contains('peers_request');
    if (unsupported) {
      _state.peerDiscoverySupported = false;
      _log('error=peers_request unsupported by server');
    }
    return unsupported;
  }

  bool _isAlreadyRegistered(Map<String, dynamic> payload) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString().toLowerCase() ?? '';
    return code == 'ALREADY_REGISTERED' ||
        message.contains('already registered');
  }

  String? _parsePeerNotConnected(Map<String, dynamic> payload) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString() ?? '';
    if (code != 'PEER_NOT_CONNECTED' &&
        !message.contains('peer_not_connected')) {
      return null;
    }

    final peerId = payload['peerId']?.toString();
    if (peerId != null && peerId.isNotEmpty) {
      return peerId;
    }

    final to = payload['to']?.toString();
    if (to != null && to.isNotEmpty) {
      return to;
    }

    final match = RegExp(
      r'peer[_ ]?id[:= ]([A-Za-z0-9_\-]+)',
    ).firstMatch(message);
    return match?.group(1);
  }

  bool _isCallScopedSignal(String type) {
    return type.startsWith('call_');
  }

  void _setStatus(SignalingConnectionStatus next) {
    if (_state.status == next) {
      return;
    }

    _state.status = next;
    _state.statusController.add(next);
    _log('status=$next');
  }

  void _setError(String? next) {
    if (_state.lastError == next) {
      return;
    }

    _state.lastError = next;
    _state.errorController.add(next);
    _log('error=$next');
  }

  void _log(String message) {
    final now = DateTime.now().toIso8601String();
    AppFileLogger.log(
      '[bootstrap][$_selfPeerId][${_state.logSeq++}][$now] $message',
      name: 'BootstrapSignaling',
    );
  }

  WebSocketChannel _connectWebSocket(Uri uri) {
    try {
      if (uri.scheme == 'wss') {
        final client = HttpClient();
        client.badCertificateCallback =
            (X509Certificate cert, String host, int port) {
              return host == uri.host;
            };
        return IOWebSocketChannel.connect(uri, customClient: client);
      }
      return WebSocketChannel.connect(uri);
    } catch (error) {
      throw StateError(
        'invalid bootstrap endpoint: ${uri.toString()} ($error)',
      );
    }
  }

  bool _isSafeBootstrapUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'ws' && scheme != 'wss') || uri.host.trim().isEmpty) {
      return false;
    }
    return _isSafeBootstrapHost(uri.host.trim());
  }

  bool _isSafeBootstrapHost(String host) {
    final value = host.trim();
    if (value.isEmpty || value.contains('%')) {
      return false;
    }
    if (_isIpAddressHost(value)) {
      return true;
    }
    final domainPattern = RegExp(r'^[A-Za-z0-9.-]+$');
    return domainPattern.hasMatch(value);
  }

  bool _isIpAddressHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    try {
      return InternetAddress.tryParse(host) != null;
    } on FormatException {
      return false;
    }
  }
}
