import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'bootstrap_signaling_runtime_state.dart';
import 'signaling_service.dart';

class BootstrapSignalingConnectivityController {
  final BootstrapSignalingRuntimeState state;
  final Future<List<ConnectivityResult>> Function() checkConnectivity;
  final Stream<List<ConnectivityResult>> connectivityChanges;
  final Future<void> Function() handleNetworkBecameUnavailable;
  final Future<void> Function() fastReconnectAfterNetworkChange;
  final void Function(String message) log;

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  BootstrapSignalingConnectivityController({
    required this.state,
    required this.checkConnectivity,
    required this.connectivityChanges,
    required this.handleNetworkBecameUnavailable,
    required this.fastReconnectAfterNetworkChange,
    required this.log,
  });

  StreamSubscription<List<ConnectivityResult>>? get subscription =>
      _subscription;

  Future<void> initializeWatch() async {
    try {
      state.lastConnectivity = await checkConnectivity();
    } catch (_) {
      state.lastConnectivity = const <ConnectivityResult>[];
    }

    try {
      _subscription = connectivityChanges.listen((results) {
        final previousState = state.lastConnectivity;
        if (sameConnectivity(previousState, results)) {
          return;
        }
        final previous = List<ConnectivityResult>.from(previousState);
        state.lastConnectivity = List<ConnectivityResult>.from(results);
        log('network:changed from=$previous to=$results');
        scheduleFastReconnectForNetworkChange(results);
      });
    } catch (error) {
      log('network:watch unavailable error=$error');
    }
  }

  bool sameConnectivity(
    List<ConnectivityResult> a,
    List<ConnectivityResult> b,
  ) {
    final normalizedA = a.toSet().toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    final normalizedB = b.toSet().toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    if (normalizedA.length != normalizedB.length) {
      return false;
    }
    for (var index = 0; index < normalizedA.length; index++) {
      if (normalizedA[index] != normalizedB[index]) {
        return false;
      }
    }
    return true;
  }

  void scheduleFastReconnectForNetworkChange(List<ConnectivityResult> results) {
    if (state.manualCloseRequested) {
      return;
    }
    final endpoint = state.serverEndpoint;
    if (endpoint == null || endpoint.isEmpty) {
      return;
    }
    if (results.isEmpty ||
        (results.length == 1 && results.first == ConnectivityResult.none)) {
      log('network:changed no network, tearing down active channel');
      unawaited(handleNetworkBecameUnavailable());
      return;
    }

    if (state.status == SignalingConnectionStatus.connected &&
        state.channel != null) {
      log(
        'network:changed active channel preserved '
        'status=${state.status} results=$results',
      );
      return;
    }

    state.networkChangeTimer?.cancel();
    state.networkChangeTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(fastReconnectAfterNetworkChange());
    });
  }
}
