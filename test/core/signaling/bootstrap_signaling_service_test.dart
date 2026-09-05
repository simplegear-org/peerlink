import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/signaling/bootstrap_signaling_service.dart';
import 'package:peerlink/core/signaling/signaling_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setServer handles websocket ready timeout without throwing', () async {
    final hangingServer = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final acceptedSockets = <Socket>[];
    final serverSubscription = hangingServer.listen(acceptedSockets.add);
    final service = BootstrapSignalingService(
      'self-peer',
      registrationTimeoutDuration: const Duration(milliseconds: 80),
    );

    addTearDown(() async {
      await service.close();
      for (final socket in acceptedSockets) {
        socket.destroy();
      }
      await serverSubscription.cancel();
      await hangingServer.close();
    });

    await expectLater(
      service.setServer(
        'ws://${hangingServer.address.address}:${hangingServer.port}',
      ),
      completes,
    );

    expect(service.connectionStatus, SignalingConnectionStatus.error);
    expect(service.lastError, 'connect ready timeout');
  });
}
