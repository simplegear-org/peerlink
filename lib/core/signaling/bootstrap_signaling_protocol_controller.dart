import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'bootstrap_signaling_models.dart';
import 'bootstrap_signaling_runtime_state.dart';
import 'signaling_message.dart';
import 'signaling_service.dart';

class BootstrapSignalingProtocolController {
  final BootstrapSignalingRuntimeState state;
  final String selfPeerId;
  final String protocolVersion;
  final Duration heartbeatInterval;
  final Duration peersRequestInterval;
  final Duration channelCloseTimeout;
  final int maxSignalAttempts;
  final Future<BootstrapRegisterProof?> Function()? registerProofBuilder;
  final void Function(String? value) setError;
  final void Function(SignalingConnectionStatus value) setStatus;
  final void Function() resetConnectFailureCircuit;
  final void Function() resetReconnectAttempt;
  final void Function(String reason) stopReconnectStopwatch;
  final void Function(String reason) scheduleReconnect;
  final Future<void> Function(String reason) handleConnectionFailure;
  final String Function() newFrameId;
  final void Function(String message) log;
  final bool Function(Map<String, dynamic> payload) isUnsupportedPeersRequest;
  final bool Function(Map<String, dynamic> payload) isAlreadyRegistered;
  final String? Function(Map<String, dynamic> payload) parsePeerNotConnected;
  final bool Function(String type) isCallScopedSignal;

  BootstrapSignalingProtocolController({
    required this.state,
    required this.selfPeerId,
    required this.protocolVersion,
    required this.heartbeatInterval,
    required this.peersRequestInterval,
    required this.channelCloseTimeout,
    required this.maxSignalAttempts,
    required this.registerProofBuilder,
    required this.setError,
    required this.setStatus,
    required this.resetConnectFailureCircuit,
    required this.resetReconnectAttempt,
    required this.stopReconnectStopwatch,
    required this.scheduleReconnect,
    required this.handleConnectionFailure,
    required this.newFrameId,
    required this.log,
    required this.isUnsupportedPeersRequest,
    required this.isAlreadyRegistered,
    required this.parsePeerNotConnected,
    required this.isCallScopedSignal,
  });

  Future<void> send(
    String peerId,
    String type,
    Map<String, dynamic> data,
  ) async {
    final signal = BootstrapPendingSignal(
      peerId: peerId,
      type: type,
      data: data,
    );

    final backoffUntil = state.peerBackoff[peerId];
    final now = DateTime.now();
    if (backoffUntil != null && backoffUntil.isAfter(now)) {
      signal.nextAttempt = backoffUntil;
      state.pendingSignals
          .putIfAbsent(peerId, () => <BootstrapPendingSignal>[])
          .add(signal);
      scheduleRetry();
      log(
        'send:queued type=$type to=$peerId reason=peer-backoff until=${backoffUntil.toIso8601String()}',
      );
      return;
    }

    if (state.status != SignalingConnectionStatus.connected ||
        state.channel == null) {
      state.pendingSignals
          .putIfAbsent(peerId, () => <BootstrapPendingSignal>[])
          .add(signal);
      scheduleRetry();
      log('send:queued type=$type to=$peerId reason=not-connected');
      return;
    }

    signal.attempts = 1;
    state.lastSentSignals[peerId] = signal;
    log('send:signal type=$type to=$peerId attempt=${signal.attempts}');
    sendRaw({
      'v': protocolVersion,
      'id': newFrameId(),
      'type': 'signal',
      'payload': {'type': type, 'from': selfPeerId, 'to': peerId, 'data': data},
    });
  }

  void sendRaw(Map<String, dynamic> frame) {
    final channel = state.channel;
    if (channel == null) {
      return;
    }
    channel.sink.add(jsonEncode(frame));
  }

