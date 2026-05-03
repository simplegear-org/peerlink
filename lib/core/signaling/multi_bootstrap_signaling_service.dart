import 'dart:async';
import 'dart:convert';

import 'package:peerlink/core/runtime/app_file_logger.dart';

import 'bootstrap_signaling_service.dart';
import 'signaling_message.dart';
import 'signaling_service.dart';

class MultiBootstrapSignalingService implements SignalingService {
  final String _selfPeerId;
  final Future<BootstrapRegisterProof?> Function()? _registerProofBuilder;

  final StreamController<SignalingMessage> _messagesController =
      StreamController<SignalingMessage>.broadcast();
  final StreamController<List<String>> _peersController =
      StreamController<List<String>>.broadcast();
  final StreamController<SignalingConnectionStatus> _statusController =
      StreamController<SignalingConnectionStatus>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  final Map<String, BootstrapSignalingService> _services =
      <String, BootstrapSignalingService>{};
  final Map<String, StreamSubscription<SignalingMessage>> _messageSubs =
      <String, StreamSubscription<SignalingMessage>>{};
  final Map<String, StreamSubscription<List<String>>> _peerSubs =
      <String, StreamSubscription<List<String>>>{};
  final Map<String, StreamSubscription<SignalingConnectionStatus>> _statusSubs =
      <String, StreamSubscription<SignalingConnectionStatus>>{};
  final Map<String, StreamSubscription<String?>> _errorSubs =
      <String, StreamSubscription<String?>>{};

  final Map<String, SignalingConnectionStatus> _statusByEndpoint =
      <String, SignalingConnectionStatus>{};
  final Map<String, String?> _errorByEndpoint = <String, String?>{};
  final Map<String, List<String>> _peersByEndpoint = <String, List<String>>{};

  final Set<String> _seenSignals = <String>{};
  final List<String> _configuredEndpoints = <String>[];

  SignalingConnectionStatus _status = SignalingConnectionStatus.disconnected;
  String? _lastError;
  int _logSeq = 0;

  MultiBootstrapSignalingService(
    this._selfPeerId, {
    Future<BootstrapRegisterProof?> Function()? registerProofBuilder,
  }) : _registerProofBuilder = registerProofBuilder;

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

  List<String> get connectedEndpoints => _configuredEndpoints
      .where(
        (endpoint) => _statusByEndpoint[endpoint] == SignalingConnectionStatus.connected,
      )
      .toList(growable: false);

  String? get primaryConnectedEndpoint {
    for (final endpoint in _configuredEndpoints) {
      if (_statusByEndpoint[endpoint] == SignalingConnectionStatus.connected) {
        return endpoint;
      }
    }
    return _configuredEndpoints.isEmpty ? null : _configuredEndpoints.first;
  }

  @override
  Future<void> setServer(String endpoint) async {
    await configureServers(<String>[endpoint]);
  }

  @override
  Future<void> configureServers(List<String> endpoints) async {
    final normalized = <String>[];
    final seen = <String>{};
    for (final item in endpoints) {
      final endpoint = item.trim();
      if (endpoint.isEmpty || !seen.add(endpoint)) {
        continue;
      }
      normalized.add(endpoint);
    }

    final removed = _services.keys
        .where((endpoint) => !normalized.contains(endpoint))
        .toList(growable: false);
    for (final endpoint in removed) {
      await _detachEndpoint(endpoint);
    }

    _configuredEndpoints
      ..clear()
      ..addAll(normalized);

    for (final endpoint in normalized) {
      await _ensureEndpoint(endpoint);
    }

    if (normalized.isEmpty) {
      _emitPeers();
      _emitStatus();
      _emitError();
      return;
    }

    await Future.wait(
      normalized.map((endpoint) async {
        try {
          await _services[endpoint]!.setServer(endpoint);
        } catch (error) {
          _log('configure:error endpoint=$endpoint error=$error');
        }
      }),
    );
    _emitStatus();
    _emitError();
  }

