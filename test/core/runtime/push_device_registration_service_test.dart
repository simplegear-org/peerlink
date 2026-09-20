import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peerlink/core/node/node_facade.dart';
import 'package:peerlink/core/runtime/push_device_registration_service.dart';
import 'package:peerlink/core/runtime/storage_service.dart';

void main() {
  late Directory tempDir;
  late StorageService storage;
  late _FakeNodeFacade facade;
  late DateTime now;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('peerlink_push_reg_test_');
    storage = StorageService();
    await storage.initForTesting(rootDirectory: tempDir);
    facade = _FakeNodeFacade();
    now = DateTime.fromMillisecondsSinceEpoch(100000);
    await storage.getSettings().put('fcm_token', 'token-1');
    await storage.getSettings().put(
      'push_servers',
      const <Map<String, dynamic>>[
        <String, dynamic>{'endpoint': 'https://push.example', 'paused': false},
      ],
    );
  });

  tearDown(() async {
    await StorageService.resetForTesting();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('registers once and skips while TTL is fresh', () async {
    final service = PushDeviceRegistrationService(
      facade: facade,
      storage: storage,
      now: () => now,
    );

    await service.registerIfDue(reason: 'startup');
    await service.registerIfDue(reason: 'resume');

    expect(facade.registerCalls, 1);
    expect(facade.lastToken, 'token-1');
    expect(facade.lastForce, isFalse);
    expect(facade.policySyncCalls, 2);
  });

  test('forces refresh after TTL expires', () async {
    final service = PushDeviceRegistrationService(
      facade: facade,
      storage: storage,
      now: () => now,
    );

    await service.registerIfDue(reason: 'startup');
    now = now.add(PushDeviceRegistrationService.defaultRefreshInterval);
    await service.registerIfDue(reason: 'resume');

    expect(facade.registerCalls, 2);
    expect(facade.lastForce, isTrue);
    expect(facade.policySyncCalls, 2);
  });

  test('force registers immediately after server import', () async {
    final service = PushDeviceRegistrationService(
      facade: facade,
      storage: storage,
      now: () => now,
    );

    await service.registerIfDue(reason: 'startup');
    await service.registerIfDue(reason: 'server_import', force: true);

    expect(facade.registerCalls, 2);
    expect(facade.lastForce, isTrue);
    expect(facade.policySyncCalls, 2);
  });

  test('allows registration when only APNS token exists', () async {
    await storage.getSettings().delete('fcm_token');
    await storage.getSettings().put('apns_token', 'apns-1');
    final service = PushDeviceRegistrationService(
      facade: facade,
      storage: storage,
      now: () => now,
    );

    await service.registerIfDue(reason: 'startup');

    expect(facade.registerCalls, 1);
    expect(facade.lastToken, isNull);
    expect(facade.policySyncCalls, 1);
  });

  test('policy sync still runs when registration has no endpoint', () async {
    await storage.getSettings().delete('push_servers');
    final service = PushDeviceRegistrationService(
      facade: facade,
      storage: storage,
      now: () => now,
    );

    await service.syncNow(reason: 'block_peer', forcePolicy: true);

    expect(facade.registerCalls, 0);
    expect(facade.policySyncCalls, 1);
  });

  test('policy sync still runs when registration fails', () async {
    facade.registerError = StateError('register failed');
    final service = PushDeviceRegistrationService(
      facade: facade,
      storage: storage,
      now: () => now,
    );

    await service.syncNow(
      reason: 'block_peer',
      forceRegister: true,
      forcePolicy: true,
    );

    expect(facade.registerCalls, 1);
    expect(facade.policySyncCalls, 1);
  });

  test(
    'joins concurrent sync requests instead of repeating registration',
    () async {
      final registerStarted = Completer<void>();
      final releaseRegister = Completer<void>();
      var registerCalls = 0;
      final service = PushDeviceRegistrationService(
        storage: storage,
        now: () => now,
        registerPushDeviceToken: (_, {force = false}) async {
          registerCalls += 1;
          registerStarted.complete();
          await releaseRegister.future;
        },
        syncAccessPolicy: ({required reason, force = false}) async {},
      );

      final first = service.syncNow(reason: 'startup', forceRegister: true);
      await registerStarted.future;
      final second = service.syncNow(
        reason: 'push_token_register',
        forceRegister: true,
      );
      releaseRegister.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(registerCalls, 1);
    },
  );
}

class _FakeNodeFacade implements NodeFacade {
  int registerCalls = 0;
  int policySyncCalls = 0;
  String? lastToken;
  bool? lastForce;
  Object? registerError;

  @override
  Future<void> registerPushDeviceToken(
    String? token, {
    bool force = false,
  }) async {
    registerCalls += 1;
    lastToken = token;
    lastForce = force;
    final error = registerError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> syncPushAccessPolicy({
    required String reason,
    bool force = false,
  }) async {
    policySyncCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
