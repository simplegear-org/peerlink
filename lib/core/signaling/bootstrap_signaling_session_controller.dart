import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'bootstrap_signaling_models.dart';
import 'bootstrap_signaling_protocol_controller.dart';
import 'bootstrap_signaling_reconnect_controller.dart';
import 'bootstrap_signaling_runtime_state.dart';
import 'signaling_service.dart';

class BootstrapSignalingSessionController {
  final BootstrapSignalingRuntimeState state;
  final BootstrapSignalingProtocolController protocolController;
  final BootstrapSignalingReconnectController reconnectController;
  final Duration registrationTimeoutDuration;
  final Uri Function(String endpoint) parseEndpointUri;
  final bool Function(Uri uri) isSafeBootstrapUri;
  final Future<void> Function() disconnect;
  final Future<void> Function(String reason) handleConnectionFailure;
  final WebSocketChannel Function(Uri uri) connectWebSocket;
  final Future<void> Function(dynamic raw) handleServerMessage;
  final void Function(SignalingConnectionStatus next) setStatus;
  final void Function(String? next) setError;
  final void Function(String message) log;

  BootstrapSignalingSessionController({
    required this.state,
    required this.protocolController,
    required this.reconnectController,
    required this.registrationTimeoutDuration,
    required this.parseEndpointUri,
    required this.isSafeBootstrapUri,
    required this.disconnect,
    required this.handleConnectionFailure,
    required this.connectWebSocket,
    required this.handleServerMessage,
    required this.setStatus,
    required this.setError,
    required this.log,
  });

  Future<void> setServer(String endpoint) async {
    final normalized = endpoint.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('Bootstrap signaling endpoint is empty');
    }

    late final Uri uri;
    late final String canonicalEndpoint;
    try {
      uri = parseEndpointUri(normalized);
      canonicalEndpoint = uri.toString();
    } catch (error) {
      setError('invalid endpoint: $error');
      setStatus(SignalingConnectionStatus.error);
      log('connect:invalid endpoint=$normalized error=$error');
      return;
    }

    if (!isSafeBootstrapUri(uri)) {
      setError('invalid endpoint: некорректный адрес');
      setStatus(SignalingConnectionStatus.error);
      log(
        'connect:invalid endpoint=$canonicalEndpoint error=unsafe host/scheme',
      );
      return;
    }

    if (state.serverEndpoint == canonicalEndpoint &&
        (state.status == SignalingConnectionStatus.connected ||
            state.status == SignalingConnectionStatus.connecting)) {
      log(
        'connect:skip unchanged endpoint=$canonicalEndpoint status=${state.status}',
      );
      return;
    }

    final inFlight = state.setServerCompleter;
    if (inFlight != null) {
      if (state.setServerEndpoint == canonicalEndpoint) {
        log('connect:join in-flight endpoint=$canonicalEndpoint');
        return inFlight.future;
      }
      log(
        'connect:wait in-flight current=${state.setServerEndpoint ?? "unknown"} '
        'requested=$canonicalEndpoint',
      );
      await inFlight.future;
      if (state.serverEndpoint == canonicalEndpoint &&
          (state.status == SignalingConnectionStatus.connected ||
              state.status == SignalingConnectionStatus.connecting)) {
        return;
      }
    }

    final completer = Completer<void>();
    state.setServerCompleter = completer;
    state.setServerEndpoint = canonicalEndpoint;

    state.manualCloseRequested = false;
    reconnectController.stopReconnectTimer();
    try {
      await disconnect();
      setStatus(SignalingConnectionStatus.connecting);

      state.serverEndpoint = canonicalEndpoint;
      try {
        log('connect:start endpoint=$canonicalEndpoint');
        reconnectController.markReconnectPhase(
          'connect:start endpoint=$canonicalEndpoint',
        );
        state.channel = connectWebSocket(uri);
        state.channelSubscription = state.channel!.stream.listen(
          handleServerMessage,
          onError: (error, stackTrace) {
            setError('socket error: $error');
            setStatus(SignalingConnectionStatus.error);
            reconnectController.scheduleReconnect('socket error');
            log('socket:error endpoint=$canonicalEndpoint error=$error');
          },
          onDone: () {
            final channel = state.channel;
            log(
              'socket:done closeCode=${channel?.closeCode} closeReason=${channel?.closeReason}',
            );
            reconnectController.markReconnectPhase(
              'socket:done closeCode=${channel?.closeCode} closeReason=${channel?.closeReason}',
            );
            state.channel = null;
            state.registrationTimeout?.cancel();
            state.registrationTimeout = null;
            protocolController.stopHeartbeat();
            setError('socket closed');
            setStatus(SignalingConnectionStatus.disconnected);
            reconnectController.scheduleReconnect('socket done');
          },
        );

        final readyError = await _waitForChannelReady(state.channel!);
        if (readyError == null) {
          log('connect:ready');
          reconnectController.markReconnectPhase('connect:ready');
        } else if (readyError is BootstrapReadyTimeout) {
          log('connect:ready timeout');
          reconnectController.markReconnectPhase('connect:ready timeout');
          await _handleConnectReadyFailure('connect ready timeout');
          return;
        } else {
          log('connect:ready error=$readyError');
          reconnectController.markReconnectPhase(
            'connect:ready error=$readyError',
          );
          await _handleConnectReadyFailure('connect ready failed: $readyError');
          return;
        }

        log('send:register');
        reconnectController.markReconnectPhase('send:register');
        protocolController.sendRaw(
          await protocolController.buildRegisterFrame(),
        );

        state.registrationTimeout?.cancel();
        state.registrationTimeout = Timer(registrationTimeoutDuration, () {
          if (state.status == SignalingConnectionStatus.connecting) {
            reconnectController.markReconnectPhase('register_ack timeout');
            unawaited(handleConnectionFailure('register_ack timeout'));
          }
        });
      } catch (error) {
        state.channel = null;
        await state.channelSubscription?.cancel();
        state.channelSubscription = null;
        state.registrationTimeout?.cancel();
        state.registrationTimeout = null;
        protocolController.stopHeartbeat();
        reconnectController.recordConnectFailure();
        setError('connect failed: $error');
        setStatus(SignalingConnectionStatus.error);
        reconnectController.scheduleReconnect('connect failed');
        log('connect:error endpoint=$canonicalEndpoint error=$error');
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(state.setServerCompleter, completer)) {
        state.setServerCompleter = null;
        state.setServerEndpoint = null;
      }
    }
  }

  Future<Object?> _waitForChannelReady(WebSocketChannel channel) async {
    final completer = Completer<Object?>();
    late final Timer timeoutTimer;

    void complete(Object? value) {
      if (!completer.isCompleted) {
        completer.complete(value);
      }
    }

    timeoutTimer = Timer(
      registrationTimeoutDuration,
      () => complete(const BootstrapReadyTimeout()),
    );
    unawaited(
      channel.ready.then<void>(
        (_) => complete(null),
        onError: (Object error, StackTrace stackTrace) => complete(error),
      ),
    );

    final result = await completer.future;
    timeoutTimer.cancel();
    return result;
  }

  Future<void> _handleConnectReadyFailure(String reason) async {
    reconnectController.recordConnectFailure();
    await handleConnectionFailure(reason);
  }
}
