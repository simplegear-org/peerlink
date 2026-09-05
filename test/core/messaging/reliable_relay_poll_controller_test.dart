import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/messaging/reliable_codec.dart';
import 'package:peerlink/core/messaging/reliable_relay_poll_controller.dart';
import 'package:peerlink/core/relay/relay_client.dart';
import 'package:peerlink/core/relay/relay_models.dart';
import 'package:peerlink/core/security/identity_service.dart';
import 'package:peerlink/core/security/session_crypto.dart';
import 'package:peerlink/core/security/session_manager.dart';
import 'package:peerlink/core/security/signature_service.dart';

class _InMemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class _FakeRelayClient implements RelayClient {
  _FakeRelayClient(this._fetchResults);

  final List<RelayFetchResult> _fetchResults;
  final List<String?> fetchCursors = <String?>[];
  final List<RelayAck> acked = <RelayAck>[];
  int _fetchIndex = 0;

  @override
  Future<RelayFetchResult> fetch(
    String recipientId, {
    String? cursor,
    int limit = 100,
  }) async {
    fetchCursors.add(cursor);
    final index = _fetchIndex < _fetchResults.length
        ? _fetchIndex
        : _fetchResults.length - 1;
    _fetchIndex += 1;
    return _fetchResults[index];
  }

  @override
  Future<void> ack(RelayAck ack) async {
    acked.add(ack);
  }

  @override
  void configureServers(List<String> servers) {}

  @override
  Future<RelayFetchResult> fetchFromServers(
    String recipientId, {
    required List<String> servers,
    String? cursor,
    int limit = 100,
  }) {
    return fetch(recipientId, cursor: cursor, limit: limit);
  }

  @override
  Future<void> registerPushToken({
    required String peerId,
    required String token,
  }) async {}

