part of 'bootstrap_signaling_service.dart';

extension _BootstrapSignalingServiceProtocol on BootstrapSignalingService {
  Future<void> _send(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {
    final signal = _PendingSignal(peerId: peerId, type: type, data: data);

    final backoffUntil = _peerBackoff[peerId];
    final now = DateTime.now();
    if (backoffUntil != null && backoffUntil.isAfter(now)) {
      signal.nextAttempt = backoffUntil;
      _pendingSignals.putIfAbsent(peerId, () => <_PendingSignal>[]).add(signal);
      _scheduleRetry();
      _log(
        'send:queued type=$type to=$peerId reason=peer-backoff until=${backoffUntil.toIso8601String()}',
      );
      return;
    }

    if (_status != SignalingConnectionStatus.connected || _channel == null) {
      _pendingSignals.putIfAbsent(peerId, () => <_PendingSignal>[]).add(signal);
      _scheduleRetry();
      _log('send:queued type=$type to=$peerId reason=not-connected');
      return;
    }

    signal.attempts = 1;
    _lastSentSignals[peerId] = signal;
    _log('send:signal type=$type to=$peerId attempt=${signal.attempts}');
    _sendRaw({
      'v': BootstrapSignalingService._protocolVersion,
      'id': _newFrameId(),
      'type': 'signal',
      'payload': {
        'type': type,
        'from': _selfPeerId,
        'to': peerId,
        'data': data,
      },
    });
  }

  void _sendRaw(Map<String, dynamic> frame) {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    channel.sink.add(jsonEncode(frame));
  }

  Future<void> _handleServerMessage(dynamic raw) async {
    String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      _log('recv:unknown ${raw.runtimeType}');
      return;
    }

    _log('recv:raw ${raw.runtimeType} payload=$text');

    Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        _log('recv:ignored non-map frame');
        return;
      }
      frame = decoded;
    } catch (error, stackTrace) {
      _log('recv:decode error=$error');
      _messagesController.addError(error, stackTrace);
      return;
    }

    final type = frame['type']?.toString();
    final payload = frame['payload'];
    final payloadMap = payload is Map<String, dynamic>
        ? payload
        : (payload is Map ? Map<String, dynamic>.from(payload) : <String, dynamic>{});

    switch (type) {
      case 'register_ack':
        _registrationTimeout?.cancel();
        _registrationTimeout = null;
        _setError(null);
        _setStatus(SignalingConnectionStatus.connected);
        _reconnectAttempt = 0;
        _resetConnectFailureCircuit();
        _stopReconnectStopwatch('register_ack');
        _startHeartbeat();
        _startPeersRequestPolling();
        _flushAllQueues();
        _sendPeersRequest();
        _log('recv:register_ack');
        return;

      case 'signal':
        final signalType = payloadMap['type']?.toString() ?? '';
        final from = payloadMap['from']?.toString() ?? '';
        final to = payloadMap['to']?.toString() ?? '';
        final dataRaw = payloadMap['data'];
        final data = dataRaw is Map<String, dynamic>
            ? dataRaw
            : (dataRaw is Map ? Map<String, dynamic>.from(dataRaw) : <String, dynamic>{});

        _log('recv:signal type=$signalType from=$from to=$to');

        if (from.isNotEmpty) {
          _peerBackoff.remove(from);
          _flushPeerQueue(from);
        }

        _messagesController.add(
          SignalingMessage(
            type: signalType,
            fromPeerId: from,
            toPeerId: to,
            data: data,
          ),
        );
        return;

      case 'peers':
        final peersRaw = payloadMap['peers'];
        if (peersRaw is List) {
          final peers = peersRaw
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
          _presenceSnapshotPeers
            ..clear()
            ..addAll(peers);
          _peersController.add(peers);
          _log('recv:peers count=${peers.length}');
        }
        return;

      case 'presence_snapshot':
        final peersRaw = payloadMap['peers'];
        if (peersRaw is List) {
          final peers = peersRaw
              .map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList(growable: false);
          _presenceSnapshotPeers
            ..clear()
            ..addAll(peers);
          _peersController.add(peers);
          _log('recv:presence_snapshot count=${peers.length}');
        }
        return;

      case 'presence_update':
        final peerId = payloadMap['peerId']?.toString();
        final status = payloadMap['status']?.toString().toLowerCase();
        if (peerId == null || peerId.isEmpty || status == null || status.isEmpty) {
          return;
        }
        if (status == 'online') {
          _presenceSnapshotPeers.add(peerId);
        } else if (status == 'offline') {
          _presenceSnapshotPeers.remove(peerId);
        } else {
          return;
        }
        _peersController.add(
          _presenceSnapshotPeers.toList(growable: false),
        );
        _log('recv:presence_update peer=$peerId status=$status');
        return;

      case 'pong':
        _log('recv:pong');
        return;

      case 'error':
        _log('recv:error frame');
        if (_isUnsupportedPeersRequest(payloadMap)) {
          _peerDiscoverySupported = false;
          _log('recv:error ignore peers_request unsupported');
          return;
        }

        if (_isAlreadyRegistered(payloadMap)) {
          unawaited(_handleConnectionFailure('already registered'));
          return;
        }

        final peerId = _parsePeerNotConnected(payloadMap);
        if (peerId != null && peerId.isNotEmpty) {
          _handlePeerNotConnected(peerId);
          return;
        }

        final code = payloadMap['code']?.toString();
        final message = payloadMap['message']?.toString();
        _setError('server error: ${code ?? 'UNKNOWN'} ${message ?? ''}'.trim());
        return;

      default:
        _log('recv:ignored type=$type');
        return;
    }
  }

  Future<void> _disconnect() async {
    _registrationTimeout?.cancel();
    _registrationTimeout = null;
    _networkChangeTimer?.cancel();
    _networkChangeTimer = null;
    _stopHeartbeat();
    _stopPeersRequestPolling();
    _stopRetryTimer();
    _stopReconnectStopwatch('disconnect');
    await _teardownActiveChannel();
    _setStatus(SignalingConnectionStatus.disconnected);
  }

  Future<void> _teardownActiveChannel() async {
    final channel = _channel;
    _channel = null;

    await _channelSubscription?.cancel();
    _channelSubscription = null;

    if (channel != null) {
      await channel.sink.close();
    }
  }

  Future<Map<String, dynamic>> _buildRegisterFrame() async {
    final payload = <String, dynamic>{
      'peerId': _selfPeerId,
      'client': {'name': 'peerlink', 'protocol': BootstrapSignalingService._protocolVersion},
      'capabilities': const ['webrtc', 'signal-relay'],
    };

    final proof = await _registerProofBuilder?.call();
    if (proof != null) {
      payload['auth'] = proof.toJson();
    }

    return {
      'v': BootstrapSignalingService._protocolVersion,
      'id': _newFrameId(),
      'type': 'register',
      'payload': payload,
    };
  }

  String _newFrameId() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(BootstrapSignalingService._heartbeatInterval, (_) {
      if (_status != SignalingConnectionStatus.connected || _channel == null) {
        return;
      }
      _sendRaw({
        'v': BootstrapSignalingService._protocolVersion,
        'id': _newFrameId(),
        'type': 'ping',
        'payload': {'peerId': _selfPeerId},
      });
    });
  }

  void _sendPeersRequest() {
    if (!_peerDiscoverySupported) {
      return;
    }
    if (_status != SignalingConnectionStatus.connected || _channel == null) {
      return;
    }
    _sendRaw({
      'v': BootstrapSignalingService._protocolVersion,
      'id': _newFrameId(),
      'type': 'peers_request',
      'payload': {'peerId': _selfPeerId},
    });
  }

  void _startPeersRequestPolling() {
    _stopPeersRequestPolling();
    _peersRequestTimer = Timer.periodic(
      BootstrapSignalingService._peersRequestInterval,
      (_) => _sendPeersRequest(),
    );
  }

  void _stopPeersRequestPolling() {
    _peersRequestTimer?.cancel();
    _peersRequestTimer = null;
  }

  bool _isUnsupportedPeersRequest(Map<String, dynamic> payload) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString() ?? '';
    final unsupported = code == 'UNKNOWN_TYPE' && message.contains('peers_request');
    if (unsupported) {
      _log('error=peers_request unsupported by server');
    }
    return unsupported;
  }

  bool _isAlreadyRegistered(Map<String, dynamic> payload) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString().toLowerCase() ?? '';
    return code == 'ALREADY_REGISTERED' || message.contains('already registered');
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _flushPeerQueue(String peerId) {
    final queue = _pendingSignals[peerId];
    if (queue == null || queue.isEmpty) {
      _pendingSignals.remove(peerId);
      return;
    }
    if (_status != SignalingConnectionStatus.connected || _channel == null) {
      _scheduleRetry();
      return;
    }

    final now = DateTime.now();
    final remaining = <_PendingSignal>[];
    for (final pending in queue) {
      if (pending.nextAttempt != null && pending.nextAttempt!.isAfter(now)) {
        remaining.add(pending);
        continue;
      }

      pending.attempts += 1;
      if (pending.attempts > BootstrapSignalingService._maxSignalAttempts) {
        _log(
          'send:dropped type=${pending.type} to=${pending.peerId} reason=max-attempts',
        );
        continue;
      }

      _lastSentSignals[peerId] = pending;
      _log(
        'send:signal type=${pending.type} to=${pending.peerId} attempt=${pending.attempts}',
      );
      _sendRaw({
        'v': BootstrapSignalingService._protocolVersion,
        'id': _newFrameId(),
        'type': 'signal',
        'payload': {
          'type': pending.type,
          'from': _selfPeerId,
          'to': pending.peerId,
          'data': pending.data,
        },
      });
    }

    if (remaining.isEmpty) {
      _pendingSignals.remove(peerId);
    } else {
      _pendingSignals[peerId] = remaining;
    }

    _scheduleRetry();
  }

  void _flushAllQueues() {
    if (_pendingSignals.isEmpty) {
      return;
    }
    for (final peerId in _pendingSignals.keys.toList(growable: false)) {
      _flushPeerQueue(peerId);
    }
  }

  void _handlePeerNotConnected(String peerId) {
    final failed = _lastSentSignals[peerId];
    if (failed == null) {
      return;
    }

    if (!_isCallScopedSignal(failed.type)) {
      _log('peer:not-connected drop non-call signal type=${failed.type} to=$peerId');
      return;
    }

    final queue = _pendingSignals.putIfAbsent(peerId, () => <_PendingSignal>[]);
    final alreadyQueued = queue.any(
      (item) =>
          item.type == failed.type &&
          jsonEncode(item.data) == jsonEncode(failed.data),
    );

    if (!alreadyQueued) {
      failed.nextAttempt = DateTime.now().add(const Duration(milliseconds: 600));
      queue.add(failed);
    }

    final jitter = (DateTime.now().microsecond % 250) + 250;
    _peerBackoff[peerId] = DateTime.now().add(Duration(milliseconds: jitter));
    _log('peer:not-connected peerId=$peerId backoffMs=$jitter');
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_retryTimer != null) {
      return;
    }

    DateTime? nearest;
    final now = DateTime.now();
    final queues = List<List<_PendingSignal>>.from(_pendingSignals.values);
    for (final queue in queues) {
      for (final pending in List<_PendingSignal>.from(queue)) {
        final candidate = pending.nextAttempt ?? now;
        if (nearest == null || candidate.isBefore(nearest)) {
          nearest = candidate;
        }
      }
    }

    if (nearest == null) {
      return;
    }

    final delay = nearest.isAfter(now) ? nearest.difference(now) : Duration.zero;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _flushAllQueues();
    });
  }

  void _stopRetryTimer() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  String? _parsePeerNotConnected(Map<String, dynamic> payload) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString() ?? '';
    if (code != 'PEER_NOT_CONNECTED' && !message.contains('peer_not_connected')) {
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

    final match = RegExp(r'peer[_ ]?id[:= ]([A-Za-z0-9_\-]+)').firstMatch(message);
    return match?.group(1);
  }

  bool _isCallScopedSignal(String type) {
    return type.startsWith('call_');
  }
}
