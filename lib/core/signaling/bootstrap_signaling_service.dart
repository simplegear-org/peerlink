import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'signaling_message.dart';
import 'signaling_service.dart';

part 'bootstrap_signaling_service_connectivity.dart';
part 'bootstrap_signaling_service_protocol.dart';

/// Signaling через внешний bootstrap WebSocket сервер с выделенным IP.
///
/// Протокол сообщений описан в BOOTSTRAP_SIGNALING_PROTOCOL.md.
class BootstrapSignalingService implements SignalingService {
  static const String _protocolVersion = '1';
  static const Duration _registrationTimeoutDuration = Duration(seconds: 4);
  static const Duration _heartbeatInterval = Duration(seconds: 20);
  static const Duration _peersRequestInterval = Duration(seconds: 15);
  static const int _maxSignalAttempts = 6;
  static const Duration _minReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 15);
  static const int _connectFailureCircuitBreakerThreshold = 3;
  static const Duration _connectFailureCooldown = Duration(seconds: 45);

  final String _selfPeerId;
  final _messagesController = StreamController<SignalingMessage>.broadcast();
  final _statusController =
      StreamController<SignalingConnectionStatus>.broadcast();
  final _errorController = StreamController<String?>.broadcast();
  final _peersController = StreamController<List<String>>.broadcast();
  final Future<BootstrapRegisterProof?> Function()? _registerProofBuilder;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  String? _serverEndpoint;
  SignalingConnectionStatus _status = SignalingConnectionStatus.disconnected;
  String? _lastError;
  Timer? _registrationTimeout;
  Timer? _heartbeatTimer;
  Timer? _peersRequestTimer;
  int _logSeq = 0;
  bool _peerDiscoverySupported = true;
  final Set<String> _presenceSnapshotPeers = <String>{};
  final Map<String, List<_PendingSignal>> _pendingSignals = {};
  final Map<String, _PendingSignal> _lastSentSignals = {};
  final Map<String, DateTime> _peerBackoff = {};
  Timer? _retryTimer;
  Timer? _reconnectTimer;
  Timer? _networkChangeTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final Connectivity _connectivity = Connectivity();
  List<ConnectivityResult> _lastConnectivity = const <ConnectivityResult>[];
  int _reconnectAttempt = 0;
  bool _manualCloseRequested = false;
  Stopwatch? _reconnectStopwatch;
  Completer<void>? _setServerCompleter;
  String? _setServerEndpoint;
  int _consecutiveConnectFailures = 0;
  DateTime? _cooldownUntil;

  BootstrapSignalingService(
    this._selfPeerId, {
    Future<BootstrapRegisterProof?> Function()? registerProofBuilder,
  }) : _registerProofBuilder = registerProofBuilder {
    unawaited(_initializeConnectivityWatch());
  }

  @override
  Stream<SignalingMessage> get messages => _messagesController.stream;

  @override
  Stream<List<String>> get peersStream => _peersController.stream;

  @override
  SignalingConnectionStatus get connectionStatus => _status;

  @override
  Stream<SignalingConnectionStatus> get connectionStatusStream =>
      _statusController.stream;

  @override
  String? get lastError => _lastError;

  @override
  Stream<String?> get lastErrorStream => _errorController.stream;

  String? get serverEndpoint => _serverEndpoint;

  /// Подключается к bootstrap-серверу и отправляет кадр register.
  /// Статус connection считается connected только после register_ack.
  @override
  Future<void> setServer(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Bootstrap signaling endpoint is empty');
    }

    late final Uri uri;
    late final String canonicalEndpoint;
    try {
      uri = _parseEndpointUri(normalized);
      canonicalEndpoint = uri.toString();
    } catch (error) {
      _setError('invalid endpoint: $error');
      _setStatus(SignalingConnectionStatus.error);
      _log('connect:invalid endpoint=$normalized error=$error');
      return;
    }

    if (_serverEndpoint == canonicalEndpoint && _channel != null) {
      return;
    }

    final inFlight = _setServerCompleter;
    if (inFlight != null) {
      if (_setServerEndpoint == canonicalEndpoint) {
        _log('connect:join in-flight endpoint=$canonicalEndpoint');
        return inFlight.future;
      }
      _log(
        'connect:wait in-flight current=${_setServerEndpoint ?? "unknown"} '
        'requested=$canonicalEndpoint',
      );
      await inFlight.future;
      if (_serverEndpoint == canonicalEndpoint && _channel != null) {
        return;
      }
    }

    final completer = Completer<void>();
    _setServerCompleter = completer;
    _setServerEndpoint = canonicalEndpoint;

    _manualCloseRequested = false;
    _stopReconnectTimer();
    try {
      await _disconnect();
      _setStatus(SignalingConnectionStatus.connecting);

      _serverEndpoint = canonicalEndpoint;
      try {
        _log('connect:start endpoint=$canonicalEndpoint');
        _markReconnectPhase('connect:start endpoint=$canonicalEndpoint');
        _channel = _connectWebSocket(uri);
        _channelSubscription = _channel!.stream.listen(
          _handleServerMessage,
          onError: (error, stackTrace) {
            _setError('socket error: $error');
            _setStatus(SignalingConnectionStatus.error);
            _scheduleReconnect('socket error');
            _log('socket:error endpoint=$canonicalEndpoint error=$error');
          },
          onDone: () {
            final channel = _channel;
            _log(
              'socket:done closeCode=${channel?.closeCode} closeReason=${channel?.closeReason}',
            );
            _markReconnectPhase(
              'socket:done closeCode=${channel?.closeCode} closeReason=${channel?.closeReason}',
            );
            _channel = null;
            _registrationTimeout?.cancel();
            _registrationTimeout = null;
            _stopHeartbeat();
            _setError('socket closed');
            _setStatus(SignalingConnectionStatus.disconnected);
            _scheduleReconnect('socket done');
          },
        );

        try {
          await _channel!.ready.timeout(_registrationTimeoutDuration);
          _log('connect:ready');
          _markReconnectPhase('connect:ready');
        } catch (error) {
          _log('connect:ready error=$error');
          _markReconnectPhase('connect:ready error=$error');
          rethrow;
        }

        _log('send:register');
        _markReconnectPhase('send:register');
        _sendRaw(await _buildRegisterFrame());

        _registrationTimeout?.cancel();
        _registrationTimeout = Timer(_registrationTimeoutDuration, () {
          if (_status == SignalingConnectionStatus.connecting) {
            _markReconnectPhase('register_ack timeout');
            unawaited(_handleConnectionFailure('register_ack timeout'));
          }
        });
      } catch (error) {
        _channel = null;
        await _channelSubscription?.cancel();
        _channelSubscription = null;
        _registrationTimeout?.cancel();
        _registrationTimeout = null;
        _stopHeartbeat();
        _recordConnectFailure();
        _setError('connect failed: $error');
        _setStatus(SignalingConnectionStatus.error);
        _scheduleReconnect('connect failed');
        _log('connect:error endpoint=$canonicalEndpoint error=$error');
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_setServerCompleter, completer)) {
        _setServerCompleter = null;
        _setServerEndpoint = null;
      }
    }
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
      _reconnectAttempt = 0;
    }
    _markReconnectPhase('failure:$reason');
    _setError(reason);
    _setStatus(SignalingConnectionStatus.error);
    await _teardownActiveChannel();
    _scheduleReconnect(reason);
  }

  /// Отправляет SDP offer адресату через bootstrap сервер.
  @override
  Future<void> sendOffer(String peerId, Map<String, dynamic> offer) {
    return sendSignal(peerId, 'offer', offer);
  }

  /// Отправляет SDP answer адресату через bootstrap сервер.
  @override
  Future<void> sendAnswer(String peerId, Map<String, dynamic> answer) {
    return sendSignal(peerId, 'answer', answer);
  }

  /// Отправляет ICE candidate адресату через bootstrap сервер.
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
    return _send(peerId, type, data);
  }

  /// Закрывает signaling-соединение.
  @override
  Future<void> close() async {
    _manualCloseRequested = true;
    _stopReconnectTimer();
    _networkChangeTimer?.cancel();
    _networkChangeTimer = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _disconnect();
  }

  void _setStatus(SignalingConnectionStatus next) {
    if (_status == next) {
      return;
    }

    _status = next;
    _statusController.add(next);
    _log('status=$next');
  }

  void _setError(String? next) {
    if (_lastError == next) {
      return;
    }

    _lastError = next;
    _errorController.add(next);
    _log('error=$next');
  }

  void _log(String message) {
    final now = DateTime.now().toIso8601String();
    AppFileLogger.log(
      '[bootstrap][$_selfPeerId][${_logSeq++}][$now] $message',
      name: 'BootstrapSignaling',
    );
  }

  WebSocketChannel _connectWebSocket(Uri uri) {
    if (uri.scheme == 'wss') {
      final client = HttpClient();
      if (_isIpAddressHost(uri.host)) {
        client.badCertificateCallback = (
          X509Certificate cert,
          String host,
          int port,
        ) {
          return host == uri.host;
        };
      }
      return IOWebSocketChannel.connect(
        uri,
        customClient: client,
      );
    }
    return WebSocketChannel.connect(uri);
  }

  bool _isIpAddressHost(String host) {
    if (host.isEmpty) {
      return false;
    }
    return InternetAddress.tryParse(host) != null;
  }
}

