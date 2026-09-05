import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/reliable_codec.dart';
import 'package:peerlink/core/messaging/reliable_session_controller.dart';
import 'package:peerlink/core/relay/relay_client.dart';
import 'package:peerlink/core/security/identity_service.dart';
import 'package:peerlink/core/security/session_crypto.dart';
import 'package:peerlink/core/security/session_manager.dart';
import 'package:peerlink/core/security/signature_service.dart';

void main() {
  test('sendHandshakeInit stops after three attempts', () async {
    final identity = IdentityService(keyStore: _MemoryIdentityKeyStore());
    await identity.initialize();
    final sessions = SessionManager(
      identity: identity,
      crypto: SessionCrypto(),
      signatures: SignatureService(),
      peerIdentityStore: _MemoryPeerIdentityStore(),
    );
    final sentTypes = <ReliableEnvelopeType>[];
    final logs = <String>[];
    final controller = ReliableSessionController(
      relay: _FakeRelayClient(),
      sessions: sessions,
      isDisposed: () => false,
      isRelayEnabled: () => true,
      flushPendingMessages: (_) async {},
      flushPendingSecureInbound: (_) async {},
      sendControlEnvelope:
          ({
            required String peerId,
            required ReliableEnvelopeType type,
            required Uint8List payload,
          }) async {
            sentTypes.add(type);
          },
      log: logs.add,
    );

    fakeAsync((async) {
      expect(controller.markHandshakeInFlight('peer-a'), isTrue);
      unawaited(controller.sendHandshakeInit('peer-a'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 4));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 12));
      async.flushMicrotasks();

      expect(
        sentTypes
            .where((type) => type == ReliableEnvelopeType.handshakeInit)
            .length,
        3,
      );
      expect(
        logs,
        contains('handshake:giveup reason=max-attempts peer=peer-a'),
      );
    });
  });
}

class _FakeRelayClient implements RelayClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryPeerIdentityStore implements PeerIdentityStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String peerId) async => values[peerId];

  @override
  Future<void> write(String peerId, String value) async {
    values[peerId] = value;
  }
}

class _MemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}
