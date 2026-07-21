import 'package:connectivity_plus/connectivity_plus.dart';

import '../transport/transport_mode.dart';
import '../turn/turn_allocator.dart';

class CallNetworkPolicyHelper {
  const CallNetworkPolicyHelper({
    required this.connectivity,
    required this.turnAllocator,
    required this.directConnectAttemptTimeout,
    required this.turnConnectAttemptTimeout,
  });

  final Connectivity connectivity;
  final TurnAllocator? turnAllocator;
  final Duration directConnectAttemptTimeout;
  final Duration turnConnectAttemptTimeout;

  Future<TransportMode> preferredInitialMode({
    required void Function(String message) log,
  }) async {
    if (!await hasTurnAvailable(log: log)) {
      log('networkPolicy: TURN unavailable, cannot start call');
      throw StateError('TURN is not available');
    }

    try {
      final results = await connectivity.checkConnectivity();
      log(
        'networkPolicy: connectivity=$results preferredMode=${TransportMode.turn.name}',
      );
    } catch (error) {
      log(
        'networkPolicy: connectivity check failed error=$error preferredMode=turn',
      );
    }
    return TransportMode.turn;
  }

  Future<bool> hasTurnAvailable({
    required void Function(String message) log,
  }) async {
    try {
      await turnAllocator?.refreshSelectionIfNeeded();
    } catch (error) {
      log('networkPolicy: TURN refresh failed error=$error');
    }
    final available = turnAllocator?.allocate() != null;
    log('networkPolicy: TURN available=$available');
    return available;
  }

  String transportLabelFor(TransportMode mode) {
    switch (mode) {
      case TransportMode.direct:
        return 'Прямое соединение';
      case TransportMode.turn:
        return 'TURN relay';
    }
  }

  Duration timeoutForMode(TransportMode mode) {
    switch (mode) {
      case TransportMode.direct:
        return directConnectAttemptTimeout;
      case TransportMode.turn:
        return turnConnectAttemptTimeout;
    }
  }
}
