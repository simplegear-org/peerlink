import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'bootstrap_signaling_models.dart';
import 'signaling_message.dart';
import 'signaling_service.dart';

class BootstrapSignalingRuntimeState {
  final StreamController<SignalingMessage> messagesController =
      StreamController<SignalingMessage>.broadcast();
  final StreamController<SignalingConnectionStatus> statusController =
      StreamController<SignalingConnectionStatus>.broadcast();
  final StreamController<String?> errorController =
      StreamController<String?>.broadcast();
  final StreamController<List<String>> peersController =
      StreamController<List<String>>.broadcast();

  WebSocketChannel? channel;
  StreamSubscription<dynamic>? channelSubscription;
  String? serverEndpoint;
  SignalingConnectionStatus status = SignalingConnectionStatus.disconnected;
  String? lastError;
  Timer? registrationTimeout;
  Timer? heartbeatTimer;
  Timer? peersRequestTimer;
  bool peerDiscoverySupported = true;
  final Set<String> presenceSnapshotPeers = <String>{};
  final Map<String, List<BootstrapPendingSignal>> pendingSignals =
      <String, List<BootstrapPendingSignal>>{};
  final Map<String, BootstrapPendingSignal> lastSentSignals =
      <String, BootstrapPendingSignal>{};
  final Map<String, DateTime> peerBackoff = <String, DateTime>{};
  Timer? retryTimer;
  Timer? networkChangeTimer;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  List<ConnectivityResult> lastConnectivity = const <ConnectivityResult>[];
  int reconnectAttempt = 0;
  bool manualCloseRequested = false;
  Completer<void>? setServerCompleter;
  String? setServerEndpoint;
  int logSeq = 0;
}