class _PendingSignal {
  final String peerId;
  final String type;
  final Map<String, dynamic> data;
  int attempts = 0;
  DateTime? nextAttempt;

  _PendingSignal({
    required this.peerId,
    required this.type,
    required this.data,
  });
}

class BootstrapRegisterProof {
  final String scheme;
  final String peerId;
  final String? legacyPeerId;
  final int timestampMs;
  final String nonce;
  final Uint8List signingPublicKey;
  final Uint8List signature;
  final Map<String, dynamic>? identityProfile;

  const BootstrapRegisterProof({
    required this.scheme,
    required this.peerId,
    this.legacyPeerId,
    required this.timestampMs,
    required this.nonce,
    required this.signingPublicKey,
    required this.signature,
    this.identityProfile,
  });

  Map<String, dynamic> toJson() {
    final payload = <String, dynamic>{
      'scheme': scheme,
      'peerId': peerId,
      'timestampMs': timestampMs,
      'nonce': nonce,
      'signingPublicKey': base64Encode(signingPublicKey),
      'signature': base64Encode(signature),
    };
    if (legacyPeerId != null && legacyPeerId!.isNotEmpty) {
      payload['legacyPeerId'] = legacyPeerId;
    }
    if (identityProfile != null && identityProfile!.isNotEmpty) {
      payload['identityProfile'] = identityProfile;
    }
    return payload;
  }
}
