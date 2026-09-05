import 'dart:io';

import 'package:peerlink/core/push/push_api_client.dart';
import 'package:peerlink/features/contacts/infrastructure/contacts_repository.dart';
import 'package:peerlink/core/runtime/peer_access_control_service.dart';
import 'package:peerlink/core/runtime/push_access_policy_sync_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';
import 'package:peerlink/core/security/identity_service.dart';
import 'package:peerlink/ui/models/contact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;
  late IdentityService identity;
  late _FakePushApiClient apiClient;

  setUp(() async {
    await StorageService.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('peerlink_policy_sync_');
    storage = StorageService();
    await storage.initForTesting(rootDirectory: tempDir);
    identity = IdentityService(keyStore: _MemoryIdentityKeyStore());
    await identity.initialize();
    apiClient = _FakePushApiClient();
    await storage.getSettings().put(
      'push_servers',
      const <Map<String, dynamic>>[
        <String, dynamic>{'endpoint': 'https://push.example', 'paused': false},
        <String, dynamic>{'endpoint': 'https://paused.example', 'paused': true},
      ],
    );
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'sync sends sorted contacts and blocked peers to active endpoints',
    () async {
      await ContactsRepository(
        storage: storage,
      ).save(Contact(peerId: 'peer-b', name: 'B'));
      await ContactsRepository(
        storage: storage,
      ).save(Contact(peerId: 'peer-a', name: 'A'));
      final access = PeerAccessControlService.forStorage(storage);
      await access.setAllowMessagesOnlyFromContacts(true);
      await access.blockPeer('peer-z');

      final service = PushAccessPolicySyncService(
        identity: identity,
        storage: storage,
        pushApiClient: apiClient,
      );

      await service.syncNow(reason: 'test', force: true);

      expect(apiClient.calls, hasLength(1));
      expect(apiClient.calls.single.baseUri.toString(), 'https://push.example');
      expect(apiClient.calls.single.userId, identity.nodeId);
      expect(apiClient.calls.single.allowMessagesOnlyFromContacts, isTrue);
      expect(apiClient.calls.single.contactPeerIds, <String>[
        'peer-a',
        'peer-b',
      ]);
      expect(apiClient.calls.single.blockedPeerIds, <String>['peer-z']);
      expect(apiClient.calls.single.policyVersion, 1);
      expect(apiClient.calls.single.updatedAt, matches(RegExp(r'\.\d{3}Z$')));
    },
  );

  test('failed sync is retried from pending state', () async {
    apiClient.fail = true;
    final service = PushAccessPolicySyncService(
      identity: identity,
      storage: storage,
      pushApiClient: apiClient,
    );

    await service.syncNow(reason: 'first', force: true);
    expect(apiClient.calls, hasLength(1));

    apiClient.fail = false;
    await service.retryPending(reason: 'retry');

    expect(apiClient.calls, hasLength(2));
    expect(apiClient.calls.last.policyVersion, 1);
  });

  test('force sync keeps version when snapshot is unchanged', () async {
    final service = PushAccessPolicySyncService(
      identity: identity,
      storage: storage,
      pushApiClient: apiClient,
    );

    await service.syncNow(reason: 'first', force: true);
    await service.syncNow(reason: 'second', force: true);

    expect(apiClient.calls, hasLength(2));
    expect(apiClient.calls.first.policyVersion, 1);
    expect(apiClient.calls.last.policyVersion, 1);
  });

  test('retries stale server policy with version above effective', () async {
    apiClient.stalePolicyVersion = 2;
    final service = PushAccessPolicySyncService(
      identity: identity,
      storage: storage,
      pushApiClient: apiClient,
    );

    await service.syncNow(reason: 'unblock', force: true);

    expect(apiClient.calls, hasLength(2));
    expect(apiClient.calls.first.policyVersion, 1);
    expect(apiClient.calls.last.policyVersion, 3);

    await service.syncNow(reason: 'unchanged', force: true);

    expect(apiClient.calls, hasLength(3));
    expect(apiClient.calls.last.policyVersion, 3);
  });

  test('uses runtime push resolver before storage endpoints', () async {
    await storage.getSettings().delete('push_servers');
    final service = PushAccessPolicySyncService(
      identity: identity,
      storage: storage,
      pushApiClient: apiClient,
      resolvePushBaseUris: () => <Uri>[Uri.parse('https://runtime.push')],
    );

    await service.syncNow(reason: 'runtime', force: true);

    expect(apiClient.calls, hasLength(1));
    expect(apiClient.calls.single.baseUri.toString(), 'https://runtime.push');
  });
}

class _FakePushApiClient extends PushApiClient {
  bool fail = false;
  int? stalePolicyVersion;
  final List<_PolicyCall> calls = <_PolicyCall>[];

  @override
  Future<PushAccessPolicySyncResult> syncAccessPolicy({
    required Uri baseUri,
    required IdentityService identity,
    required String userId,
    required bool allowMessagesOnlyFromContacts,
    required List<String> contactPeerIds,
    required List<String> blockedPeerIds,
    required int policyVersion,
    required String updatedAt,
    required String snapshotHash,
    String? bearerToken,
  }) async {
    calls.add(
      _PolicyCall(
        baseUri: baseUri,
        userId: userId,
        allowMessagesOnlyFromContacts: allowMessagesOnlyFromContacts,
        contactPeerIds: contactPeerIds,
        blockedPeerIds: blockedPeerIds,
        policyVersion: policyVersion,
        updatedAt: updatedAt,
      ),
    );
    if (fail) {
      throw const SocketException('offline');
    }
    final staleVersion = stalePolicyVersion;
    if (staleVersion != null && policyVersion < staleVersion) {
      return PushAccessPolicySyncResult(
        ok: true,
        stale: true,
        policyVersion: staleVersion,
      );
    }
    stalePolicyVersion = null;
    return PushAccessPolicySyncResult(
      ok: true,
      stale: false,
      policyVersion: policyVersion,
    );
  }
}

class _PolicyCall {
  final Uri baseUri;
  final String userId;
  final bool allowMessagesOnlyFromContacts;
  final List<String> contactPeerIds;
  final List<String> blockedPeerIds;
  final int policyVersion;
  final String updatedAt;

  const _PolicyCall({
    required this.baseUri,
    required this.userId,
    required this.allowMessagesOnlyFromContacts,
    required this.contactPeerIds,
    required this.blockedPeerIds,
    required this.policyVersion,
    required this.updatedAt,
  });
}

class _MemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> values = <String, String>{};

  Future<void> clear() async => values.clear();

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