  @override
  Future<void> storeBlob(
    RelayBlobUploadEnvelope envelope, {
    void Function({
      required int sentBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) async {}

  @override
  Future<RelayWriteReceipt> store(RelayEnvelope envelope) async {
    return RelayWriteReceipt.empty;
  }

  @override
  Future<RelayWriteReceipt> storeGroup(RelayGroupEnvelope envelope) async {
    return RelayWriteReceipt.empty;
  }

  @override
  Future<void> unregisterPushToken({
    required String peerId,
    required String token,
  }) async {}

  @override
  Future<void> updateGroupMembers(
    RelayGroupMembersUpdateEnvelope envelope,
  ) async {}

  @override
  Future<RelayBlobDownload> fetchBlob(
    String blobId, {
    void Function({
      required int receivedBytes,
      required int totalBytes,
      required String status,
    })?
    onProgress,
  }) async {
    throw UnimplementedError();
  }
}

Future<SessionManager> _buildSessionManager() async {
  final identity = IdentityService(keyStore: _InMemoryIdentityKeyStore());
  await identity.initialize();
  return SessionManager(
    identity: identity,
    crypto: SessionCrypto(),
    signatures: SignatureService(),
  );
}

Future<RelayEnvelope> _buildEnvelope({
  required SessionManager sender,
  required SessionManager recipient,
}) async {
  final payload = Uint8List.fromList('hello'.codeUnits);
  const envelopeId = 'env-1';
  final timestampMs = DateTime.now().millisecondsSinceEpoch;
  final signaturePayload = buildReliableSignaturePayload(
    envelopeId: envelopeId,
    from: sender.identity.nodeId,
    to: recipient.identity.nodeId,
    timestampMs: timestampMs,
    ttlSeconds: 60,
    payload: payload,
  );
  final signature = await sender.signatures.sign(
    signaturePayload,
    sender.identity.signingKeyPair,
  );
  return RelayEnvelope(
    id: envelopeId,
    from: sender.identity.nodeId,
    to: recipient.identity.nodeId,
    timestampMs: timestampMs,
    ttlSeconds: 60,
    payload: payload,
    signature: signature,
    senderSigningPublicKey: Uint8List.fromList(
      sender.identity.signingPublicKey.bytes,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('poll retains cursor until envelope is acked', () async {
    final recipient = await _buildSessionManager();
    final sender = await _buildSessionManager();
    final envelope = await _buildEnvelope(sender: sender, recipient: recipient);
    final relay = _FakeRelayClient(<RelayFetchResult>[
      RelayFetchResult(messages: <RelayEnvelope>[envelope], cursor: 'cursor-1'),
      RelayFetchResult(messages: <RelayEnvelope>[envelope], cursor: 'cursor-1'),
    ]);

    var deliveryAttempts = 0;
    final controller = ReliableRelayPollController(
      relay: relay,
      sessions: recipient,
      selfId: recipient.identity.nodeId,
      activePollInterval: const Duration(seconds: 1),
      idlePollInterval: const Duration(seconds: 2),
      isDisposed: () => false,
      isRelayEnabled: () => true,
      isInboundReady: () => true,
      buildSignaturePayload: buildReliableSignaturePayload,
      buildAckSignaturePayload: buildReliableAckSignaturePayload,
      handleReliableEnvelope:
          ({
            required String envelopeId,
            required String fromPeerId,
            String? groupId,
            required int timestampMs,
            required Uint8List bytes,
          }) async {
            deliveryAttempts += 1;
            return deliveryAttempts > 1;
          },
      log: (_) {},
    );

    await controller.poll();
    await controller.poll();

    expect(relay.fetchCursors, <String?>[null, null]);
    expect(deliveryAttempts, 2);
    expect(relay.acked, hasLength(1));
    expect(relay.acked.single.id, envelope.id);
  });

  test(
    'empty poll must not advance cursor while deferred replay is pending',
    () async {
      final recipient = await _buildSessionManager();
      final sender = await _buildSessionManager();
      final envelope = await _buildEnvelope(
        sender: sender,
        recipient: recipient,
      );
      final relay = _FakeRelayClient(<RelayFetchResult>[
        RelayFetchResult(
          messages: <RelayEnvelope>[envelope],
          cursor: 'cursor-1',
        ),
        RelayFetchResult(messages: const <RelayEnvelope>[], cursor: 'cursor-1'),
        RelayFetchResult(
          messages: <RelayEnvelope>[envelope],
          cursor: 'cursor-1',
        ),
      ]);

      var deliveryAttempts = 0;
      final controller = ReliableRelayPollController(
        relay: relay,
        sessions: recipient,
        selfId: recipient.identity.nodeId,
        activePollInterval: const Duration(seconds: 1),
        idlePollInterval: const Duration(seconds: 2),
        isDisposed: () => false,
        isRelayEnabled: () => true,
        isInboundReady: () => true,
        buildSignaturePayload: buildReliableSignaturePayload,
        buildAckSignaturePayload: buildReliableAckSignaturePayload,
        handleReliableEnvelope:
            ({
              required String envelopeId,
              required String fromPeerId,
              String? groupId,
              required int timestampMs,
              required Uint8List bytes,
            }) async {
              deliveryAttempts += 1;
              return deliveryAttempts >= 2;
            },
        log: (_) {},
      );

      await controller.poll();
      await controller.poll();
      await controller.poll();

      expect(relay.fetchCursors, <String?>[null, null, null]);
      expect(deliveryAttempts, 2);
      expect(relay.acked, hasLength(1));
      expect(relay.acked.single.id, envelope.id);
    },
  );

  test('poll skips fetch until inbound consumer is ready', () async {
    final recipient = await _buildSessionManager();
    final relay = _FakeRelayClient(<RelayFetchResult>[
      RelayFetchResult(messages: const <RelayEnvelope>[], cursor: null),
    ]);

    final controller = ReliableRelayPollController(
      relay: relay,
      sessions: recipient,
      selfId: recipient.identity.nodeId,
      activePollInterval: const Duration(seconds: 1),
      idlePollInterval: const Duration(seconds: 2),
      isDisposed: () => false,
      isRelayEnabled: () => true,
      isInboundReady: () => false,
      buildSignaturePayload: buildReliableSignaturePayload,
      buildAckSignaturePayload: buildReliableAckSignaturePayload,
      handleReliableEnvelope:
          ({
            required String envelopeId,
            required String fromPeerId,
            String? groupId,
            required int timestampMs,
            required Uint8List bytes,
          }) async {
            fail(
              'handleReliableEnvelope should not be called when inbound is not ready',
            );
          },
      log: (_) {},
    );

    await controller.poll();

    expect(relay.fetchCursors, isEmpty);
    expect(relay.acked, isEmpty);
  });
}