  Future<void> handleServerMessage(dynamic raw) async {
    String text;
    if (raw is String) {
      text = raw;
    } else if (raw is List<int>) {
      text = utf8.decode(raw);
    } else {
      log('recv:unknown ${raw.runtimeType}');
      return;
    }

    log('recv:raw ${raw.runtimeType} payload=$text');

    Map<String, dynamic> frame;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) {
        log('recv:ignored non-map frame');
        return;
      }
      frame = decoded;
    } catch (error, stackTrace) {
      log('recv:decode error=$error');
      state.messagesController.addError(error, stackTrace);
      return;
    }

    final type = frame['type']?.toString();
    final payload = frame['payload'];
    final payloadMap = payload is Map<String, dynamic>
        ? payload
        : (payload is Map
              ? Map<String, dynamic>.from(payload)
              : <String, dynamic>{});

    switch (type) {
      case 'register_ack':
        state.registrationTimeout?.cancel();
        state.registrationTimeout = null;
        setError(null);
        setStatus(SignalingConnectionStatus.connected);
        resetReconnectAttempt();
        resetConnectFailureCircuit();
        stopReconnectStopwatch('register_ack');
        startHeartbeat();
        startPeersRequestPolling();
        flushAllQueues();
        sendPeersRequest();
        log('recv:register_ack');
        return;

      case 'signal':
        final signalType = payloadMap['type']?.toString() ?? '';
        final from = payloadMap['from']?.toString() ?? '';
        final to = payloadMap['to']?.toString() ?? '';
        final dataRaw = payloadMap['data'];
        final data = dataRaw is Map<String, dynamic>
            ? dataRaw
            : (dataRaw is Map
                  ? Map<String, dynamic>.from(dataRaw)
                  : <String, dynamic>{});

        log('recv:signal type=$signalType from=$from to=$to');

        if (from.isNotEmpty) {
          state.peerBackoff.remove(from);
          flushPeerQueue(from);
        }

        state.messagesController.add(
          SignalingMessage(
            type: signalType,
            fromPeerId: from,
            toPeerId: to,
            data: data,
          ),
        );
        return;

      case 'peers':
        _handlePeersSnapshot(payloadMap, 'recv:peers');
        return;

      case 'presence_snapshot':
        _handlePeersSnapshot(payloadMap, 'recv:presence_snapshot');
        return;

      case 'presence_update':
        final peerId = payloadMap['peerId']?.toString();
        final status = payloadMap['status']?.toString().toLowerCase();
        if (peerId == null ||
            peerId.isEmpty ||
            status == null ||
            status.isEmpty) {
          return;
        }
        if (status == 'online') {
          state.presenceSnapshotPeers.add(peerId);
        } else if (status == 'offline') {
          state.presenceSnapshotPeers.remove(peerId);
        } else {
          return;
        }
        state.peersController.add(
          state.presenceSnapshotPeers.toList(growable: false),
        );
        log('recv:presence_update peer=$peerId status=$status');
        return;

      case 'pong':
        log('recv:pong');
        return;

      case 'error':
        log('recv:error frame');
        if (isUnsupportedPeersRequest(payloadMap)) {
          return;
        }

        if (isAlreadyRegistered(payloadMap)) {
          unawaited(handleConnectionFailure('already registered'));
          return;
        }

        final peerId = parsePeerNotConnected(payloadMap);
        if (peerId != null && peerId.isNotEmpty) {
          handlePeerNotConnected(peerId);
          return;
        }

        final code = payloadMap['code']?.toString();
        final message = payloadMap['message']?.toString();
        setError('server error: ${code ?? 'UNKNOWN'} ${message ?? ''}'.trim());
        return;

      default:
        log('recv:ignored type=$type');
        return;
    }
  }

  Future<void> disconnect() async {
    state.registrationTimeout?.cancel();
    state.registrationTimeout = null;
    stopHeartbeat();
    stopPeersRequestPolling();
    stopRetryTimer();
    stopReconnectStopwatch('disconnect');
    await teardownActiveChannel();
    setStatus(SignalingConnectionStatus.disconnected);
  }

  Future<void> teardownActiveChannel() async {
    final channel = state.channel;
    state.channel = null;

    await state.channelSubscription?.cancel();
    state.channelSubscription = null;

    if (channel != null) {
      await closeChannelSinkBounded(channel);
    }
  }

  Future<void> closeChannelSinkBounded(WebSocketChannel channel) async {
    final completer = Completer<void>();
    late final Timer timeoutTimer;

    void complete() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    timeoutTimer = Timer(channelCloseTimeout, () {
      log('socket:close timeout ignored');
      complete();
    });
    unawaited(
      channel.sink.close().then<void>(
        (_) => complete(),
        onError: (Object error, StackTrace stackTrace) {
          log('socket:close ignored error=$error');
          complete();
        },
      ),
    );
    await completer.future;
    timeoutTimer.cancel();
  }

  Future<Map<String, dynamic>> buildRegisterFrame() async {
    final payload = <String, dynamic>{
      'peerId': selfPeerId,
      'client': {'name': 'peerlink', 'protocol': protocolVersion},
      'capabilities': const ['webrtc', 'signal-relay'],
    };

    final proof = await registerProofBuilder?.call();
    if (proof != null) {
      payload['auth'] = proof.toJson();
    }

    return {
      'v': protocolVersion,
      'id': newFrameId(),
      'type': 'register',
      'payload': payload,
    };
  }

  void startHeartbeat() {
    stopHeartbeat();
    state.heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (state.status != SignalingConnectionStatus.connected ||
          state.channel == null) {
        return;
      }
      sendRaw({
        'v': protocolVersion,
        'id': newFrameId(),
        'type': 'ping',
        'payload': {'peerId': selfPeerId},
      });
    });
  }

  void sendPeersRequest() {
    if (!state.peerDiscoverySupported) {
      return;
    }
    if (state.status != SignalingConnectionStatus.connected ||
        state.channel == null) {
      return;
    }
    sendRaw({
      'v': protocolVersion,
      'id': newFrameId(),
      'type': 'peers_request',
      'payload': {'peerId': selfPeerId},
    });
  }

  void startPeersRequestPolling() {
    stopPeersRequestPolling();
    state.peersRequestTimer = Timer.periodic(
      peersRequestInterval,
      (_) => sendPeersRequest(),
    );
  }

  void stopPeersRequestPolling() {
    state.peersRequestTimer?.cancel();
    state.peersRequestTimer = null;
  }

  void stopHeartbeat() {
    state.heartbeatTimer?.cancel();
    state.heartbeatTimer = null;
  }

  void flushPeerQueue(String peerId) {
    final queue = state.pendingSignals[peerId];
    if (queue == null || queue.isEmpty) {
      state.pendingSignals.remove(peerId);
      return;
    }
    if (state.status != SignalingConnectionStatus.connected ||
        state.channel == null) {
      scheduleRetry();
      return;
    }

    final now = DateTime.now();
    final remaining = <BootstrapPendingSignal>[];
    for (final pending in queue) {
      if (pending.nextAttempt != null && pending.nextAttempt!.isAfter(now)) {
        remaining.add(pending);
        continue;
      }

      pending.attempts += 1;
      if (pending.attempts > maxSignalAttempts) {
        log(
          'send:dropped type=${pending.type} to=${pending.peerId} reason=max-attempts',
        );
        continue;
      }

      state.lastSentSignals[peerId] = pending;
      log(
        'send:signal type=${pending.type} to=${pending.peerId} attempt=${pending.attempts}',
      );
      sendRaw({
        'v': protocolVersion,
        'id': newFrameId(),
        'type': 'signal',
        'payload': {
          'type': pending.type,
          'from': selfPeerId,
          'to': pending.peerId,
          'data': pending.data,
        },
      });
    }

    if (remaining.isEmpty) {
      state.pendingSignals.remove(peerId);
    } else {
      state.pendingSignals[peerId] = remaining;
    }

    scheduleRetry();
  }

  void flushAllQueues() {
    if (state.pendingSignals.isEmpty) {
      return;
    }
    for (final peerId in state.pendingSignals.keys.toList(growable: false)) {
      flushPeerQueue(peerId);
    }
  }

  void handlePeerNotConnected(String peerId) {
    final failed = state.lastSentSignals[peerId];
    if (failed == null) {
      return;
    }

    if (!isCallScopedSignal(failed.type)) {
      log(
        'peer:not-connected drop non-call signal type=${failed.type} to=$peerId',
      );
      return;
    }

    final queue = state.pendingSignals.putIfAbsent(
      peerId,
      () => <BootstrapPendingSignal>[],
    );
    final alreadyQueued = queue.any((item) => item.samePayloadAs(failed));

    if (!alreadyQueued) {
      failed.nextAttempt = DateTime.now().add(
        const Duration(milliseconds: 600),
      );
      queue.add(failed);
    }

    final jitter = (DateTime.now().microsecond % 250) + 250;
    state.peerBackoff[peerId] = DateTime.now().add(
      Duration(milliseconds: jitter),
    );
    log('peer:not-connected peerId=$peerId backoffMs=$jitter');
    scheduleRetry();
  }

  void scheduleRetry() {
    if (state.retryTimer != null) {
      return;
    }

    DateTime? nearest;
    final now = DateTime.now();
    final queues = List<List<BootstrapPendingSignal>>.from(
      state.pendingSignals.values,
    );
    for (final queue in queues) {
      for (final pending in List<BootstrapPendingSignal>.from(queue)) {
        final candidate = pending.nextAttempt ?? now;
        if (nearest == null || candidate.isBefore(nearest)) {
          nearest = candidate;
        }
      }
    }

    if (nearest == null) {
      return;
    }

    final delay = nearest.isAfter(now)
        ? nearest.difference(now)
        : Duration.zero;
    state.retryTimer = Timer(delay, () {
      state.retryTimer = null;
      flushAllQueues();
    });
  }

  void stopRetryTimer() {
    state.retryTimer?.cancel();
    state.retryTimer = null;
  }

  void _handlePeersSnapshot(Map<String, dynamic> payloadMap, String label) {
    final peersRaw = payloadMap['peers'];
    if (peersRaw is! List) {
      return;
    }
    final peers = peersRaw
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    state.presenceSnapshotPeers
      ..clear()
      ..addAll(peers);
    state.peersController.add(peers);
    log('$label count=${peers.length}');
  }
}