  @override
  Future<void> sendSignal(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {
    final targets = _targetServicesForPeer(peerId);
    if (targets.isEmpty) {
      throw StateError('No bootstrap signaling server configured');
    }
    _log(
      'send:signal type=$type to=$peerId targets=${targets.keys.join(',')}',
    );
    await Future.wait(
      targets.values.map((service) => service.sendSignal(peerId, type, data)),
    );
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
  Future<void> close() async {
    for (final endpoint in List<String>.from(_services.keys)) {
      await _services[endpoint]?.close();
      _statusByEndpoint[endpoint] = SignalingConnectionStatus.disconnected;
      _errorByEndpoint.remove(endpoint);
      _peersByEndpoint.remove(endpoint);
    }
    _emitPeers();
    _emitStatus();
    _emitError();
  }

  Future<void> _ensureEndpoint(String endpoint) async {
    if (_services.containsKey(endpoint)) {
      return;
    }
    final service = BootstrapSignalingService(
      _selfPeerId,
      registerProofBuilder: _registerProofBuilder,
    );
    _services[endpoint] = service;
    _statusByEndpoint[endpoint] = SignalingConnectionStatus.disconnected;
    _errorByEndpoint[endpoint] = null;
    _peersByEndpoint[endpoint] = const <String>[];

    _messageSubs[endpoint] = service.messages.listen(
      (message) => _handleMessage(endpoint, message),
      onError: (Object error, StackTrace stackTrace) {
        _messagesController.addError(error, stackTrace);
      },
    );
    _peerSubs[endpoint] = service.peersStream.listen(
      (peers) {
        _peersByEndpoint[endpoint] = List<String>.from(peers);
        _emitPeers();
      },
    );
    _statusSubs[endpoint] = service.connectionStatusStream.listen((status) {
      _statusByEndpoint[endpoint] = status;
      _emitStatus();
    });
    _errorSubs[endpoint] = service.lastErrorStream.listen((error) {
      _errorByEndpoint[endpoint] = error;
      _emitError();
    });
  }

  Future<void> _detachEndpoint(String endpoint) async {
    await _messageSubs.remove(endpoint)?.cancel();
    await _peerSubs.remove(endpoint)?.cancel();
    await _statusSubs.remove(endpoint)?.cancel();
    await _errorSubs.remove(endpoint)?.cancel();
    final service = _services.remove(endpoint);
    await service?.close();
    _statusByEndpoint.remove(endpoint);
    _errorByEndpoint.remove(endpoint);
    _peersByEndpoint.remove(endpoint);
  }

  Map<String, BootstrapSignalingService> _targetServicesForPeer(String peerId) {
    final targeted = <String, BootstrapSignalingService>{};

    for (final endpoint in _configuredEndpoints) {
      if (_statusByEndpoint[endpoint] != SignalingConnectionStatus.connected) {
        continue;
      }
      final peers = _peersByEndpoint[endpoint] ?? const <String>[];
      if (!peers.contains(peerId)) {
        continue;
      }
      final service = _services[endpoint];
      if (service != null) {
        targeted[endpoint] = service;
      }
    }

    if (targeted.isNotEmpty) {
      return targeted;
    }

    for (final endpoint in _configuredEndpoints) {
      if (_statusByEndpoint[endpoint] != SignalingConnectionStatus.connected) {
        continue;
      }
      final service = _services[endpoint];
      if (service != null) {
        targeted[endpoint] = service;
      }
    }

    if (targeted.isNotEmpty) {
      return targeted;
    }

    for (final endpoint in _configuredEndpoints) {
      final service = _services[endpoint];
      if (service != null) {
        targeted[endpoint] = service;
      }
    }

    return targeted;
  }

  void _handleMessage(String endpoint, SignalingMessage message) {
    final dedupeKey = jsonEncode(<String, dynamic>{
      'type': message.type,
      'from': message.fromPeerId,
      'to': message.toPeerId,
      'data': message.data,
    });
    if (!_seenSignals.add(dedupeKey)) {
      return;
    }
    if (_seenSignals.length > 512) {
      final oldest = _seenSignals.first;
      _seenSignals.remove(oldest);
    }
    _messagesController.add(message);
  }

  void _emitPeers() {
    final peers = <String>{};
    final snapshots = List<List<String>>.from(_peersByEndpoint.values);
    for (final items in snapshots) {
      peers.addAll(items);
    }
    final merged = peers.toList(growable: false)..sort();
    _peersController.add(merged);
  }

  void _emitStatus() {
    final statuses = _configuredEndpoints
        .map((endpoint) => _statusByEndpoint[endpoint])
        .whereType<SignalingConnectionStatus>()
        .toList(growable: false);
    final next = _aggregateStatus(statuses);
    if (_status == next) {
      return;
    }
    _status = next;
    _statusController.add(next);
    _log('status=$next connected=${connectedEndpoints.length}/${_configuredEndpoints.length}');
  }

  void _emitError() {
    String? next;
    if (connectedEndpoints.isNotEmpty) {
      next = null;
    } else {
      final endpoints = List<String>.from(_configuredEndpoints);
      for (final endpoint in endpoints) {
        final error = _errorByEndpoint[endpoint];
        if (error != null && error.isNotEmpty) {
          next = error;
          break;
        }
      }
    }
    if (_lastError == next) {
      return;
    }
    _lastError = next;
    _errorController.add(next);
    _log('error=$next');
  }

  SignalingConnectionStatus _aggregateStatus(
    List<SignalingConnectionStatus> statuses,
  ) {
    if (statuses.isEmpty) {
      return SignalingConnectionStatus.disconnected;
    }
    if (statuses.contains(SignalingConnectionStatus.connected)) {
      return SignalingConnectionStatus.connected;
    }
    if (statuses.contains(SignalingConnectionStatus.connecting)) {
      return SignalingConnectionStatus.connecting;
    }
    if (statuses.contains(SignalingConnectionStatus.error)) {
      return SignalingConnectionStatus.error;
    }
    return SignalingConnectionStatus.disconnected;
  }

  void _log(String message) {
    AppFileLogger.log(
      '[multi_bootstrap][$_selfPeerId][${_logSeq++}] $message',
    );
  }
}
